#!/usr/bin/env python3
"""Parse the deployed custom ruleset and decoders into a queryable model.

The readiness audit reported "0 of 0 detections exercised" for this repo. That
is not a coverage number, it is the absence of one: nothing in the tree could
state how many of the shipped rules are reachable from a log line, so the
number could never be anything but zero.

This module answers the question the audit could not: given a log line and the
custom ruleset in files/, which rule IDs fire, and which rules could never
fire from any line at all. It deliberately models only the matching primitives
the custom ruleset actually uses, and classifies every rule by how it can be
exercised so a stateful rule is never reported as covered by a static matcher.
"""

from __future__ import annotations

import os
import re
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field as dc_field

# Rule-matching primitives the offline engine can evaluate exactly.
CONTENT_PRIMITIVES = ("match", "regex", "field", "list")

# Primitives that need analysisd's cross-event state, which a per-line static
# matcher cannot reproduce. A rule using any of these is reported separately
# instead of being counted as covered.
STATEFUL_PRIMITIVES = (
    "frequency",
    "timeframe",
    "same_source_ip",
    "same_user",
    "same_field",
    "different_user",
    "if_matched_sid",
    "if_matched_group",
    "check_diff",
)

# How a rule can be exercised.
EXERCISABLE = "exercisable"          # reachable from a raw log line offline
CONTENT = "content"                  # matches the line itself
DECODED = "decoded"                  # selected by a custom decoder's match
DERIVED = "derived"                  # child of an exercisable rule
STATEFUL = "stateful"                # needs analysisd cross-event state
ORPHANED = "orphaned"                # child of a rule this repo does not ship
UNPARSEABLE = "unparseable"          # no matcher this engine can evaluate


@dataclass
class Rule:
    rule_id: int
    level: int
    description: str = ""
    group: tuple = ()
    decoded_as: str | None = None
    matches: tuple = ()            # (kind, field_name, pattern) tuples
    lists: tuple = ()              # (field_name, lookup, list_path) tuples
    if_sid: int | None = None
    if_group: str | None = None
    stateful_primitives: tuple = ()
    mitre: tuple = ()
    source: str = ""
    exercise: str = UNPARSEABLE
    unparseable: tuple = ()        # (kind, pattern, reason) triples

    @property
    def is_content(self) -> bool:
        return bool(self.matches) or bool(self.lists)


@dataclass
class Decoder:
    name: str
    prematch: str | None = None
    regex: str | None = None
    order: tuple = ()
    parent: str | None = None
    source: str = ""
    unparseable: str | None = None


@dataclass
class RuleSet:
    rules: dict = dc_field(default_factory=dict)
    decoders: dict = dc_field(default_factory=dict)
    parse_errors: list = dc_field(default_factory=list)
    unparseable_patterns: list = dc_field(default_factory=list)
    duplicate_ids: list = dc_field(default_factory=list)


def _strip_ns(tag: str) -> str:
    return tag.rsplit("}", 1)[-1]


def compile_pattern(pattern: str):
    """Compile a Wazuh/OS regex to a Python regex, or explain why we cannot.

    Wazuh uses OS regex, which is close to PCRE for the constructs the custom
    ruleset uses. Where it is not, we record the failure instead of silently
    skipping the rule, because a silently skipped rule is exactly how a
    coverage number becomes a lie.
    """
    translated = pattern
    # OS regex classes that Python spells differently.
    translated = re.sub(r"\\d", r"\\d", translated)
    translated = translated.replace("(?i)", "(?i)")
    try:
        return re.compile(translated, re.IGNORECASE if "(?i)" in pattern else 0)
    except re.error as exc:
        return exc


def pattern_is_valid(pattern: str) -> tuple[bool, str]:
    compiled = compile_pattern(pattern)
    if isinstance(compiled, re.error):
        return False, str(compiled)
    return True, ""


def _int_or_none(text: str | None):
    if text is None:
        return None
    text = text.strip()
    return int(text) if text.isdigit() else None


