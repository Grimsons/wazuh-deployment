#!/usr/bin/env bats
# Proves the indexer side of the 4.x/5.x boundary: that the OpenSearch config
# is correct for each major, that 5.x ISM policies target 5.x index families,
# that certificate paths are read from the config rather than assumed, and that
# the cross-major operations refuse rather than half-apply.
#
# No live indexer is available here, so the checks that would need one are
# recorded as known risks in docs/operations/indexer-cutover-5x.md rather than
# claimed as verified.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

setup() {
    if ! command -v ansible-playbook >/dev/null 2>&1; then
        skip "ansible-playbook not installed"
    fi
    if ! command -v python3 >/dev/null 2>&1; then
        skip "python3 not installed"
    fi

    WORK="$BATS_TEST_TMPDIR/work"
    rm -rf "$WORK"
    mkdir -p "$WORK/out"

    cat > "$WORK/probe.yml" <<'YAML'
---
- name: Render the indexer configuration and logic for one target version
  hosts: localhost
  connection: local
  gather_facts: false
  vars:
    indexer_repo_root: "{{ probe_repo_root }}"
  tasks:
    - name: Load the shared release contract
      ansible.builtin.include_vars:
        file: "{{ indexer_repo_root }}/roles/vars/main.yml"

    - name: Load the indexer role defaults
      ansible.builtin.include_vars:
        file: "{{ indexer_repo_root }}/roles/wazuh-indexer/defaults/main.yml"

    # The role's own filter_plugins directory is not on the plugin path for a
    # playbook outside the role, so the shipped template matching is exercised
    # through the role instead.
    - name: Write the version-selected contract
      ansible.builtin.copy:
        dest: "{{ playbook_dir }}/out/{{ item.key }}"
        mode: "0644"
        content: "{{ item.value }}"
      loop: "{{ resolved | dict2items }}"
      vars:
        resolved:
          is_5x: "{{ wazuh_is_5x | bool | lower }}"
          initial_nodes_setting: "{{ wazuh_indexer_initial_nodes_setting }}"
          index_schema: "{{ wazuh_indexer_index_schema }}"
          cross_major_supported: "{{ wazuh_indexer_cross_major_upgrade_supported | string | lower }}"

    - name: Template opensearch.yml for this major
      ansible.builtin.copy:
        dest: "{{ playbook_dir }}/out/opensearch.yml"
        mode: "0644"
        content: "{{ lookup('ansible.builtin.template', indexer_repo_root ~ '/roles/wazuh-indexer/templates/opensearch.yml.j2') }}"
      vars:
        wazuh_indexer_nodes:
          - { name: "indexer-1", ip: "10.0.0.1" }
          - { name: "indexer-2", ip: "10.0.0.2" }

    - name: Resolve certificate paths through the role
      ansible.builtin.include_role:
        name: wazuh-indexer
        tasks_from: certificate_paths
      vars:
        wazuh_indexer_certs_path: /etc/wazuh-indexer/certs
        wazuh_indexer_config_path: /etc/wazuh-indexer
        wazuh_indexer_nodes:
          - { name: "indexer-1", ip: "10.0.0.1" }
        indexer_node_name: "indexer-1"

    - name: Write the resolved certificate paths
      ansible.builtin.copy:
        dest: "{{ playbook_dir }}/out/cert-paths"
        mode: "0644"
        content: |
          {% for item in wazuh_indexer_cert_paths | dict2items %}
          {{ item.key }}={{ item.value }}
          {% endfor %}

    - name: Write the 5.x family table
      ansible.builtin.copy:
        dest: "{{ playbook_dir }}/out/families"
        mode: "0644"
        content: >-
          {{ wazuh_indexer_5x_families | dict2items
             | map(attribute='key') | list | join('\n') }}

    - name: Write the ISM policy bodies
      ansible.builtin.include_role:
        name: wazuh-indexer
        tasks_from: index_management_5x_policies
      vars:
        wazuh_indexer_5x_families: "{{ lookup('ansible.builtin.file', families_for_probe) | from_json }}"
        wazuh_retention_enabled: true
        wazuh_close_cold_indices: true

    - name: Serialise the ISM policy bodies
      ansible.builtin.copy:
        dest: "{{ playbook_dir }}/out/ism-bodies.json"
        mode: "0644"
        content: "{{ wazuh_5x_ism_bodies | to_nice_json }}"

    - name: Serialise the system index lists
      ansible.builtin.copy:
        dest: "{{ playbook_dir }}/out/system-indices.json"
        mode: "0644"
        content: "{{ wazuh_indexer_system_indices | to_nice_json }}"
YAML

    # A trimmed family table: the real one is small, but the probe only needs
    # one short-retention family (to prove cold is dropped) and one long one.
    cat > "$WORK/families.json" <<'JSON'
{
  "events": {"pattern": "wazuh-events-v5*", "alias": "wazuh-events-v5",
             "retention_days": 365, "primary_shards": 1, "replica_shards": 0},
  "metrics": {"pattern": "wazuh-metrics-*", "alias": "wazuh-metrics",
              "retention_days": 7, "primary_shards": 1, "replica_shards": 0}
}
JSON
}

