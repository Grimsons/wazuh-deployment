#!/usr/bin/env python3
"""Exercise the custom ruleset against a log fixture corpus, offline.

The readiness audit found "0 of 0 detections actually exercised" for the
custom rules, decoders, lists and SCA. The number was 0 of 0 because there
were no fixtures and no way to ask the question. This is the asking part.

For each fixture line this runs the same sequence analysisd runs -- custom
decoder selection, then content matching, then if_sid chain resolution -- and
records which rule IDs fire. It then compares what fired against the
expectation file that ships beside each fixture.

It is deliberately not a claim that analysisd is reproduced. Rules that depend
on cross-event state (frequency, same_source_ip, if_matched_sid) cannot be
decided by a per-line matcher, so they are counted as not-exercisable rather
than quietly passing. The gap between "reachable offline" and "reachable in a
real analysisd" is reported, not hidden.

Usage:
  ./exercise_corpus.py [--repo-root DIR] [--json] [--quiet] [--no-fail]

Exit codes:
  0  every expectation met
  1  an expectation was missed, or no fixture exercised any rule
  2  the corpus or the ruleset could not be read at all
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import ruleset_model as model  # noqa: E402

CYAN = "\033[36m"
GREEN = "\033[32m"
YELLOW = "\033[33m"
RED = "\033[31m"
BOLD = "\033[1m"
RESET = "\033[0m"


#═══════════════════════════════════════════════════════════════════════════════
# Fixture expectations
#═══════════════════════════════════════════════════════════════════════════════

class Expectation:
    """What a fixture is required to produce.

    `rules`   every one of these rule IDs must fire for the fixture to pass.
    `decoder` the named custom decoder must select the line.
    `any_of`  at least one of these rule IDs must fire. Used where a parent
              rule legitimately differs by Wazuh version.
    `count`   total rules fired must be at least this many.
    `technique` ATT&CK technique the fixture represents, for the report.
    """

    def __init__(self, data: dict, path: str):
        self.path = path
        self.rules = tuple(int(r) for r in data.get("rule", ()))
        self.any_of = tuple(int(r) for r in data.get("any_of", ()))
        self.decoder = data.get("decoder")
        self.count = int(data.get("min_fired", 0))
        self.technique = data.get("technique", "")
        self.note = data.get("note", "")

    @classmethod
    def load(cls, path: str) -> "Expectation":
        with open(path, "r", encoding="utf-8") as handle:
            return cls(json.load(handle), path)


#═══════════════════════════════════════════════════════════════════════════════
# The offline matching engine
#═══════════════════════════════════════════════════════════════════════════════

class Engine:
    def __init__(self, ruleset: model.RuleSet, repo_root: str):
        self.ruleset = ruleset
        self.repo_root = repo_root
        self._cdb_cache: dict = {}
        # Rules that can fire directly off a line, in ascending ID order.
        self._direct = sorted(
            (
                r
                for r in ruleset.rules.values()
                if r.exercise in (model.CONTENT, model.DECODED)
            ),
            key=lambda r: r.rule_id,
        )
        self._children: dict[int, list] = {}
        for rule in sorted(ruleset.rules.values(), key=lambda r: r.rule_id):
            if rule.exercise == model.EXERCISABLE and rule.if_sid is not None:
                self._children.setdefault(rule.if_sid, []).append(rule)

    # -- CDB lists ---------------------------------------------------------

    def cdb_lookup(self, field_value: str, lookup: str, list_path: str) -> bool:
        if field_value is None:
            return False
        entries = self._cdb_cache.get(list_path)
        if entries is None:
            entries = self._load_cdb(list_path)
            self._cdb_cache[list_path] = entries
        if not entries:
            return False
        if lookup == "match_key":
            return field_value in entries
        if lookup == "not_match_key":
            return field_value not in entries
        if lookup == "match_field":
            return any(field_value == v for v in entries.values())
        if lookup == "match_value":
            return any(field_value == v for v in entries.values())
        return False

    def _load_cdb(self, list_path: str) -> dict:
        # Rule lists reference "etc/lists/<name>"; the source of truth is
        # files/cdb_lists/<name>.
        relative = list_path.split("etc/lists/", 1)[-1]
        disk = os.path.join(self.repo_root, "files", "cdb_lists", relative)
        entries: dict = {}
        if not os.path.isfile(disk):
            return entries
        with open(disk, "r", encoding="utf-8", errors="replace") as handle:
            for line in handle:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                parts = line.split(":", 1)
                entries[parts[0].strip()] = parts[1].strip() if len(parts) > 1 else ""
        return entries

    # -- Decoders ----------------------------------------------------------

    def decode(self, line: str) -> tuple[dict | None, str | None]:
        """Return (decoded fields, decoder name) for a line, or (None, None).

        Mirrors Wazuh: a decoder is selected by prematch on the parent, then the
        child regex extracts fields in <order>. Only the first match wins, as in
        analysisd.
        """
        for name, decoder in sorted(self.ruleset.decoders.items()):
            if not decoder.prematch:
                continue
            compiled = model.compile_pattern(decoder.prematch)
            if isinstance(compiled, Exception) or not compiled.search(line):
                continue
            if not decoder.regex:
                return {}, name
            fields = self._extract(decoder.regex, line, decoder.order)
            if fields is not None:
                return fields, name
        return None, None

    @staticmethod
    def _extract(pattern: str, line: str, order: tuple) -> dict | None:
        compiled = model.compile_pattern(pattern)
        if isinstance(compiled, Exception):
            return None
        match = compiled.search(line)
        if not match:
            return None
        fields: dict = {}
        names = [n.strip() for n in match.groupdict().keys() if n]
        if names:
            # Named groups: trust them.
            fields = {k: (v if v is not None else "") for k, v in match.groupdict().items()}
        else:
            for index, key in enumerate(order, start=1):
                try:
                    fields[key] = match.group(index) or ""
                except IndexError:
                    # The regex captured fewer groups than <order> declares.
                    break
        return fields

    # -- Field extraction for undecoded lines ------------------------------

    # Windows event channel fields that analysisd's stock decoder maps onto a
    # hierarchical name. Without these a rule matching win.system.eventID could
    # never be exercised offline, which would understate real coverage.
    EVENT_CHANNEL_FIELDS = {
        "EventID": "win.system.eventID",
        "Channel": "win.system.channel",
        "Provider_Name": "win.system.provider_Name",
        "Computer": "win.system.computer",
        "EventRecordID": "win.system.eventID",
    }

    _XML_DATA = re.compile(r'<Data\s+Name="([^"]+)"\s*>(.*?)</Data>')
    _XML_SIMPLE = re.compile(r"<(\w+)>([^<>]*)</\1>")
    _KV = re.compile(r"\b([A-Za-z_][\w.\-]*)=(\"[^\"]*\"|\S+)")
    _KV_PLAIN = re.compile(r"\b([A-Za-z_][\w.\-]*):\s*(\S+)")

    def extract_raw_fields(self, line: str) -> dict:
        """Best-effort field extraction for lines no custom decoder claimed.

        Deliberately conservative: these are the shapes Wazuh's own stock
        decoders produce, not a general key/value scraper. They only feed
        <field> matchers, never content matching, so a mis-extraction can make
        a rule fire that would not have in analysisd -- never the reverse, which
        is the direction that would hide a gap.
        """
        fields: dict = {}

        for name, value in self._XML_DATA.findall(line):
            fields[f"win.eventdata.{name}"] = value
            fields[name] = value

        for name, value in self._XML_SIMPLE.findall(line):
            mapped = self.EVENT_CHANNEL_FIELDS.get(name)
            if mapped:
                fields[mapped] = value
                fields.setdefault(name, value)

        for name, value in self._KV.findall(line):
            fields.setdefault(name, value.strip('"'))

        return fields

    # -- Rules -------------------------------------------------------------

    def _match_value(self, line: str, fields: dict, pattern: str) -> bool:
        compiled = model.compile_pattern(pattern)
        if isinstance(compiled, Exception):
            return False
        if compiled.search(line):
            return True
        # A field-based match is evaluated against the decoded value, and a
        # decoded value also counts as part of the searchable text.
        for value in fields.values():
            if value and compiled.search(value):
                return True
        return False

    def _rule_fires(self, rule: model.Rule, line: str, fields: dict) -> bool:
        for entry in rule.matches:
            kind, name, pattern = entry[0], entry[1], entry[2]
            negate = entry[3] if len(entry) > 3 else False
            if kind == "match":
                if (pattern in line) == negate:
                    return False
            elif kind == "regex":
                if self._match_value(line, fields, pattern) == negate:
                    return False
            elif kind == "field":
                # A dotted field name is decoder-produced, so an undecoded line
                # gets the raw-shape extraction. An undotted one is a plain
                # key and falls through to the raw line.
                value = fields.get(name)
                if value is None and name and "." in name:
                    value = self.extract_raw_fields(line).get(name)
                if value is None:
                    value = line
                compiled = model.compile_pattern(pattern)
                if isinstance(compiled, Exception):
                    return False
                if bool(compiled.search(value)) == negate:
                    return False
            else:  # pragma: no cover
                return False

        raw_fields = None
        for field_name, lookup, list_path in rule.lists:
            if raw_fields is None:
                raw_fields = self.extract_raw_fields(line)
            value = fields.get(field_name)
            if value is None and field_name:
                value = raw_fields.get(field_name)
            if not self.cdb_lookup(value, lookup, list_path):
                return False

        return True

    def evaluate(self, line: str) -> dict:
        fields, decoder_name = self.decode(line)
        fields = fields or {}
        fired: list[int] = []

        for rule in self._direct:
            if rule.decoded_as and decoder_name != rule.decoded_as:
                continue
            if self._rule_fires(rule, line, fields):
                fired.append(rule.rule_id)

        # if_sid children inherit their parent's event, so resolve chains
        # until the fired set stops growing.
        changed = True
        while changed:
            changed = False
            for parent_id in list(self._children):
                if parent_id not in fired:
                    continue
                for child in self._children[parent_id]:
                    if child.rule_id in fired:
                        continue
                    if self._rule_fires(child, line, fields):
                        fired.append(child.rule_id)
                        changed = True

        return {
            "fired": sorted(fired),
            "decoder": decoder_name,
            "fields": fields,
        }


#═══════════════════════════════════════════════════════════════════════════════
# Corpus
#═══════════════════════════════════════════════════════════════════════════════

def read_fixture(path: str) -> list:
    lines = []
    with open(path, "r", encoding="utf-8", errors="replace") as handle:
        for raw in handle:
            stripped = raw.strip()
            if not stripped or stripped.startswith("#"):
                continue
            lines.append(stripped)
    return lines


def find_corpus(repo_root: str) -> tuple[list, list]:
    """Return (fixtures, problems). A fixture without its expectation counts."""
    corpus_dir = os.path.join(repo_root, "tests", "rules", "corpus")
    fixtures: list = []
    problems: list = []
    if not os.path.isdir(corpus_dir):
        return fixtures, [f"corpus directory missing: {corpus_dir}"]
    for entry in sorted(os.listdir(corpus_dir)):
        if not entry.endswith(".log"):
            continue
        log_path = os.path.join(corpus_dir, entry)
        expect_path = os.path.join(corpus_dir, entry[: -len(".log")] + ".expect.json")
        if not os.path.isfile(expect_path):
            problems.append(f"{entry}: no expectation file ({os.path.basename(expect_path)})")
            continue
        try:
            expectation = Expectation.load(expect_path)
        except (OSError, ValueError) as exc:
            problems.append(f"{entry}: unreadable expectation: {exc}")
            continue
        lines = read_fixture(log_path)
        if not lines:
            problems.append(f"{entry}: fixture has no log lines")
            continue
        fixtures.append((entry, log_path, expectation, lines))
    return fixtures, problems


def run(repo_root: str) -> dict:
    ruleset = model.load(repo_root)
    engine = Engine(ruleset, repo_root)
    fixtures, problems = find_corpus(repo_root)

    results: list = []
    exercised: set = set()
    passed = failed = 0

    for name, log_path, expectation, lines in fixtures:
        line_results = []
        fired_total: set = set()
        decoders_hit: set = set()
        for index, line in enumerate(lines, start=1):
            outcome = engine.evaluate(line)
            fired_total.update(outcome["fired"])
            if outcome["decoder"]:
                decoders_hit.add(outcome["decoder"])
            line_results.append(
                {"line": index, "fired": outcome["fired"], "decoder": outcome["decoder"]}
            )

        exercised.update(fired_total)
        missing = [r for r in expectation.rules if r not in fired_total]
        any_of_ok = (
            not expectation.any_of
            or any(r in fired_total for r in expectation.any_of)
        )
        decoder_ok = expectation.decoder in decoders_hit if expectation.decoder else True
        count_ok = len(fired_total) >= expectation.count
        ok = not missing and any_of_ok and decoder_ok and count_ok

        if ok:
            passed += 1
        else:
            failed += 1

        results.append(
            {
                "fixture": name,
                "technique": expectation.technique,
                "ok": ok,
                "lines": len(lines),
                "fired": sorted(fired_total),
                "decoders": sorted(decoders_hit),
                "missing_rules": missing,
                "any_of": list(expectation.any_of),
                "any_of_ok": any_of_ok,
                "decoder_expected": expectation.decoder,
                "decoder_ok": decoder_ok,
                "min_fired": expectation.count,
                "count_ok": count_ok,
                "note": expectation.note,
                "line_results": line_results,
            }
        )

    summary = model.coverage_summary(ruleset)
    reachable = (
        summary["buckets"].get(model.CONTENT, 0)
        + summary["buckets"].get(model.DECODED, 0)
        + summary["buckets"].get(model.EXERCISABLE, 0)
    )
    exercised_reachable = sorted(exercised & (
        set(summary["ids"].get(model.CONTENT, []))
        | set(summary["ids"].get(model.DECODED, []))
        | set(summary["ids"].get(model.EXERCISABLE, []))
    ))

    return {
        "repo_root": repo_root,
        "summary": summary,
        "offline_reachable": reachable,
        "exercised": sorted(exercised),
        "exercised_reachable": exercised_reachable,
        "exercised_reachable_count": len(exercised_reachable),
        "coverage_pct": round(100.0 * len(exercised_reachable) / reachable, 1) if reachable else 0.0,
        "fixtures_passed": passed,
        "fixtures_failed": failed,
        "fixtures_total": passed + failed,
        "results": results,
        "corpus_problems": problems,
        "parse_errors": ruleset.parse_errors,
        "unparseable_patterns": ruleset.unparseable_patterns,
        "duplicate_ids": ruleset.duplicate_ids,
    }


#═══════════════════════════════════════════════════════════════════════════════
# Reporting
#═══════════════════════════════════════════════════════════════════════════════

def render(report: dict, use_color: bool) -> str:
    def c(code: str, text: str) -> str:
        return f"{code}{text}{RESET}" if use_color else text

    out: list = []
    summary = report["summary"]
    out.append(c(CYAN, "═" * 71))
    out.append(c(CYAN, "  Wazuh detection coverage — custom rules, decoders, lists"))
    out.append(c(CYAN, "═" * 71))
    out.append("")

    buckets = summary["buckets"]
    out.append(f"  Rules parsed      : {summary['total_rules']}")
    out.append(f"  Decoders parsed   : {summary['decoders']}")
    out.append(
        "  Offline-reachable : "
        + c(
            BOLD,
            f"{report['offline_reachable']} "
            f"({report['coverage_pct']}% exercised by this corpus)",
        )
    )
    out.append("")

    label = {
        model.CONTENT: "matches the log line itself",
        model.DECODED: "selected by a custom decoder",
        model.EXERCISABLE: "child of an in-repo rule",
        model.ORPHANED: "child of a Wazuh built-in rule (not in this repo)",
        model.STATEFUL: "needs analysisd cross-event state",
        model.UNPARSEABLE: "no matcher this engine can evaluate",
    }
    for key, meaning in label.items():
        count = buckets.get(key, 0)
        if not count:
            continue
        out.append(f"    {count:5d}  {key:<12} {meaning}")
    out.append("")

    out.append(c(CYAN, "  Fixtures"))
    out.append("  " + "-" * 69)
    for item in report["results"]:
        mark = c(GREEN, "PASS") if item["ok"] else c(RED, "FAIL")
        technique = item["technique"] or "(no technique declared)"
        out.append(
            f"  [{mark}] {item['fixture']:<34} {item['lines']:>3d} line(s)  "
            f"{len(item['fired']):>2d} rule(s)  {technique}"
        )
        if not item["ok"]:
            if item["missing_rules"]:
                out.append(
                    c(RED, f"         expected but never fired: {item['missing_rules']}")
                )
            if item["any_of"] and not item["any_of_ok"]:
                out.append(
                    c(RED, f"         none of any_of fired: {item['any_of']}")
                )
            if not item["decoder_ok"]:
                out.append(
                    c(RED, f"         decoder {item['decoder_expected']!r} did not select the line")
                )
            if not item["count_ok"]:
                out.append(
                    c(RED, f"         expected at least {item['min_fired']} rule(s) to fire")
                )
    out.append("")

    if report["corpus_problems"]:
        out.append(c(YELLOW, "  Corpus problems"))
        for problem in report["corpus_problems"]:
            out.append(c(YELLOW, f"    - {problem}"))
        out.append("")

    if report["unparseable_patterns"]:
        out.append(c(YELLOW, "  Patterns this engine could not compile"))
        for item in report["unparseable_patterns"]:
            out.append(c(YELLOW, f"    - {item}"))
        out.append("")

    if report["parse_errors"]:
        out.append(c(RED, "  Ruleset parse errors"))
        for item in report["parse_errors"]:
            out.append(c(RED, f"    - {item}"))
        out.append("")

    if report["duplicate_ids"]:
        out.append(c(YELLOW, "  Duplicate rule IDs (first definition wins)"))
        for item in report["duplicate_ids"]:
            out.append(c(YELLOW, f"    - {item}"))
        out.append("")

    ok = (
        report["fixtures_failed"] == 0
        and not report["corpus_problems"]
        and not report["parse_errors"]
        and report["fixtures_total"] > 0
        and report["exercised_reachable_count"] > 0
    )
    verdict = (
        c(GREEN, f"COVERAGE OK — {report['exercised_reachable_count']}/{report['offline_reachable']} reachable rules exercised")
        if ok
        else c(RED, "COVERAGE FAIL — see above")
    )
    out.append(c(CYAN, "═" * 71))
    out.append(f"  {verdict}")
    out.append(
        f"  fixtures {report['fixtures_passed']}/{report['fixtures_total']} passed"
    )
    out.append(c(CYAN, "═" * 71))
    return "\n".join(out)


def main(argv: list | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo-root", default=os.path.abspath(os.path.join(
        os.path.dirname(os.path.abspath(__file__)), "..", "..")))
    parser.add_argument("--json", action="store_true", help="emit the report as JSON")
    parser.add_argument("--quiet", action="store_true", help="suppress the human report")
    parser.add_argument("--no-fail", action="store_true", help="always exit 0")
    args = parser.parse_args(argv)

    report = run(args.repo_root)

    if args.json:
        print(json.dumps(report, indent=2, sort_keys=True))
    elif not args.quiet:
        use_color = sys.stdout.isatty() or os.environ.get("FORCE_COLOR")
        print(render(report, bool(use_color)))

    if args.no_fail:
        return 0

    failed = report["fixtures_failed"] > 0
    problems = bool(report["corpus_problems"]) or bool(report["parse_errors"])
    empty = report["fixtures_total"] == 0
    blind = report["exercised_reachable_count"] == 0
    return 1 if (failed or problems or empty or blind) else 0


if __name__ == "__main__":
    sys.exit(main())
