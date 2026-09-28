"""Select the index templates that apply to a given index name.

OpenSearch has no API that answers "which templates apply to this index", so
the 5.x rollover templates have to work it out themselves. Getting it wrong is
not a cosmetic problem: only the highest-priority matching template is applied
to an index, so a template declared with an index pattern that no shipped
template also matches would become the sole owner of that pattern's mappings.
"""

import fnmatch

from ansible.errors import AnsibleFilterError


def _patterns(template):
    """Index patterns of one template, under either response shape.

    GET /_index_template returns composable templates as
    {"name": ..., "index_template": {"index_patterns": [...]}} and legacy
    templates as {"name": ..., "order": ..., "index_patterns": [...]}.
    """
    if "index_template" in template:
        inner = template["index_template"]
        if isinstance(inner, list):
            return [p for entry in inner for p in entry.get("index_patterns", [])]
        return inner.get("index_patterns", [])
    return template.get("index_patterns", [])


def _is_catch_all(patterns):
    """True when every pattern is a bare '*' match.

    A catch-all is not evidence that the indexer shipped a template for a
    particular family, so callers that are checking "did the vendor own this
    pattern" can exclude them.
    """
    return bool(patterns) and all(pattern.strip() in ("*", ".*") for pattern in patterns)


def matching_templates(index_templates, index_name, include_catch_all=True):
    """Names of the templates whose index patterns cover index_name.

    Returned in ascending priority order so that composing them preserves the
    order OpenSearch itself would have applied them in: a later component
    overrides an earlier one.
    """
    if not index_name:
        raise AnsibleFilterError("matching_templates requires an index name")

    matched = []
    for template in index_templates or []:
        name = template.get("name")
        if not name:
            continue
        patterns = _patterns(template)
        if not any(fnmatch.fnmatchcase(index_name, pattern) for pattern in patterns):
            continue
        if not include_catch_all and _is_catch_all(patterns):
            continue
        matched.append((template.get("priority") or 0, name))

    return [name for _, name in sorted(matched, key=lambda pair: (pair[0], pair[1]))]


class FilterModule(object):
    def filters(self):
        return {"wazuh_matching_index_templates": matching_templates}