# render <version> — resolves the contract, renders opensearch.yml and the 5.x
# logic for that version, writing everything under $WORK/out.
render() {
    local version="$1"
    cat > "$WORK/VERSION.json" <<JSON
{"version": "$version", "stage": "stable"}
JSON

    ANSIBLE_NOCOLOR=1 \
    ANSIBLE_LOCALHOST_WARNING=False \
    ANSIBLE_INVENTORY_UNPARSED_WARNING=False \
    ANSIBLE_DEPRECATION_WARNINGS=False \
    ANSIBLE_RETRY_FILES_ENABLED=False \
    ANSIBLE_ROLES_PATH="$REPO_ROOT/roles:$REPO_ROOT" \
        ansible-playbook -i localhost, -c local "$WORK/probe.yml" \
        -e "probe_repo_root=$REPO_ROOT" \
        -e "families_for_probe=$WORK/families.json" \
        >"$WORK/ansible.log" 2>&1
}

rendered() {
    cat "$WORK/out/$1"
}

# The probe fails the run if any of the role logic is broken, so surface the
# log rather than a bare non-zero exit when something is wrong.
require_render() {
    if ! render "$1"; then
        echo "--- ansible-playbook failed for $1 ---" >&2
        cat "$WORK/ansible.log" >&2
        return 1
    fi
}

# ══════════════════════════════════════════════════════════════════════════
# Release contract
# ══════════════════════════════════════════════════════════════════════════

@test "4.14.5 uses the OpenSearch 2.x cluster bootstrap key" {
    require_render "4.14.5"
    [ "$(rendered is_5x)" = "false" ]
    [ "$(rendered initial_nodes_setting)" = "cluster.initial_master_nodes" ]
    [ "$(rendered index_schema)" = "v4" ]
}

@test "5.0.0 uses the renamed cluster manager key" {
    require_render "5.0.0"
    [ "$(rendered is_5x)" = "true" ]
    [ "$(rendered initial_nodes_setting)" = "cluster.initial_cluster_manager_nodes" ]
    [ "$(rendered index_schema)" = "v5" ]
}

@test "a cross-major indexer upgrade is declared unsupported" {
    require_render "5.0.0"
    [ "$(rendered cross_major_supported)" = "false" ]
}

# ══════════════════════════════════════════════════════════════════════════
# Rendered opensearch.yml
# ══════════════════════════════════════════════════════════════════════════

@test "4.14.5 single-node rendering omits cluster bootstrap keys" {
    require_render "4.14.5"
    rendered opensearch.yml | grep -q '^discovery.type: single-node$'
    ! rendered opensearch.yml | grep -q '^cluster\.initial_master_nodes:'
    ! rendered opensearch.yml | grep -q 'initial_cluster_manager_nodes'
}

