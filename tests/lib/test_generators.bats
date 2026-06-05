#!/usr/bin/env bats
# Tests for lib/generators.sh

LIB_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)/lib"

setup() {
    source "$LIB_DIR/generators.sh"
}

setup_file() {
    export SSH_KEY_DIR
    SSH_KEY_DIR="$(mktemp -d)"
}

teardown_file() {
    rm -rf "$SSH_KEY_DIR"
}

# ─── generate_password ─────────────────────────────────────────────────────────

@test "generate_password: produces output of default length 24" {
    run generate_password
    [ "$status" -eq 0 ]
    [ "${#output}" -eq 24 ]
}

@test "generate_password: produces output of requested length 16" {
    run generate_password 16
    [ "$status" -eq 0 ]
    [ "${#output}" -eq 16 ]
}

@test "generate_password: produces output of requested length 48" {
    run generate_password 48
    [ "$status" -eq 0 ]
    [ "${#output}" -eq 48 ]
}

@test "generate_password: contains at least one uppercase letter" {
    run generate_password
    [ "$status" -eq 0 ]
    [[ "$output" =~ [A-Z] ]]
}

@test "generate_password: contains at least one lowercase letter" {
    run generate_password
    [ "$status" -eq 0 ]
    [[ "$output" =~ [a-z] ]]
}

@test "generate_password: contains at least one digit" {
    run generate_password
    [ "$status" -eq 0 ]
    [[ "$output" =~ [0-9] ]]
}

@test "generate_password: contains at least one symbol from the required set" {
    run generate_password
    [ "$status" -eq 0 ]
    # Required symbols: !@#$%^&*
    [[ "$output" =~ [!@#\$%^\&*] ]]
}

@test "generate_password: two consecutive calls produce different passwords" {
    run generate_password
    local first="$output"
    run generate_password
    local second="$output"
    [ "$first" != "$second" ]
}

@test "generate_password: output contains no newlines or whitespace" {
    run generate_password
    [ "$status" -eq 0 ]
    [[ ! "$output" =~ [[:space:]] ]]
}

# ─── generate_hex_key ─────────────────────────────────────────────────────────

@test "generate_hex_key: produces output of default length 32" {
    run generate_hex_key
    [ "$status" -eq 0 ]
    [ "${#output}" -eq 32 ]
}

@test "generate_hex_key: produces output of requested length 16" {
    run generate_hex_key 16
    [ "$status" -eq 0 ]
    [ "${#output}" -eq 16 ]
}

@test "generate_hex_key: produces output of requested length 64" {
    run generate_hex_key 64
    [ "$status" -eq 0 ]
    [ "${#output}" -eq 64 ]
}

@test "generate_hex_key: output contains only hex characters" {
    run generate_hex_key
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[0-9a-f]+$ ]]
}

@test "generate_hex_key: two consecutive calls produce different keys" {
    run generate_hex_key
    local first="$output"
    run generate_hex_key
    local second="$output"
    [ "$first" != "$second" ]
}

# ─── generate_vault_password ──────────────────────────────────────────────────

@test "generate_vault_password: produces output of length 32" {
    run generate_vault_password
    [ "$status" -eq 0 ]
    [ "${#output}" -eq 32 ]
}

@test "generate_vault_password: meets all Wazuh password requirements" {
    run generate_vault_password
    [ "$status" -eq 0 ]
    [[ "$output" =~ [A-Z] ]]
    [[ "$output" =~ [a-z] ]]
    [[ "$output" =~ [0-9] ]]
    [[ "$output" =~ [!@#\$%^\&*] ]]
}

# ─── generate_deployment_id ───────────────────────────────────────────────────

@test "generate_deployment_id: uses default 'wazuh' prefix" {
    run generate_deployment_id
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^wazuh- ]]
}

@test "generate_deployment_id: uses custom prefix when provided" {
    run generate_deployment_id "myorg"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^myorg- ]]
}

@test "generate_deployment_id: matches expected format prefix-YYYYMMDDHHMMSS-hex" {
    run generate_deployment_id
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^wazuh-[0-9]{14}-[0-9a-f]+ ]]
}

@test "generate_deployment_id: two consecutive calls produce different IDs" {
    run generate_deployment_id
    local first="$output"
    run generate_deployment_id
    local second="$output"
    [ "$first" != "$second" ]
}

# ─── generate_ssh_keypair ─────────────────────────────────────────────────────

@test "generate_ssh_keypair: returns 0 and creates key files" {
    local key_path="$SSH_KEY_DIR/test_key_new"
    run generate_ssh_keypair "$key_path"
    [ "$status" -eq 0 ]
    [ -f "$key_path" ]
    [ -f "${key_path}.pub" ]
}

@test "generate_ssh_keypair: private key has mode 600" {
    local key_path="$SSH_KEY_DIR/test_key_perms"
    generate_ssh_keypair "$key_path"
    local mode
    mode=$(stat -c '%a' "$key_path")
    [ "$mode" = "600" ]
}

@test "generate_ssh_keypair: public key has mode 644" {
    local key_path="$SSH_KEY_DIR/test_key_pubperms"
    generate_ssh_keypair "$key_path"
    local mode
    mode=$(stat -c '%a' "${key_path}.pub")
    [ "$mode" = "644" ]
}

@test "generate_ssh_keypair: uses default comment when none provided" {
    local key_path="$SSH_KEY_DIR/test_key_comment"
    generate_ssh_keypair "$key_path"
    grep -q "wazuh-ansible-deploy" "${key_path}.pub"
}

@test "generate_ssh_keypair: uses custom comment when provided" {
    local key_path="$SSH_KEY_DIR/test_key_custom_comment"
    generate_ssh_keypair "$key_path" "my-custom-comment"
    grep -q "my-custom-comment" "${key_path}.pub"
}

@test "generate_ssh_keypair: returns 1 without creating duplicate key" {
    local key_path="$SSH_KEY_DIR/test_key_existing"
    generate_ssh_keypair "$key_path"
    local mtime_before
    mtime_before=$(stat -c '%Y' "$key_path")

    run generate_ssh_keypair "$key_path"
    [ "$status" -ne 0 ]

    local mtime_after
    mtime_after=$(stat -c '%Y' "$key_path")
    [ "$mtime_before" = "$mtime_after" ]
}

@test "generate_ssh_keypair: creates parent directories as needed" {
    local key_path="$SSH_KEY_DIR/nested/dir/test_key"
    run generate_ssh_keypair "$key_path"
    [ "$status" -eq 0 ]
    [ -f "$key_path" ]
}
