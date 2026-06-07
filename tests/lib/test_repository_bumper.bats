#!/usr/bin/env bats
# Tests for tools/repository_bumper.sh
#
# NOTE: repository_bumper.sh runs `set -euo pipefail` at the top
# (it is a standalone script, not a library).  When we source it,
# these options leak into the test shell.  We restore safe defaults
# after each source to avoid `set -e` killing the test process on
# expected failures (e.g. grep returning 1 for no match).

setup_file() {
    export REPO_ROOT
    REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

    export TEST_DIR
    TEST_DIR="$(mktemp -d)"

    cat > "$TEST_DIR/VERSION.json" <<'EOF'
{"version": "4.14.5", "stage": "stable"}
EOF

    echo "wazuh_version: 4.14.5" > "$TEST_DIR/test_vars.yml"
    echo "Wazuh v4.14.5" > "$TEST_DIR/test_readme.md"
    mkdir -p "$TEST_DIR/tools"

    echo "any log" > "$TEST_DIR/repository_bumper_2025-01-01.log"
    echo "changelog entry" > "$TEST_DIR/CHANGELOG.md"
    echo "main script" > "$TEST_DIR/tools/repository_bumper.sh"

    mkdir -p "$TEST_DIR/sub"
    echo "version: 4.14.5" > "$TEST_DIR/sub/nested.yml"

    # Init git so git diff works inside update_version_in_files
    git -C "$TEST_DIR" init -q
    git -C "$TEST_DIR" config user.email "test@test.com"
    git -C "$TEST_DIR" config user.name "Test"
    git -C "$TEST_DIR" add -A
    git -C "$TEST_DIR" commit -q -m "initial"

    export SEARCH_DIR
    SEARCH_DIR="$(mktemp -d)"
    echo "version: 1.2.3" > "$SEARCH_DIR/v1.yml"
    echo "version: 4.14.5" > "$SEARCH_DIR/v2.yml"
    mkdir -p "$SEARCH_DIR/.git"
    echo "version: 4.14.5" > "$SEARCH_DIR/.git/ignored"
}

teardown_file() {
    rm -rf "$TEST_DIR" "$SEARCH_DIR"
}

setup() {
    if ! command -v jq &>/dev/null; then
        export PATH="/tmp/jq-extracted/usr/bin:$PATH"
    fi
}

# Wrapper: source the script then restore safe shell options.
source_bumper() {
    source "$REPO_ROOT/tools/repository_bumper.sh"
    set +euo pipefail
}

# ─── Argument parsing: main() ─────────────────────────────────────────────

@test "main: exits with error when --version is missing" {
    source_bumper
    run main --stage stable
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Error: --version argument is required" ]]
}

@test "main: exits with error when --stage is missing" {
    source_bumper
    run main --version 4.15.0
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Error: --stage argument is required" ]]
}

@test "main: exits with error for malformed version (not X.Y.Z)" {
    source_bumper
    run main --version 1.2 --stage beta1
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Version must be in the format" ]]
}

@test "main: exits with error for non-numeric version" {
    source_bumper
    run main --version abc --stage beta1
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Version must be in the format" ]]
}

@test "main: exits with error for malformed stage" {
    source_bumper
    run main --version 4.15.0 --stage invalid
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Stage must be one of the following" ]]
}

@test "main: accepts valid --version and --stage" {
    source_bumper
    DIR="$TEST_DIR"
    run main --version 4.14.5 --stage stable
    [ "$status" -eq 0 ]
    [[ "$output" =~ "already up to date" ]]
}

@test "main: converts stage to lowercase" {
    source_bumper
    DIR="$TEST_DIR"
    run main --version 4.14.5 --stage STABLE
    [ "$status" -eq 0 ]
    [[ "$output" =~ "already up to date" ]]
}

@test "main: bumps version when different from current" {
    if ! command -v jq &>/dev/null && [ ! -x /tmp/jq-extracted/usr/bin/jq ]; then
        skip "jq not available"
    fi
    source_bumper
    DIR="$TEST_DIR"
    run main --version 99.99.99 --stage rc99
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Version and stage updated successfully" ]]
}

# ─── grep_command ─────────────────────────────────────────────────────────

@test "grep_command: finds files matching a pattern in a directory" {
    source_bumper
    run grep_command "4.14.5" "$SEARCH_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" == *"v2.yml"* ]]
}