@test "5.0.0 single-node rendering omits cluster bootstrap keys" {
    require_render "5.0.0"
    rendered opensearch.yml | grep -q '^discovery.type: single-node$'
    ! rendered opensearch.yml | grep -q '^cluster\.initial_cluster_manager_nodes:'
    ! rendered opensearch.yml | grep -q 'cluster\.initial_master_nodes'
}

@test "4.14.5 keeps the compatibility override that 5.x removed" {
    require_render "4.14.5"
    rendered opensearch.yml | grep -q '^compatibility\.override_main_response_version: true'
}

@test "5.0.0 does not render the setting OpenSearch 3.x removed" {
    # A 5.x node that still defines this does not boot, so its absence is a
    # hard requirement rather than a preference.
    require_render "5.0.0"
    ! rendered opensearch.yml | grep -q 'compatibility.override_main_response_version'
}

@test "4.14.5 keeps the 4.x system index list unchanged" {
    require_render "4.14.5"
    for index in .opendistro-alerting-config .opendistro-anomaly-detector* \
                 .opendistro-notebooks .opensearch-observability \
                 .opendistro-asynchronous-search-response* \
                 .replication-metadata-store; do
        rendered opensearch.yml | grep -Fq -- "  - ${index}"
    done
}

@test "5.0.0 protects the Wazuh plugin system indices" {
    require_render "5.0.0"
    for index in .wazuh-content-manager-resource-locks .wazuh-cti-consumers \
                 .wazuh-content-manager-jobs .wazuh-internal-state; do
        rendered opensearch.yml | grep -Fq -- "  - ${index}"
    done
}

@test "5.0.0 drops the system indices of plugins 5.x no longer ships" {
    require_render "5.0.0"
    # anomaly detection, asynchronous search, observability and notebooks are
    # not part of the 5.x distribution, so these protect nothing.
    ! rendered opensearch.yml | grep -q 'opendistro-anomaly'
    ! rendered opensearch.yml | grep -q 'opendistro-notebooks'
    ! rendered opensearch.yml | grep -q 'opensearch-observability'
    ! rendered opensearch.yml | grep -q 'asynchronous-search'
}

@test "5.0.0 does not declare .wazuh-settings a system index" {
    # It is a normal index whose access the shipped roles grant explicitly.
    # Declaring it a system index would override those grants and make it
    # unreadable by the components meant to write it.
    require_render "5.0.0"
    ! rendered opensearch.yml | grep -q -- '  - \.wazuh-settings$'
}

@test "both majors still enable the default security index init" {
    # securityadmin and the 5.x init script both need a reachable cluster
    # before the security index exists, so this cannot be turned off.
    require_render "4.14.5"
    rendered opensearch.yml | grep -q '^plugins\.security\.allow_default_init_securityindex: true'
    require_render "5.0.0"
    rendered opensearch.yml | grep -q '^plugins\.security\.allow_default_init_securityindex: true'
}

# ══════════════════════════════════════════════════════════════════════════
# Certificate paths
# ══════════════════════════════════════════════════════════════════════════

@test "certificate paths are read out of the rendered config on 4.14.5" {
    require_render "4.14.5"
    grep -q '^node_cert=/etc/wazuh-indexer/certs/indexer.pem$' "$WORK/out/cert-paths"
    grep -q '^node_key=/etc/wazuh-indexer/certs/indexer-key.pem$' "$WORK/out/cert-paths"
    grep -q '^root_ca=/etc/wazuh-indexer/certs/root-ca.pem$' "$WORK/out/cert-paths"
}

@test "certificate paths are read out of the rendered config on 5.0.0" {
    require_render "5.0.0"
    grep -q '^node_cert=/etc/wazuh-indexer/certs/indexer.pem$' "$WORK/out/cert-paths"
    grep -q '^http_cert=/etc/wazuh-indexer/certs/indexer.pem$' "$WORK/out/cert-paths"
}

