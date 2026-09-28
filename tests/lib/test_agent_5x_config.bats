#!/usr/bin/env bats
# Wazuh 5.0 agent migration regression suite.
#
# Two things are worth locking down here, because both are silent failures:
#
#   1. The 4.14.5 rendered config must not change. A 5.0 migration that quietly
#      drops a FIM directory or a rootcheck option on the way is worse than one
#      that fails, and nothing else in the suite would notice.
#   2. The 5.0 rendered config must contain none of the elements 5.0 removed.
#      Wazuh does not reject an unknown element at parse time, it logs
#      "Invalid element in the configuration" on every agent start, so a bad
#      template ships as a fleet-wide log warning rather than a play failure.
#
# The upgrade-path gate gets the same treatment: 4.9.0 < 4.14.0 is exactly the
# comparison a string compare gets wrong.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
AGENT_TEMPLATES="$REPO_ROOT/roles/wazuh-agent/templates"

setup() {
    if ! command -v ansible-playbook >/dev/null 2>&1; then
        skip "ansible-playbook not installed"
    fi
    if ! command -v python3 >/dev/null 2>&1; then
        skip "python3 not installed"
    fi

    WORK="$BATS_TEST_TMPDIR/work"
    rm -rf "$WORK"
    mkdir -p "$WORK"

    cat > "$WORK/render.yml" <<'YAML'
---
- name: Render an agent ossec.conf
  hosts: localhost
  connection: local
  gather_facts: false
  vars:
    ansible_system: StubOS
    ansible_os_family: StubOS
    ansible_distribution: StubOS
    ansible_distribution_major_version: "1"
    ansible_distribution_version: "1.0"
    ansible_hostname: testhost
    wazuh_manager_nodes:
      - { name: manager-1, ip: 10.0.0.1 }
      - { name: manager-2, ip: 10.0.0.2 }
  tasks:
    - name: Load the shared release contract
      ansible.builtin.include_vars:
        file: "{{ agent_repo_root }}/roles/vars/main.yml"

    - name: Load the agent defaults
      ansible.builtin.include_vars:
        file: "{{ agent_repo_root }}/roles/wazuh-agent/defaults/main.yml"

    - name: Write the rendered configuration
      ansible.builtin.copy:
        dest: "{{ agent_out }}"
        mode: "0644"
        content: "{{ lookup('ansible.builtin.template', agent_template) }}"
YAML

    cat > "$WORK/elements.py" <<'PY'
"""Flatten an ossec.conf into comparable (path, attrs, text) triples."""
import sys
import xml.etree.ElementTree as ET

root = ET.parse(sys.argv[1]).getroot()
out = []


def walk(el, path):
    here = f"{path}/{el.tag}"
    attrs = ",".join(f"{k}={v}" for k, v in sorted(el.attrib.items()))
    out.append((here, attrs, (el.text or "").strip()))
    for child in el:
        walk(child, here)


walk(root, "")
for triple in out:
    print("\t".join(triple))
PY
}

# render_agent <tpl> <version> <out> [key=value ...]
render_agent() {
    local tpl="$1" version="$2" out="$3"
    shift 3

    local -a extra=(
        -e "agent_repo_root=$REPO_ROOT"
        -e "agent_template=$AGENT_TEMPLATES/$tpl"
        -e "agent_out=$out"
        -e "wazuh_effective_version=$version"
    )
    for kv in "$@"; do
        extra+=(-e "$kv")
    done

    ANSIBLE_NOCOLOR=1 \
    ANSIBLE_REMOTE_TMP="$WORK/ansible-tmp" \
    ANSIBLE_LOCALHOST_WARNING=False \
    ANSIBLE_INVENTORY_UNPARSED_WARNING=False \
    ANSIBLE_DEPRECATION_WARNINGS=False \
    ANSIBLE_RETRY_FILES_ENABLED=False \
        ansible-playbook -i localhost, -c local "$WORK/render.yml" "${extra[@]}" \
        >"$WORK/ansible.log" 2>&1
}

# Every (path, attrs, text) triple in the rendered config.
elements() {
    python3 "$WORK/elements.py" "$1"
}

# Paths of every element with a given tag, e.g. element_paths file scan_on_start
element_paths() {
    elements "$1" | cut -f1 | grep -E "/$2\$" || true
}

# Number of elements with a given tag. Structural assertions run against the
# parsed config, not against grep: the templates carry explanatory comments
# that mention <agent>, <ssl> and 1517, and a raw grep matches those too.
count_elements() {
    elements "$1" | cut -f1 | grep -cE "/$2\$" || true
}

# Value of the first element with a given tag, e.g. element_value file endpoint
element_value() {
    elements "$1" | awk -F'\t' -v t="/$2\$" '$1 ~ t { print $3; exit }'
}

assert_parsed() {
    python3 -c "import xml.etree.ElementTree as ET; ET.parse('$1')"
}

# ─────────────────────────────────────────────────────────────────────────────
# 4.14.5 must be untouched
# ─────────────────────────────────────────────────────────────────────────────

