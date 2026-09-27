#!/bin/bash
# Machine-checkable GA gate for the Wazuh release pin.
#
# The 5.0 upgrade is gated on Wazuh publishing a GA release *and* the
# matching package repository with checksums.  Eyeballing the release-notes
# index is not a gate: it is prose that changes without a commit, it is
# silent about whether the 5.x channel an install would actually fetch
# exists, and it says nothing about the checksums that would authenticate
# those packages.  This library reduces the gate to the three facts the
# VERSION.json pin flip actually depends on:
#
#   1. a published, non-draft, non-prerelease release exists for the
#      target version
#   2. the stable package channel for that major version publishes an
#      index carrying strong digests
#   3. the target version is present in that channel's package index
#
# Every predicate is a pure function of an already-fetched body, so the
# whole gate is exercisable offline.  scripts/check-ga-gate.sh does the
# fetching; nothing here touches the network.

# Endpoints are indirected so an operator (or a mirror) can point the gate
# somewhere else without editing the checks.
: "${WAZUH_GATE_PACKAGES_BASE:=https://packages.wazuh.com}"
: "${WAZUH_GATE_GITHUB_API:=https://api.github.com}"
: "${WAZUH_GATE_REPO:=wazuh/wazuh}"

# Packages whose presence in the channel proves the version is installable.
ga_gate_managed_packages() {
    printf '%s\n' "wazuh-manager" "wazuh-indexer" "wazuh-dashboard" "wazuh-agent"
}

# The release-notes default target.  Overridable so the gate can be pointed
# at a later line (5.1.0, ...) without editing the checks.
ga_gate_default_target() {
    printf '%s\n' "${WAZUH_GATE_TARGET:-5.0.0}"
}

# 5.0.0 -> 5.x
ga_gate_major_channel() {
    printf '%s.x\n' "${1%%.*}"
}

# A pre-release target can never satisfy the gate, whatever upstream does.
ga_gate_target_is_prerelease() {
    [[ "$1" == *-* ]]
}

# Strip a Debian packaging revision (4.14.8-1 -> 4.14.8) so a target
# upstream version matches the index entry that carries it.  Only a
# trailing -<digits> is removed, so a pre-release such as 5.0.0-beta2 is
# left intact and keeps failing the target comparison.
ga_gate_strip_revision() {
    if [[ "$1" =~ ^(.+)-[0-9]+$ ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
    else
        printf '%s\n' "$1"
    fi
}

ga_gate_release_api_url() {
    printf '%s\n' "${WAZUH_GATE_GITHUB_API%/}/repos/${WAZUH_GATE_REPO}/releases/tags/v$1"
}

ga_gate_release_index_url() {
    printf '%s\n' "${WAZUH_GATE_PACKAGES_BASE%/}/$(ga_gate_major_channel "$1")/apt/dists/stable/Release"
}

ga_gate_packages_index_url() {
    printf '%s\n' "${WAZUH_GATE_PACKAGES_BASE%/}/$(ga_gate_major_channel "$1")/apt/dists/stable/main/binary-amd64/Packages"
}

# 1. GA release exists.  $1 is the single-tag release JSON (the API returns
# 404 for an unpublished tag, which has none of these fields and so fails
# here).  An exact quoted tag match is deliberate: it keeps v5.0.0 from
# being satisfied by v5.0.0-beta5.
ga_gate_has_ga_release() {
    local release_json="$1" target="$2"

    printf '%s' "$release_json" | grep -qF "\"tag_name\": \"v${target}\"" || return 1
    printf '%s' "$release_json" | grep -qE '"draft":[[:space:]]*false' || return 1
    printf '%s' "$release_json" | grep -qE '"prerelease":[[:space:]]*false' || return 1
}

# 2. The channel publishes an index with strong digests.  MD5Sum alone is
# not enough to trust a mirror, so a SHA256 or SHA512 section with at least
# one entry is required.
ga_gate_release_file_has_checksums() {
    printf '%s\n' "$1" | awk '
        /^SHA(256|512):[[:space:]]*$/ { in_section = 1; next }
        /^[A-Za-z][A-Za-z0-9]*:/       { in_section = 0 }
        in_section && NF >= 2          { found = 1 }
        END { exit(found ? 0 : 1) }
    '
}

# 3. The target version is actually installable from the stable channel.
# An RC published to the pre-release host must not open the stable gate.
ga_gate_package_index_has_version() {
    local packages_index="$1" target="$2"

    printf '%s\n' "$packages_index" | awk -v target="$target" '
        /^Package: / { pkg = $2 }
        /^Version: / {
            version = $2
            sub(/-[0-9]+$/, "", version)
            if (version == target) { found[pkg] = 1 }
        }
        END {
            split("wazuh-manager wazuh-indexer wazuh-dashboard wazuh-agent", want, " ")
            for (i in want) { if (!(want[i] in found)) { exit 1 } }
        }
    '
}