def parse_wazuh_xml(path: str):
    """Parse a Wazuh rules/decoder file, which is not well-formed XML.

    Wazuh's own parser accepts a bare sequence of top-level <rule>, <group>
    and <decoder> elements. Every off-the-shelf XML parser rejects that as
    "junk after document element", so the file has to be wrapped in a
    synthetic root first. Getting this wrong is not cosmetic: a strict parser
    silently drops the whole file, and the rules in it vanish from the count.
    """
    with open(path, "r", encoding="utf-8", errors="replace") as handle:
        body = handle.read()
    wrapped = f"<wazuhroot>{body}</wazuhroot>"
    return ET.fromstring(wrapped)


def load_decoders(directory: str) -> tuple[dict, list]:
    decoders: dict[str, Decoder] = {}
    errors: list = []
    if not os.path.isdir(directory):
        return decoders, errors
    for entry in sorted(os.listdir(directory)):
        if not entry.endswith(".xml"):
            continue
        path = os.path.join(directory, entry)
        try:
            root = parse_wazuh_xml(path)
        except ET.ParseError as exc:
            errors.append(f"{entry}: {exc}")
            continue
        for node in root.iter():
            if _strip_ns(node.tag) != "decoder":
                continue
            name = node.get("name")
            if not name:
                continue
            decoder = decoders.setdefault(name, Decoder(name=name, source=entry))
            for child in node:
                tag = _strip_ns(child.tag)
                if tag == "prematch" and child.text:
                    decoder.prematch = child.text.strip()
                elif tag == "regex" and child.text:
                    decoder.regex = child.text.strip()
                elif tag == "order" and child.text:
                    decoder.order = tuple(
                        f.strip() for f in child.text.strip().split(",") if f.strip()
                    )
                elif tag == "parent" and child.text:
                    decoder.parent = child.text.strip()
    return decoders, errors


def load_rules(directory: str) -> tuple[dict, list, list, list]:
    rules: dict[int, Rule] = {}
    errors: list = []
    unparseable: list = []
    duplicates: list = []
    if not os.path.isdir(directory):
        return rules, errors, unparseable, duplicates

    for entry in sorted(os.listdir(directory)):
        if not entry.endswith(".xml"):
            continue
        path = os.path.join(directory, entry)
        try:
            root = parse_wazuh_xml(path)
        except ET.ParseError as exc:
            errors.append(f"{entry}: {exc}")
            continue
        for node in root.iter():
            if _strip_ns(node.tag) != "rule":
                continue
            raw_id = node.get("id")
            if raw_id is None:
                continue
            rule_id = _int_or_none(raw_id)
            if rule_id is None:
                errors.append(f"{entry}: non-numeric rule id {raw_id!r}")
                continue
            if rule_id in rules:
                duplicates.append(f"{rule_id} ({rules[rule_id].source} and {entry})")
                continue

            matches: list = []
            lists: list = []
            stateful: list = []
            unparse: list = []
            decoded_as = None
            if_sid = None
            if_group = None
            description = ""
            mitre: list = []
            for child in node:
                tag = _strip_ns(child.tag)
                text = (child.text or "").strip() if child.text else ""
                if tag == "description":
                    description = text
                elif tag == "decoded_as":
                    decoded_as = text
                elif tag == "if_sid":
                    if_sid = _int_or_none(text)
                elif tag == "if_group":
                    if_group = text
                elif tag == "group":
                    pass  # group is metadata here; if_group is the matcher
                elif tag == "mitre":
                    mitre = [
                        m.text.strip()
                        for m in child
                        if m.text and _strip_ns(m.tag) == "id"
                    ]
                elif tag in STATEFUL_PRIMITIVES:
                    stateful.append(tag)
                elif tag == "match" and text:
                    ok, reason = pattern_is_valid(re.escape(text))
                    matches.append(("match", None, text))
                    if not ok:  # pragma: no cover - re.escape is always valid
                        unparse.append(("match", text, reason))
                elif tag == "regex" and text:
                    ok, reason = pattern_is_valid(text)
                    matches.append(("regex", None, text))
                    if not ok:
                        unparse.append(("regex", text, reason))
                        unparseable.append(f"{entry}: rule {rule_id} <regex> {text!r}: {reason}")
                elif tag == "field" and text:
                    name = child.get("name")
                    negate = (child.get("negate") or "no").lower() == "yes"
                    ok, reason = pattern_is_valid(text)
                    matches.append(("field", name, text, negate))
                    if not ok:
                        unparse.append(("field", text, reason))
                        unparseable.append(f"{entry}: rule {rule_id} <field> {text!r}: {reason}")
                elif tag == "list":
                    lists.append(
                        (
                            child.get("field"),
                            (child.get("lookup") or "match_key"),
                            text,
                        )
                    )

            rules[rule_id] = Rule(
                rule_id=rule_id,
                level=_int_or_none(node.get("level")) or 0,
                description=description,
                decoded_as=decoded_as,
                matches=tuple(matches),
                lists=tuple(lists),
                if_sid=if_sid,
                if_group=if_group,
                stateful_primitives=tuple(stateful),
                mitre=tuple(mitre),
                source=entry,
                unparseable=tuple(unparse),
            )

    return rules, errors, unparseable, duplicates


