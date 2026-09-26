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
