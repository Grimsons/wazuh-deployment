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