@test "grep_command: excludes .git directory" {
    source_bumper
    run grep_command "4.14.5" "$SEARCH_DIR"
    [ "$status" -eq 0 ]
    [[ "$output" != *".git"* ]]
}

@test "grep_command: returns empty for unmatched pattern" {
    source_bumper
    run grep_command "NONEXISTENT_PATTERN_XYZ" "$SEARCH_DIR"
    [ "$status" -eq 0 ]
    [ "${#output}" -eq 0 ]
}

@test "grep_command: excludes repository_bumper_*.log files" {
    source_bumper
    echo "4.14.5" > "$TEST_DIR/repository_bumper_test.log"
    run grep_command "4.14.5" "$TEST_DIR"
    [[ "$output" != *"repository_bumper_test.log"* ]]
    rm -f "$TEST_DIR/repository_bumper_test.log"
}

@test "grep_command: excludes CHANGELOG.md" {
    source_bumper
    run grep_command "changelog" "$TEST_DIR"
    [[ "$output" != *"CHANGELOG.md"* ]]
}

@test "grep_command: excludes repository_bumper.sh" {
    source_bumper
    run grep_command "main" "$TEST_DIR"
    [[ "$output" != *"repository_bumper.sh"* ]]
}

# ─── get_old_version_and_stage ────────────────────────────────────────────

@test "get_old_version_and_stage: reads VERSION.json correctly" {
    if ! command -v jq &>/dev/null && [ ! -x /tmp/jq-extracted/usr/bin/jq ]; then
        skip "jq not available"
    fi
    source_bumper
    DIR="$TEST_DIR"
    get_old_version_and_stage
    [ "$OLD_VERSION" = "4.14.5" ]
    [ "$OLD_STAGE" = "stable" ]
}

@test "get_old_version_and_stage: version file path uses DIR" {
    if ! command -v jq &>/dev/null && [ ! -x /tmp/jq-extracted/usr/bin/jq ]; then
        skip "jq not available"
    fi
    source_bumper
    DIR="$TEST_DIR"
    get_old_version_and_stage
    [[ "$OLD_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

# ─── SED_IN_PLACE ─────────────────────────────────────────────────────────

@test "SED_IN_PLACE: is set to platform-appropriate value" {
    source_bumper
    if [[ "$(uname -s)" == "Darwin" ]]; then
        [ "${SED_IN_PLACE[0]}" = "-i" ]
        [ "${#SED_IN_PLACE[@]}" -eq 2 ]
    else
        [ "${SED_IN_PLACE[0]}" = "-i" ]
        [ "${#SED_IN_PLACE[@]}" -eq 1 ]
    fi
}

# ─── cleanup ──────────────────────────────────────────────────────────────

@test "cleanup: removes sed backup files" {
    source_bumper
    DIR="$TEST_DIR"
    touch "$TEST_DIR/test_file.yml.bak"
    [ -f "$TEST_DIR/test_file.yml.bak" ]
    cleanup
    [ ! -f "$TEST_DIR/test_file.yml.bak" ]
}

@test "cleanup: does not fail when DIR is empty" {
    source_bumper
    local save_dir="${DIR:-}"
    DIR=""
    run cleanup
    [ "$status" -eq 0 ]
    DIR="$save_dir"
}

# ─── update_version_in_files (in temp repo) ───────────────────────────────

@test "update_version_in_files: bumps version in files" {
    if ! command -v jq &>/dev/null && [ ! -x /tmp/jq-extracted/usr/bin/jq ]; then
        skip "jq not available"
    fi
    source_bumper
    DIR="$TEST_DIR"
    VERSION="4.15.0"
    get_old_version_and_stage
    run update_version_in_files
    [ "$status" -eq 0 ]
    grep -q "wazuh_version: 4.15.0" "$TEST_DIR/test_vars.yml"
}

@test "update_stage_in_files: updates stage in files" {
    if ! command -v jq &>/dev/null && [ ! -x /tmp/jq-extracted/usr/bin/jq ]; then
        skip "jq not available"
    fi
    source_bumper
    DIR="$TEST_DIR"
    STAGE="beta1"
    get_old_version_and_stage
    run update_stage_in_files
    [ "$status" -eq 0 ]
}