@test "4.14.5 Linux renders a client block on 1514 and no agent block" {
    render_agent ossec.conf.j2 4.14.5 "$WORK/linux-4x.conf"
    assert_parsed "$WORK/linux-4x.conf"

    [ "$(count_elements "$WORK/linux-4x.conf" client)" = "1" ]
    [ "$(count_elements "$WORK/linux-4x.conf" agent)" = "0" ]
    [ "$(element_value "$WORK/linux-4x.conf" port)" = "1514" ]
}

@test "4.14.5 keeps client_buffer, rootcheck and the osquery-era surface" {
    render_agent ossec.conf.j2 4.14.5 "$WORK/linux-4x.conf"

    for tag in client_buffer check_files check_trojans rootkit_files; do
        [ "$(count_elements "$WORK/linux-4x.conf" "$tag")" -ge 1 ]
    done

    # scan_on_start is still valid on 4.x FIM, and it is the syscheck one.
    run element_paths "$WORK/linux-4x.conf" scan_on_start
    [ "$status" -eq 0 ]
    [[ "$output" == *"/syscheck/scan_on_start"* ]]
}

@test "4.14.5 macOS and Windows still render the 4.x client block" {
    render_agent ossec-macos.conf.j2 4.14.5 "$WORK/macos-4x.conf"
    render_agent ossec-windows.conf.j2 4.14.5 "$WORK/windows-4x.conf"

    for f in "$WORK/macos-4x.conf" "$WORK/windows-4x.conf"; do
        assert_parsed "$f"
        [ "$(count_elements "$f" client)" = "1" ]
        [ "$(count_elements "$f" agent)" = "0" ]
    done
}

# ─────────────────────────────────────────────────────────────────────────────
# 5.0 schema
# ─────────────────────────────────────────────────────────────────────────────

@test "5.0 renders an agent block with a single 1517 endpoint" {
    render_agent ossec.conf.j2 5.0.0 "$WORK/linux-5x.conf"
    assert_parsed "$WORK/linux-5x.conf"

    [ "$(count_elements "$WORK/linux-5x.conf" endpoint)" = "1" ]
    [ "$(element_value "$WORK/linux-5x.conf" endpoint)" = "10.0.0.1:1517" ]
    [ "$(count_elements "$WORK/linux-5x.conf" client)" = "0" ]

    # Server rotation is gone, so the second manager must not be emitted.
    run element_value "$WORK/linux-5x.conf" endpoint
    [[ "$output" != *"10.0.0.2"* ]]

    # Nothing may still dial the legacy port.
    run element_value "$WORK/linux-5x.conf" port
    [[ "$output" != *"1514"* ]]
}

@test "5.0 puts ssl as a sibling of manager under agent" {
    for tpl in ossec.conf.j2 ossec-macos.conf.j2 ossec-windows.conf.j2; do
        render_agent "$tpl" 5.0.0 "$WORK/ssl-5x.conf"
        assert_parsed "$WORK/ssl-5x.conf"

        # /ossec_config/agent/ssl must exist...
        run element_paths "$WORK/ssl-5x.conf" ssl
        [ "$status" -eq 0 ]
        [ "$output" = "/ossec_config/agent/ssl" ]

        # ...and must be the only one, i.e. not nested under <manager>.
        [ "$(count_elements "$WORK/ssl-5x.conf" ssl)" = "1" ]
    done
}

@test "5.0 emits a TLS 1.3 ciphersuite list, not a 4.x OpenSSL cipher string" {
    render_agent ossec.conf.j2 5.0.0 "$WORK/linux-5x.conf"

    run element_value "$WORK/linux-5x.conf" ciphers
    [ "$status" -eq 0 ]
    [[ "$output" == *"TLS_AES_256_GCM_SHA384"* ]]
    [[ "$output" != *"HIGH"* ]]
    [[ "$output" != *"@STRENGTH"* ]]
}

@test "5.0 drops the elements Wazuh removed" {
    for tpl in ossec.conf.j2 ossec-macos.conf.j2 ossec-windows.conf.j2; do
        render_agent "$tpl" 5.0.0 "$WORK/removed-5x.conf"
        assert_parsed "$WORK/removed-5x.conf"

        for tag in client_buffer crypto_method check_files check_trojans rootkit_files; do
            [ "$(count_elements "$WORK/removed-5x.conf" "$tag")" = "0" ]
        done
        run element_paths "$WORK/removed-5x.conf" skip_nfs
        [[ "$output" != *"/sca/skip_nfs"* ]]

        for wodle in osquery cis-cat open-scap; do
            [ "$(count_elements "$WORK/removed-5x.conf" "$wodle")" = "0" ]
        done
    done
}

@test "5.0 keeps scan_on_start only where it is still valid" {
    for tpl in ossec.conf.j2 ossec-macos.conf.j2 ossec-windows.conf.j2; do
        render_agent "$tpl" 5.0.0 "$WORK/scan-5x.conf"

        # Under <syscheck> it is an invalid element on 5.0.
        # Under <syscheck> it is an invalid element on 5.0, so no scan_on_start
        # may sit directly under it.
        run elements "$WORK/scan-5x.conf"
        [ "$status" -eq 0 ]
        run bash -c "echo \"$output\" | cut -f1 | grep -c '/syscheck/scan_on_start' || true"
        [ "$output" = "0" ]
    done
}

