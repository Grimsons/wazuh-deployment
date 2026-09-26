#!/usr/bin/env bats

LIB_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)/lib"

setup() {
    source "$LIB_DIR/version.sh"
}

@test "get_repository_version reads VERSION.json" {
    run get_repository_version "$LIB_DIR/../VERSION.json"
    [ "$status" -eq 0 ]
    [ "$output" = "4.14.5" ]
}

@test "set_default_wazuh_version uses repository version when unset" {
    unset WAZUH_VERSION
    set_default_wazuh_version
    [ "$WAZUH_VERSION" = "4.14.5" ]
}

@test "set_default_wazuh_version preserves an explicit override" {
    WAZUH_VERSION="5.0.0-beta2"
    set_default_wazuh_version
    [ "$WAZUH_VERSION" = "5.0.0-beta2" ]
}

@test "get_repository_version rejects a missing file" {
    run get_repository_version "/does/not/exist/VERSION.json"
    [ "$status" -ne 0 ]
}

@test "shared deployment config loads values without executing shell code" {
    config="$BATS_TEST_TMPDIR/deployment.conf"
    printf 'WAZUH_VERSION=5.0.0\nDEPLOYMENT_PROFILE=minimal\n' > "$config"
    source "$LIB_DIR/config.sh"
    unset WAZUH_VERSION DEPLOYMENT_PROFILE
    load_deployment_config "$config"
    [ "$WAZUH_VERSION" = "5.0.0" ]
    [ "$DEPLOYMENT_PROFILE" = "minimal" ]
}

@test "shared deployment config does not override environment values" {
    config="$BATS_TEST_TMPDIR/deployment.conf"
    printf 'WAZUH_VERSION=4.14.5\n' > "$config"
    source "$LIB_DIR/config.sh"
    WAZUH_VERSION="5.0.0"
    load_deployment_config "$config"
    [ "$WAZUH_VERSION" = "5.0.0" ]
}

@test "release consumers do not duplicate the pinned baseline" {
    run grep -n "4\.14\.5" \
        "$LIB_DIR/../Makefile" \
        "$LIB_DIR/../setup.sh" \
        "$LIB_DIR/../setup-tui.sh" \
        "$LIB_DIR/profiles.sh" \
        "$LIB_DIR/../scripts/migrate-from-main.sh"
    [ "$status" -eq 1 ]
}

@test "upgrade paths use version-derived manager path and Filebeat gate" {
    run grep -n "wazuh_manager_install_path" "$LIB_DIR/../playbooks/upgrade.yml"
    [ "$status" -eq 0 ]
    run grep -n "wazuh_use_filebeat.*bool" "$LIB_DIR/../playbooks/upgrade.yml"
    [ "$status" -eq 0 ]
}

@test "deployment smoke and system update paths gate Filebeat for 5.x" {
    run grep -n "wazuh_use_filebeat.*default(true).*bool" "$LIB_DIR/../site.yml"
    [ "$status" -eq 0 ]
    run grep -n "wazuh_use_filebeat.*default(true).*bool" "$LIB_DIR/../playbooks/system-update.yml"
    [ "$status" -eq 0 ]
}

@test "the version contract is emitted from one shared function" {
    for consumer in \
        "$LIB_DIR/../setup.sh" \
        "$LIB_DIR/../setup-tui.sh" \
        "$LIB_DIR/../scripts/migrate-from-main.sh"; do
        run grep -n "emit_version_contract >>" "$consumer"
        [ "$status" -eq 0 ]
    done
}

@test "generators do not carry their own copy of the version contract" {
    # Any of these literals in a generator means the contract was re-inlined
    # and can drift from lib/version.sh and roles/vars/main.yml.
    run grep -n "/var/wazuh-manager\|wazuh-manager.conf\|wazuh_is_5x:\|wazuh_use_filebeat:\|wazuh_manager_install_path:" \
        "$LIB_DIR/../setup.sh" \
        "$LIB_DIR/../setup-tui.sh" \
        "$LIB_DIR/../scripts/migrate-from-main.sh"
    [ "$status" -eq 1 ]
}

@test "the emitted version contract is valid YAML with the expected keys" {
    command -v python3 >/dev/null 2>&1 || skip "python3 not installed"

    emit_version_contract > "$BATS_TEST_TMPDIR/contract.yml"
    run python3 -c '
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
expected = {
    "wazuh_is_5x", "wazuh_is_prerelease", "wazuh_direct_download",
    "wazuh_manager_install_path", "wazuh_manager_config_file",
    "wazuh_manager_certs_path", "wazuh_manager_log_path",
    "wazuh_manager_owner", "wazuh_manager_group", "wazuh_use_filebeat",
    "wazuh_manager_cert_name",
}
missing = expected - set(doc)
if missing:
    sys.exit("missing keys: %s" % sorted(missing))
' "$BATS_TEST_TMPDIR/contract.yml"
    [ "$status" -eq 0 ]
}

@test "the emitted version contract performs no shell expansion" {
    # The fragment is Jinja evaluated by Ansible at deploy time, so any '$'
    # would have been eaten by the emitting shell.
    emit_version_contract > "$BATS_TEST_TMPDIR/contract.yml"
    run grep -c '\$' "$BATS_TEST_TMPDIR/contract.yml"
    [ "$output" = "0" ]
}