@test "absolute certificate paths are left alone" {
    # A path already rooted at / is not re-prefixed with the config directory.
    require_render "5.0.0"
    ! grep -q '/etc/wazuh-indexer//' "$WORK/out/cert-paths"
}

@test "a missing certificate setting fails instead of deploying nothing" {
    # The role must not fall through to a default path when the config no
    # longer names a certificate; that is the failure this parsing exists to
    # prevent.
    cat > "$WORK/missing.yml" <<'YAML'
---
- hosts: localhost
  connection: local
  gather_facts: false
  vars:
    indexer_repo_root: "{{ probe_repo_root }}"
  tasks:
    - ansible.builtin.include_vars:
        file: "{{ indexer_repo_root }}/roles/vars/main.yml"
    - ansible.builtin.include_vars:
        file: "{{ indexer_repo_root }}/roles/wazuh-indexer/defaults/main.yml"
    - ansible.builtin.include_role:
        name: wazuh-indexer
        tasks_from: certificate_paths
      vars:
        wazuh_indexer_certs_path: /etc/wazuh-indexer/certs
        wazuh_indexer_config_path: /etc/wazuh-indexer
        wazuh_indexer_nodes: [{ name: "indexer-1", ip: "10.0.0.1" }]
        indexer_node_name: "indexer-1"
YAML

    # The role's own template is rendered by the role's lookup, so remove the
    # setting from the real template for the duration of the probe instead.
    local backup="$WORK/opensearch.yml.j2"
    cp "$REPO_ROOT/roles/wazuh-indexer/templates/opensearch.yml.j2" "$backup"
    sed -i 's|^plugins\.security\.ssl\.http\.pemkey_filepath:.*|# removed by test|' \
        "$REPO_ROOT/roles/wazuh-indexer/templates/opensearch.yml.j2"

    local rc=0
    ANSIBLE_NOCOLOR=1 \
    ANSIBLE_LOCALHOST_WARNING=False \
    ANSIBLE_INVENTORY_UNPARSED_WARNING=False \
    ANSIBLE_DEPRECATION_WARNINGS=False \
    ANSIBLE_RETRY_FILES_ENABLED=False \
    ANSIBLE_ROLES_PATH="$REPO_ROOT/roles:$REPO_ROOT" \
        ansible-playbook -i localhost, -c local "$WORK/missing.yml" \
        -e "probe_repo_root=$REPO_ROOT" \
        >"$WORK/missing.log" 2>&1 || rc=$?

    cp "$backup" "$REPO_ROOT/roles/wazuh-indexer/templates/opensearch.yml.j2"

    [ "$rc" -ne 0 ]
    # The failure is the contract; Ansible may surface the task's assertion
    # through a structured result without preserving the assertion text.
}

# ══════════════════════════════════════════════════════════════════════════
# 5.x ISM policies
# ══════════════════════════════════════════════════════════════════════════

@test "5.x families are the four 5.x index families, not the 4.x ones" {
    require_render "5.0.0"
    python3 -c "
raw=open('$WORK/out/families').read().replace('\\\\n', '\\n')
assert raw.splitlines() == ['events', 'states', 'metrics', 'agent'], raw
"
    python3 -c "
import json,sys
f=json.load(open('$WORK/families.json'))
assert f['events']['pattern'] == 'wazuh-events-v5*', f
assert f['metrics']['pattern'] == 'wazuh-metrics-*', f
"
}

@test "the shipped family table names no 4.x index family" {
    # wazuh-alerts/archives/monitoring/statistics are 4.x names. Creating them
    # on a 5.x cluster produces indices no 5.x template or dashboard knows.
    ! grep -qE '^[[:space:]]+pattern: "wazuh-(alerts|archives|monitoring|statistics)-\*"' \
        "$REPO_ROOT/roles/wazuh-indexer/defaults/main.yml"
}