@test "5.0 declares the trust anchor the role deploys" {
    render_agent ossec.conf.j2 5.0.0 "$WORK/linux-5x.conf" \
        wazuh_agent_trust_anchor_path=/var/ossec/etc/certs/root-ca.pem

    [ "$(element_value "$WORK/linux-5x.conf" certificate_authorities)" \
        = "/var/ossec/etc/certs/root-ca.pem" ]
}

@test "the trust anchor default follows the platform" {
    local expected
    for spec in "Linux:/var/ossec/etc/certs/root-ca.pem" \
                "Darwin:/Library/Ossec/etc/certs/root-ca.pem" \
                "Windows:C:\Program Files (x86)\ossec-agent\certs\root-ca.pem"; do
        expected="${spec#*:}"
        render_agent ossec.conf.j2 5.0.0 "$WORK/anchor.conf" \
            "ansible_system=${spec%%:*}"
        [ "$(element_value "$WORK/anchor.conf" certificate_authorities)" = "$expected" ]
    done
}

# ─────────────────────────────────────────────────────────────────────────────
# Upgrade-path gate
# ─────────────────────────────────────────────────────────────────────────────

setup_gate() {
    cat > "$WORK/gate.yml" <<'YAML'
---
- name: Run the real 5.0 upgrade-path gate
  hosts: localhost
  connection: local
  gather_facts: false
  vars:
    # Neither Linux/Darwin/Windows, so the three version probes are skipped and
    # the supplied version is what the gate sees.
    ansible_system: StubOS
    ansible_os_family: StubOS
    wazuh_agent_is_5x: true
    wazuh_effective_version: "5.0.0"
    wazuh_agent_min_upgrade_source_version: "4.14.0"
    wazuh_agent_upgrade_path_enforced: true
    wazuh_agent_installed_version_override: "{{ gate_override | default(omit, true) }}"
  tasks:
    - name: Enforce the upgrade path
      ansible.builtin.include_tasks: "{{ agent_repo_root }}/roles/wazuh-agent/tasks/upgrade_path.yml"
YAML
}

run_gate() {
    local override="${1:-__omit__}"
    local -a extra=(-e "agent_repo_root=$REPO_ROOT")
    [[ "$override" != "__omit__" ]] && extra+=(-e "gate_override=$override")

    ANSIBLE_NOCOLOR=1 \
    ANSIBLE_LOCALHOST_WARNING=False \
    ANSIBLE_INVENTORY_UNPARSED_WARNING=False \
    ANSIBLE_DEPRECATION_WARNINGS=False \
    ANSIBLE_RETRY_FILES_ENABLED=False \
        ansible-playbook -i localhost, -c local "$WORK/gate.yml" "${extra[@]}" \
        >"$WORK/gate.log" 2>&1 || true
}

@test "the upgrade gate blocks every agent older than 4.14.0" {
    setup_gate
    for version in 4.3.0-1 4.9.0-1 4.13.1-1 4.13.99-1; do
        run_gate "$version"
        run grep -c "UPGRADE BLOCKED" "$WORK/gate.log"
        [ "$status" -eq 0 ]
        [ "$output" -ge 1 ]
    done
}

@test "the upgrade gate allows 4.14.0 and newer" {
    setup_gate
    for version in 4.14.0-1 4.14.5-1 4.14.5 5.0.0-beta5-1; do
        run_gate "$version"
        run grep -c "UPGRADE BLOCKED" "$WORK/gate.log"
        [ "$status" -ne 0 ]
    done
}

@test "the upgrade gate treats an undetectable version as a fresh install with a warning" {
    setup_gate

    # Nothing installed at all.
    run_gate
    run grep -c "UPGRADE BLOCKED" "$WORK/gate.log"
    [ "$status" -ne 0 ]
    run grep -c "Could not determine the installed Wazuh agent version" "$WORK/gate.log"
    [ "$status" -eq 0 ]

    # Installed by something this role does not manage.
    run_gate "not-a-version"
    run grep -c "Could not determine the installed Wazuh agent version" "$WORK/gate.log"
    [ "$status" -eq 0 ]
}

# ─────────────────────────────────────────────────────────────────────────────
# Manager-side centralized configuration
# ─────────────────────────────────────────────────────────────────────────────

@test "the manager group template drops syscheck scan_on_start and osquery on 5.0" {
    local group_conf="$REPO_ROOT/roles/wazuh-manager/templates/agent_group_conf.j2"

    # 5.0 guard on both removed constructs.
    run grep -c "not wazuh_is_5x | default(false) | bool" "$group_conf"
    [ "$status" -eq 0 ]
    [ "$output" -ge 2 ]
}

@test "the agent group template can express SCA on 5.0" {
    local group_conf="$REPO_ROOT/roles/wazuh-manager/templates/agent_group_conf.j2"

    run grep -c "<sca>" "$group_conf"
    [ "$status" -eq 0 ]
    run grep -c "OSQUERY_PACK_DROPPED" "$group_conf"
    [ "$status" -eq 0 ]
}
