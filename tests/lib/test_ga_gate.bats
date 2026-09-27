#!/usr/bin/env bats
# Tests for lib/ga_gate.sh and scripts/check-ga-gate.sh
#
# The gate is evaluated from saved bodies so nothing here touches the
# network: a closed gate and an open gate must be equally reproducible.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

setup() {
    source "$REPO_ROOT/lib/ga_gate.sh"
}

# Real upstream shapes, trimmed to the fields the gate reads.
ga_release_json() {
    cat <<EOF
{
  "tag_name": "v$1",
  "draft": false,
  "prerelease": $2
}
EOF
}

stable_release_file() {
    cat <<'EOF'
Origin: 5.x/apt
Label: 5.x/apt
Suite: stable
Codename: stable
Date: Fri, 25 Sep 2026 10:00:00 UTC
Architectures: amd64 arm64
Components: main
MD5Sum:
 0123456789abcdef0123456789abcdef         44062343 Contents-amd64
SHA256:
 9a9d0d1f344afcb428ccdcee2a6b7ae0b81fd2cb414d30a0bace972640952467 44062343 Contents-amd64
 a2ca1d3956031c9ccffccc0ecec2247495105888ff3acf75513fef5f1ce4b9ea  2074765 Contents-amd64.gz
SHA512:
 0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000 44062343 Contents-amd64
EOF
}

# A channel carrying the four managed packages at the given upstream version.
stable_packages_index() {
    local version="$1" pkg
    for pkg in wazuh-manager wazuh-indexer wazuh-dashboard wazuh-agent; do
        cat <<EOF
Package: $pkg
Priority: extra
Section: admin
Architecture: amd64
Version: $version-1
Filename: pool/main/w/$pkg/${pkg}_${version}-1_amd64.deb
Size: 1234

EOF
    done
}

# ── version and channel derivation ────────────────────────────────────────────

@test "the gate targets 5.0.0 by default and is overridable" {
    [ "$(ga_gate_default_target)" = "5.0.0" ]
    WAZUH_GATE_TARGET=5.1.0 run ga_gate_default_target
    [ "$output" = "5.1.0" ]
}

@test "channel URLs derive the major channel and stable suite" {
    WAZUH_GATE_PACKAGES_BASE=https://packages.wazuh.com
    [ "$(ga_gate_release_index_url 5.0.0)" = "https://packages.wazuh.com/5.x/apt/dists/stable/Release" ]
    [ "$(ga_gate_packages_index_url 5.0.0)" = "https://packages.wazuh.com/5.x/apt/dists/stable/main/binary-amd64/Packages" ]
    [ "$(ga_gate_release_index_url 4.14.5)" = "https://packages.wazuh.com/4.x/apt/dists/stable/Release" ]
}

@test "a trailing package repository base does not double the slash" {
    WAZUH_GATE_PACKAGES_BASE=https://mirror.example/wazuh/
    [ "$(ga_gate_release_index_url 5.0.0)" = "https://mirror.example/wazuh/5.x/apt/dists/stable/Release" ]
}

@test "the release API is queried for the exact tag" {
    WAZUH_GATE_GITHUB_API=https://api.github.com
    [ "$(ga_gate_release_api_url 5.0.0)" = "https://api.github.com/repos/wazuh/wazuh/releases/tags/v5.0.0" ]
}

# ── Debian revision handling ──────────────────────────────────────────────────

@test "only a trailing packaging revision is stripped" {
    [ "$(ga_gate_strip_revision 4.14.8-1)" = "4.14.8" ]
    [ "$(ga_gate_strip_revision 5.0.0-12)" = "5.0.0" ]
    [ "$(ga_gate_strip_revision 5.0.0)" = "5.0.0" ]
}

@test "a pre-release suffix survives revision stripping" {
    # 5.0.0-beta2 must keep its suffix so it cannot match a 5.0.0 target.
    [ "$(ga_gate_strip_revision 5.0.0-beta2)" = "5.0.0-beta2" ]
    run ga_gate_target_is_prerelease "5.0.0-beta2"
    [ "$status" -eq 0 ]
    run ga_gate_target_is_prerelease "5.0.0"
    [ "$status" -ne 0 ]
}

# ── check 1: GA release ───────────────────────────────────────────────────────

@test "a published non-prerelease release opens the release check" {
    run ga_gate_has_ga_release "$(ga_release_json 5.0.0 false)" "5.0.0"
    [ "$status" -eq 0 ]
}

@test "a pre-release does not satisfy the GA release check" {
    run ga_gate_has_ga_release "$(ga_release_json 5.0.0-beta5 true)" "5.0.0"
    [ "$status" -ne 0 ]
}

@test "a beta5 tag is not accepted as the 5.0.0 tag" {
    # Guards against a substring match: v5.0.0-beta5 must not satisfy v5.0.0.
    run ga_gate_has_ga_release "$(ga_release_json 5.0.0-beta5 true)" "5.0.0"
    [ "$status" -ne 0 ]
}

@test "a draft release is rejected even when tagged" {
    cat > "$BATS_TEST_TMPDIR/draft.json" <<'EOF'
{
  "tag_name": "v5.0.0",
  "draft": true,
  "prerelease": false
}
EOF
    run ga_gate_has_ga_release "$(cat "$BATS_TEST_TMPDIR/draft.json")" "5.0.0"
    [ "$status" -ne 0 ]
}

@test "an unpublished tag (API 404 body) fails the release check" {
    cat > "$BATS_TEST_TMPDIR/404.json" <<'EOF'
{
  "message": "Not Found",
  "documentation_url": "https://docs.github.com/rest/releases/releases#get-a-release-by-tag-name",
  "status": "404"
}
EOF
    run ga_gate_has_ga_release "$(cat "$BATS_TEST_TMPDIR/404.json")" "5.0.0"
    [ "$status" -ne 0 ]
}