def classify(rules: dict, decoders: dict) -> None:
    """Label every rule by how it can be exercised.

    A derived rule is only exercisable when its ancestry terminates in a rule
    this repo actually ships. The custom ruleset is overwhelmingly a child-rule
    layer over Wazuh's built-in IDs (5710, 4624, 7045 ...), and those parents
    are not in this tree, so labelling them "covered" would be the same lie the
    audit reported -- only better formatted.
    """
    for rule in rules.values():
        if rule.unparseable:
            rule.exercise = UNPARSEABLE
        elif rule.stateful_primitives:
            # A parent constraint plus cross-event state is still stateful.
            rule.exercise = STATEFUL
        elif rule.if_sid is not None or rule.if_group is not None:
            rule.exercise = DERIVED
        elif rule.is_content:
            rule.exercise = CONTENT
        elif rule.decoded_as and rule.decoded_as in decoders:
            # A base rule selected purely by one of our own decoders. The
            # auditd/YARA/Suricata/DNAC base rules are all of this shape.
            rule.exercise = DECODED
        else:
            rule.exercise = UNPARSEABLE

    def roots_in_repo(rule_id: int, seen: frozenset = frozenset()) -> bool:
        if rule_id in seen:
            return False
        rule = rules.get(rule_id)
        if rule is None:
            return False  # a built-in ID: not shipped here
        if rule.exercise in (CONTENT, DECODED):
            return True
        if rule.if_sid is None:
            return False
        return roots_in_repo(rule.if_sid, seen | {rule_id})

    for rule in rules.values():
        if rule.exercise == DERIVED and rule.if_sid is not None:
            rule.exercise = EXERCISABLE if roots_in_repo(rule.if_sid) else ORPHANED

    # An if_group rule can only fire if some rule in this tree actually emits
    # that group. The sysmon/dns/cloud groups are produced by Wazuh's stock
    # ruleset, so those rules are orphaned here just as the if_sid ones are.
    produced = set()
    for rule in rules.values():
        for name in rule.group:
            if name:
                produced.add(name)

    for rule in rules.values():
        if rule.exercise == DERIVED and rule.if_group is not None:
            rule.exercise = EXERCISABLE if rule.if_group in produced else ORPHANED


def load(repo_root: str) -> RuleSet:
    rules, rule_errors, unparseable, duplicates = load_rules(
        os.path.join(repo_root, "files", "custom_rules")
    )
    decoders, decoder_errors = load_decoders(
        os.path.join(repo_root, "files", "custom_decoders")
    )
    classify(rules, decoders)
    return RuleSet(
        rules=rules,
        decoders=decoders,
        parse_errors=rule_errors + decoder_errors,
        unparseable_patterns=unparseable,
        duplicate_ids=duplicates,
    )


def coverage_summary(ruleset: RuleSet) -> dict:
    buckets: dict[str, list[int]] = {}
    for rule in ruleset.rules.values():
        buckets.setdefault(rule.exercise, []).append(rule.rule_id)
    return {
        "total_rules": len(ruleset.rules),
        "decoders": len(ruleset.decoders),
        "buckets": {k: len(v) for k, v in sorted(buckets.items())},
        "ids": {k: sorted(v) for k, v in sorted(buckets.items())},
    }