@test "one ISM policy is built per 5.x family" {
    require_render "5.0.0"
    python3 -c "
import json
b=json.load(open('$WORK/out/ism-bodies.json'))
ids=sorted(p['policy_id'] for p in b)
assert ids == ['wazuh-events-policy', 'wazuh-metrics-policy'], ids
"
}

@test "a 5.x policy targets only its own 5.x family" {
    require_render "5.0.0"
    python3 -c "
import json
b=json.load(open('$WORK/out/ism-bodies.json'))
for p in b:
    tpl=p['body']['policy']['ism_template']
    assert len(tpl) == 1, tpl
    assert tpl[0]['index_patterns'] == p['index_patterns'], p
    assert p['index_patterns'] == ['wazuh-' + ('events-v5*' if p['family']=='events' else 'metrics-*')], p
"
}

@test "a long-retention family keeps the hot warm cold delete lifecycle" {
    require_render "5.0.0"
    python3 -c "
import json
b={p['family']: p for p in json.load(open('$WORK/out/ism-bodies.json'))}
states=[s['name'] for s in b['events']['body']['policy']['states']]
assert states == ['hot', 'warm', 'cold', 'delete'], states
assert b['events']['reaches_cold'] is True
cold=[s for s in b['events']['body']['policy']['states'] if s['name']=='cold'][0]
assert cold['actions'][0] == {'read_only': {}}, cold
assert {'close': {}} in cold['actions'], cold
"
}

@test "a family whose retention is shorter than the cold threshold drops cold" {
    # A 7-day family transitioned to cold at 30 days can never reach cold, so
    # the state is dropped rather than left as dead configuration.
    require_render "5.0.0"
    python3 -c "
import json
b={p['family']: p for p in json.load(open('$WORK/out/ism-bodies.json'))}
states=[s['name'] for s in b['metrics']['body']['policy']['states']]
assert states == ['hot', 'warm', 'delete'], states
assert b['metrics']['reaches_cold'] is False
"
}

@test "every 5.x policy ends in a delete state" {
    require_render "5.0.0"
    python3 -c "
import json
for p in json.load(open('$WORK/out/ism-bodies.json')):
    states=p['body']['policy']['states']
    last=states[-1]
    assert last['name'] == 'delete', p['family']
    assert last['actions'] == [{'delete': {}}], p['family']
    assert last['transitions'] == [], p['family']
"
}

@test "5.x policies use only ISM actions available in OpenSearch 3.x" {
    require_render "5.0.0"
    python3 -c "
import json
allowed={'rollover','replica_count','force_merge','index_priority','read_only','close','delete','allocation'}
for p in json.load(open('$WORK/out/ism-bodies.json')):
    for s in p['body']['policy']['states']:
        for a in s['actions']:
            unknown=set(a) - allowed
            assert not unknown, (p['family'], s['name'], unknown)
"
}

# ══════════════════════════════════════════════════════════════════════════
# Index template composition
# ══════════════════════════════════════════════════════════════════════════

# The shipped-template matcher decides which existing template a new rollover
# template composes with. Getting it wrong either duplicates mappings or
# shadows the ones the 5.x indexer ships.
matcher() {
    python3 -c "
import sys, json
sys.path.insert(0, '$REPO_ROOT/roles/wazuh-indexer/filter_plugins')
from index_patterns import matching_templates
print(json.dumps(matching_templates(json.loads(sys.argv[1]), sys.argv[2])))
" "$1" "$2"
}

@test "the shipped template matcher finds the template that owns a family" {
    result=$(matcher '[{"name":"wazuh-events-v5","priority":50,
                      "index_template":{"index_patterns":["wazuh-events-v5*"]}},
                     {"name":"metrics","priority":50,
                      "index_patterns":["wazuh-metrics-*"]},
                     {"name":"legacy","priority":50,
                      "index_patterns":["wazuh-alerts-*"]}]' \
                     "wazuh-events-v5-000001")
    [ "$result" = '["wazuh-events-v5"]' ]
}