@test "an empty response fails the release check instead of passing vacuously" {
    run ga_gate_has_ga_release "" "5.0.0"
    [ "$status" -ne 0 ]
}

# ── check 2: checksummed channel ──────────────────────────────────────────────

@test "a Release file with SHA256 and SHA512 digest sections passes" {
    run ga_gate_release_file_has_checksums "$(stable_release_file)"
    [ "$status" -eq 0 ]
}

@test "a Release file with only MD5Sum digests is rejected" {
    run ga_gate_release_file_has_checksums "$(printf 'Origin: 5.x/apt\nMD5Sum:\n 0123456789abcdef0123456789abcdef 44062343 Contents-amd64\n')"
    [ "$status" -ne 0 ]
}

@test "a Release file with an empty digest section is rejected" {
    run ga_gate_release_file_has_checksums "$(printf 'Origin: 5.x/apt\nSHA256:\nMD5Sum:\n 0123456789abcdef0123456789abcdef 44062343 Contents-amd64\n')"
    [ "$status" -ne 0 ]
}

@test "an S3 AccessDenied body is not mistaken for a published channel" {
    # What packages.wazuh.com actually returns for an unpublished 5.x suite.
    run ga_gate_release_file_has_checksums '<?xml version="1.0" encoding="UTF-8"?>
<Error><Code>AccessDenied</Code><Message>Access Denied</Message></Error>'
    [ "$status" -ne 0 ]
}

# ── check 3: version present in the stable channel ────────────────────────────

@test "a channel carrying the target version passes" {
    run ga_gate_package_index_has_version "$(stable_packages_index 5.0.0)" "5.0.0"
    [ "$status" -eq 0 ]
}

@test "a channel carrying only some managed packages is rejected" {
    partial="$(printf 'Package: wazuh-manager\nVersion: 5.0.0-1\n\n')"
    run ga_gate_package_index_has_version "$partial" "5.0.0"
    [ "$status" -ne 0 ]
}

@test "a channel serving a different version is rejected" {
    run ga_gate_package_index_has_version "$(stable_packages_index 5.0.1)" "5.0.0"
    [ "$status" -ne 0 ]
}

@test "a pre-release build in the channel does not satisfy a GA target" {
    run ga_gate_package_index_has_version "$(stable_packages_index 5.0.0-beta5)" "5.0.0"
    [ "$status" -ne 0 ]
}

# ── the CLI, replayed from fixtures ───────────────────────────────────────────

gate_fixture_dir() {
    local dir="$BATS_TEST_TMPDIR/fixtures-$1"
    mkdir -p "$dir"
    printf '%s' "$2" > "$dir/release.json"
    printf '%s' "$3" > "$dir/Release"
    printf '%s' "$4" > "$dir/Packages"
    printf '%s' "$dir"
}

run_gate() {
    run "$REPO_ROOT/scripts/check-ga-gate.sh" --fixture-dir "$1" --target "${2:-5.0.0}"
}

@test "the gate opens only when all three checks pass" {
    dir="$(gate_fixture_dir open \
        "$(ga_release_json 5.0.0 false)" \
        "$(stable_release_file)" \
        "$(stable_packages_index 5.0.0)")"
    run_gate "$dir"
    [ "$status" -eq 0 ]
    [[ "$output" == *"GATE OPEN"* ]]
}

@test "the gate stays closed while upstream is still pre-release" {
    dir="$(gate_fixture_dir beta \
        "$(ga_release_json 5.0.0-beta5 true)" \
        "$(stable_release_file)" \
        "$(stable_packages_index 5.0.0-beta5)")"
    run_gate "$dir"
    [ "$status" -eq 1 ]
    [[ "$output" == *"GATE CLOSED"* ]]
}

@test "the gate stays closed when the 5.x channel is not published" {
    dir="$(gate_fixture_dir nopackages \
        "$(ga_release_json 5.0.0 false)" \
        "$(stable_release_file)" \
        "")"
    run_gate "$dir"
    [ "$status" -eq 1 ]
    [[ "$output" == *"not in the stable channel"* ]]
}

@test "an unreachable upstream closes the gate rather than passing it" {
    dir="$BATS_TEST_TMPDIR/empty"
    mkdir -p "$dir"
    run_gate "$dir"
    [ "$status" -eq 1 ]
    [[ "$output" == *"GATE CLOSED"* ]]
}

@test "a pre-release target is refused before any request is made" {
    run "$REPO_ROOT/scripts/check-ga-gate.sh" --target 5.0.0-beta5 --fixture-dir /nonexistent
    [ "$status" -eq 1 ]
    [[ "$output" == *"can never open this gate"* ]]
}

# ── the pin flip stays gated ──────────────────────────────────────────────────

@test "the default pin is not a 5.x version while the gate is closed" {
    # VERSION.json is the pin this gate authorises.  Flipping it is the
    # Phase 7 action that only an open gate permits, so a 5.x pin here
    # means someone flipped it without the evidence.
    version="$(awk -F'"' '/"version"[[:space:]]*:/ { print $4; exit }' "$REPO_ROOT/VERSION.json")"
    case "$version" in
        5.*) false "VERSION.json is pinned to $version; the GA gate has not been satisfied" ;;
        *)   true ;;
    esac
}

@test "the gate is reachable from make" {
    run grep -n "^ga-gate:" "$REPO_ROOT/Makefile"
    [ "$status" -eq 0 ]
}

@test "the pin flip is documented as gated on this check" {
    run grep -rn "check-ga-gate" "$REPO_ROOT/docs/operations/upgrade.md"
    [ "$status" -eq 0 ]
}
