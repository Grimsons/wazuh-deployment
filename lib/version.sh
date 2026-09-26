#!/bin/bash
# Shared release contract for shell entry points.
# VERSION.json is authoritative; callers may still override WAZUH_VERSION.

_VERSION_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

get_repository_version() {
    local version_file="${1:-$_VERSION_LIB_DIR/VERSION.json}"
    [[ -r "$version_file" ]] || return 1
    awk -F'"' '/"version"[[:space:]]*:/ { print $4; exit }' "$version_file"
}

default_wazuh_version() {
    get_repository_version || return 1
}

set_default_wazuh_version() {
    : "${WAZUH_VERSION:=$(default_wazuh_version)}"
    export WAZUH_VERSION
}

# Emit the version-derived group_vars fragment.
#
# setup.sh, setup-tui.sh and scripts/migrate-from-main.sh all generate
# group_vars/all/main.yml and all need the same release contract.  Emit it from
# one place so a 5.x change cannot drift between generators.  The runtime
# counterpart is roles/vars/main.yml; both must agree.
emit_version_contract() {
    cat <<'YAML'
# ═══════════════════════════════════════════════════════════════
# Version-Derived Variables (evaluated from wazuh_version above)
# ═══════════════════════════════════════════════════════════════
wazuh_is_5x: "{{ wazuh_version.split('.')[0] == '5' }}"
wazuh_is_prerelease: "{{ '-' in wazuh_version }}"
wazuh_direct_download: "{{ wazuh_is_prerelease }}"
wazuh_manager_install_path: "{{ '/var/wazuh-manager' if wazuh_is_5x else '/var/ossec' }}"
wazuh_manager_config_file: "{{ wazuh_manager_install_path }}/etc/{{ 'wazuh-manager.conf' if wazuh_is_5x else 'ossec.conf' }}"
wazuh_manager_certs_path: "{{ wazuh_manager_install_path }}/etc/certs"
wazuh_manager_log_path: "{{ wazuh_manager_install_path }}/logs"
wazuh_manager_owner: "{{ 'wazuh-manager' if wazuh_is_5x else 'wazuh' }}"
wazuh_manager_group: "{{ 'wazuh-manager' if wazuh_is_5x else 'wazuh' }}"
wazuh_use_filebeat: "{{ false if wazuh_is_5x else true }}"
wazuh_manager_cert_name: "{{ manager_node_name | default('server') }}"
YAML
}