@test "the shipped template matcher reads both index template response shapes" {
    # Composable templates nest under index_template; legacy ones do not.
    result=$(matcher '[{"name":"composable","priority":1,
                      "index_template":{"index_patterns":["wazuh-states-*"]}},
                     {"name":"legacy","priority":1,
                      "index_patterns":["wazuh-states-*"]}]' \
                     "wazuh-states-000001")
    [ "$result" = '["composable", "legacy"]' ]
}

@test "the shipped template matcher returns matches in ascending priority" {
    # Components are applied in order, so a later one overrides an earlier one.
    result=$(matcher '[{"name":"high","priority":200,
                      "index_patterns":["wazuh-*"]},
                     {"name":"low","priority":1,
                      "index_patterns":["wazuh-events-v5*"]}]' \
                     "wazuh-events-v5-000001")
    [ "$result" = '["low", "high"]' ]
}

@test "the shipped template matcher can exclude a bare catch-all" {
    # A '*' template matching everything is not evidence that the vendor owns a
    # particular family, and must not satisfy the composition guard.
    templates='[{"name":"glob","priority":1,"index_template":[{"index_patterns":["*"]}]}]'
    [ "$(matcher "$templates" "wazuh-states-000001")" = '["glob"]' ]
    [ "$(matcher "$templates" "wazuh-states-000001" all)" = '[]' ] ||
        python3 -c "
import sys, json
sys.path.insert(0, '$REPO_ROOT/roles/wazuh-indexer/filter_plugins')
from index_patterns import matching_templates
t = json.loads('$templates')
assert matching_templates(t, 'wazuh-states-000001', include_catch_all=False) == []
"
}

@test "the 5.x role refuses to create a template with no shipped template to compose with" {
    grep -q 'wazuh_indexer_5x_require_shipped_template' \
        "$REPO_ROOT/roles/wazuh-indexer/defaults/main.yml"
    grep -q 'specific_matches' \
        "$REPO_ROOT/roles/wazuh-indexer/tasks/index_management_5x.yml"
}

# ══════════════════════════════════════════════════════════════════════════
# Cross-major refusals
# ══════════════════════════════════════════════════════════════════════════

@test "restore refuses a cross-major indexer restore before touching anything" {
    grep -q 'Refuse a cross-major indexer restore' "$REPO_ROOT/playbooks/restore.yml"
    # The guard must read the recorded major, not infer it from the target.
    grep -q 'indexer-major' "$REPO_ROOT/playbooks/backup.yml"
    grep -q 'major=' "$REPO_ROOT/playbooks/backup.yml"
}

@test "the cross-major guard compares against the target major, not a constant" {
    python3 -c "
import re
s = open('$REPO_ROOT/playbooks/restore.yml').read()
guard = s[s.index('Refuse a cross-major indexer restore'):]
assert 'restore_target_major' in guard, 'guard does not use the target major'
assert 'restore_source_majors' in guard, 'guard does not read the recorded major'
"
}

@test "restore selects the timestamped isolated legacy-4x archive" {
    python3 -c "
s = open('$REPO_ROOT/playbooks/restore.yml').read()
start = s.index('Set backup source path')
guard = s[start:s.index('Refuse an invalid or missing target version', start)]
assert \"+ '/' + restore_from\" in guard, 'legacy-4x path drops restore_from'
"
}

@test "restore fails closed when the effective target version is invalid" {
    python3 -c "
s = open('$REPO_ROOT/playbooks/restore.yml').read()
start = s.index('Resolve the effective target version')
guard = s[start:s.index('Refuse the legacy archive path', start)]
assert 'wazuh_effective_version' in guard, 'guard does not use the effective version contract'
assert 'Cannot safely restore without a valid target Wazuh version' in guard
assert 'is not match' in guard, 'guard does not reject malformed or missing versions'
assert 'restore_target_major | length > 0' not in s, 'cross-major guard can still be skipped'
"
}

@test "upgrade refuses a cross-major indexer upgrade" {
    grep -q 'Refuse a cross-major indexer upgrade' "$REPO_ROOT/playbooks/upgrade.yml"
}

@test "the indexer rolling-update play is gone" {
    ! grep -q 'Upgrade - Wazuh Indexer (Rolling Update)' "$REPO_ROOT/playbooks/upgrade.yml"
    ! grep -q 'PHASE 1: UPGRADE WAZUH INDEXER (Rolling)' "$REPO_ROOT/playbooks/upgrade.yml"
}

@test "the cutover runbook exists and says the data cannot be migrated" {
    runbook="$REPO_ROOT/docs/operations/indexer-cutover-5x.md"
    [ -f "$runbook" ]
    grep -qi 'no in-place upgrade, no snapshot restore' "$runbook"
    grep -q 'read-only' "$runbook"
}

@test "the cutover runbook records the unverified ISM risk rather than claiming it" {
    runbook="$REPO_ROOT/docs/operations/indexer-cutover-5x.md"
    grep -q 'ISM action compatibility is unverified' "$runbook"
    grep -q 'Known risks' "$runbook"
}

@test "snapshot restore docs warn that snapshots do not cross a major" {
    for doc in backup-restore disaster-recovery; do
        path="$REPO_ROOT/docs/operations/$doc.md"
        [ -f "$path" ]
        grep -qi 'same major' "$path"
    done
}

# ══════════════════════════════════════════════════════════════════════════
# 4.x path is untouched
# ══════════════════════════════════════════════════════════════════════════

@test "the 4.14.5 index management file is byte-identical to its pre-split state" {
    # The 4.x implementation was moved, not rewritten, so the 4.14.5 path cannot
    # have changed as a side effect of the 5.x work.
    command -v git >/dev/null 2>&1 || skip "git not installed"
    git -C "$REPO_ROOT" show \
        839e376:roles/wazuh-indexer/tasks/index_management.yml \
        > "$WORK/index_management_4x.expected" 2>/dev/null \
        || skip "reference commit 839e376 not available"
    diff -u "$WORK/index_management_4x.expected" \
        "$REPO_ROOT/roles/wazuh-indexer/tasks/index_management_4x.yml"
}

@test "the 4.x security and user tasks were moved, not rewritten" {
    command -v git >/dev/null 2>&1 || skip "git not installed"
    for pair in "security_init.yml security_init_4x.yml" \
                "security_users.yml security_users_4x.yml"; do
        set -- $pair
        git -C "$REPO_ROOT" show "839e376:roles/wazuh-indexer/tasks/$1" \
            > "$WORK/$2.expected" 2>/dev/null \
            || skip "reference commit 839e376 not available"
        diff -u "$WORK/$2.expected" "$REPO_ROOT/roles/wazuh-indexer/tasks/$2"
    done
}

@test "the majors are dispatched, not branched inside one implementation" {
    grep -q 'index_management_4x.yml' "$REPO_ROOT/roles/wazuh-indexer/tasks/index_management.yml"
    grep -q 'index_management_5x.yml' "$REPO_ROOT/roles/wazuh-indexer/tasks/index_management.yml"
    grep -q 'wazuh_is_5x' "$REPO_ROOT/roles/wazuh-indexer/tasks/index_management.yml"
}

# ══════════════════════════════════════════════════════════════════════════
# Field renames
# ══════════════════════════════════════════════════════════════════════════

@test "no shipped rule or decoder still references the 4.x data.user field" {
    # 5.x renamed the actor identity to data.dstuser, with data.srcuser for the
    # source. A reference left on the old name silently aggregates to nothing.
    ! grep -rEn '(^|[.\"'"'"'])data\.user\b' "$REPO_ROOT/files/"
}

@test "the cutover runbook records the actor field rename" {
    grep -q 'data.dstuser' "$REPO_ROOT/docs/operations/indexer-cutover-5x.md"
    grep -q 'data.srcuser' "$REPO_ROOT/docs/operations/indexer-cutover-5x.md"
}
