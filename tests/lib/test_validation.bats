#!/usr/bin/env bats
# Tests for lib/validation.sh

LIB_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)/lib"

setup() {
    source "$LIB_DIR/validation.sh"
}

# ─── validate_ip ───────────────────────────────────────────────────────────────

@test "validate_ip: accepts standard private addresses" {
    validate_ip "192.168.1.1"
    validate_ip "10.0.0.1"
    validate_ip "172.16.0.50"
}

@test "validate_ip: accepts boundary values 0.0.0.0 and 255.255.255.255" {
    validate_ip "0.0.0.0"
    validate_ip "255.255.255.255"
}

@test "validate_ip: rejects octet above 255" {
    run validate_ip "256.0.0.1"
    [ "$status" -ne 0 ]
}

@test "validate_ip: rejects address with only three octets" {
    run validate_ip "192.168.1"
    [ "$status" -ne 0 ]
}

@test "validate_ip: rejects address with five octets" {
    run validate_ip "192.168.1.1.5"
    [ "$status" -ne 0 ]
}

@test "validate_ip: rejects non-numeric octets" {
    run validate_ip "192.168.1.abc"
    [ "$status" -ne 0 ]
}

@test "validate_ip: rejects empty string" {
    run validate_ip ""
    [ "$status" -ne 0 ]
}

@test "validate_ip: rejects leading zeros that could cause octal misparse" {
    run validate_ip "192.168.01.1"
    [ "$status" -ne 0 ]
}

# ─── validate_hostname ─────────────────────────────────────────────────────────

@test "validate_hostname: accepts simple hostname" {
    validate_hostname "localhost"
}

@test "validate_hostname: accepts hostname with hyphens and numbers" {
    validate_hostname "wazuh-manager-01"
}

@test "validate_hostname: accepts fully qualified domain name" {
    validate_hostname "wazuh.example.com"
}

@test "validate_hostname: accepts IP address via validate_ip path" {
    validate_hostname "192.168.1.1"
}

@test "validate_hostname: rejects hostname starting with a hyphen" {
    run validate_hostname "-invalid"
    [ "$status" -ne 0 ]
}

@test "validate_hostname: rejects empty string" {
    run validate_hostname ""
    [ "$status" -ne 0 ]
}

# ─── validate_port ─────────────────────────────────────────────────────────────

@test "validate_port: accepts well-known ports" {
    validate_port "22"
    validate_port "80"
    validate_port "443"
    validate_port "9200"
    validate_port "55000"
}

@test "validate_port: accepts boundary port 1" {
    validate_port "1"
}

@test "validate_port: accepts boundary port 65535" {
    validate_port "65535"
}

@test "validate_port: rejects port 0" {
    run validate_port "0"
    [ "$status" -ne 0 ]
}

@test "validate_port: rejects port 65536" {
    run validate_port "65536"
    [ "$status" -ne 0 ]
}

@test "validate_port: rejects non-numeric input" {
    run validate_port "http"
    [ "$status" -ne 0 ]
}

@test "validate_port: rejects empty string" {
    run validate_port ""
    [ "$status" -ne 0 ]
}

@test "validate_port: rejects negative number" {
    run validate_port "-1"
    [ "$status" -ne 0 ]
}

# ─── validate_heap_size ────────────────────────────────────────────────────────

@test "validate_heap_size: accepts 'auto'" {
    validate_heap_size "auto"
}

@test "validate_heap_size: accepts gigabyte values" {
    validate_heap_size "1g"
    validate_heap_size "4G"
    validate_heap_size "16g"
}

@test "validate_heap_size: accepts megabyte values" {
    validate_heap_size "512m"
    validate_heap_size "1024M"
}

@test "validate_heap_size: rejects value with no unit" {
    run validate_heap_size "512"
    [ "$status" -ne 0 ]
}

@test "validate_heap_size: rejects invalid unit like 'gb'" {
    run validate_heap_size "1gb"
    [ "$status" -ne 0 ]
}

@test "validate_heap_size: rejects terabyte unit" {
    run validate_heap_size "1t"
    [ "$status" -ne 0 ]
}

@test "validate_heap_size: rejects empty string" {
    run validate_heap_size ""
    [ "$status" -ne 0 ]
}

# ─── validate_email ────────────────────────────────────────────────────────────

@test "validate_email: accepts standard address" {
    validate_email "user@example.com"
}

@test "validate_email: accepts address with plus tag and subdomain" {
    validate_email "user.name+tag@sub.domain.org"
}

@test "validate_email: rejects address with no at-sign" {
    run validate_email "notanemail"
    [ "$status" -ne 0 ]
}

@test "validate_email: rejects address starting with at-sign" {
    run validate_email "@domain.com"
    [ "$status" -ne 0 ]
}

@test "validate_email: rejects address with no domain" {
    run validate_email "user@"
    [ "$status" -ne 0 ]
}

@test "validate_email: rejects empty string" {
    run validate_email ""
    [ "$status" -ne 0 ]
}

# ─── validate_url ──────────────────────────────────────────────────────────────

@test "validate_url: accepts http URL" {
    validate_url "http://example.com"
}

@test "validate_url: accepts https URL with path" {
    validate_url "https://wazuh.example.com/api/v1"
}

@test "validate_url: accepts https URL with IP host" {
    validate_url "https://10.0.0.1"
}

@test "validate_url: rejects ftp scheme" {
    run validate_url "ftp://example.com"
    [ "$status" -ne 0 ]
}

@test "validate_url: rejects bare hostname without scheme" {
    run validate_url "example.com"
    [ "$status" -ne 0 ]
}

@test "validate_url: rejects empty string" {
    run validate_url ""
    [ "$status" -ne 0 ]
}

# ─── validate_version ──────────────────────────────────────────────────────────

@test "validate_version: accepts standard semver" {
    validate_version "4.14.5"
    validate_version "1.0.0"
    validate_version "10.2.3"
}

@test "validate_version: rejects version with only two parts" {
    run validate_version "4.14"
    [ "$status" -ne 0 ]
}

@test "validate_version: rejects version with 'v' prefix" {
    run validate_version "v4.14.5"
    [ "$status" -ne 0 ]
}

@test "validate_version: rejects version with four parts" {
    run validate_version "4.14.1.0"
    [ "$status" -ne 0 ]
}

@test "validate_version: rejects non-numeric version string" {
    run validate_version "latest"
    [ "$status" -ne 0 ]
}

# ─── sanitize_alphanum ─────────────────────────────────────────────────────────

@test "sanitize_alphanum: passes through alphanumeric and allowed punctuation" {
    run sanitize_alphanum "valid-name_1.2"
    [ "$status" -eq 0 ]
    [ "$output" = "valid-name_1.2" ]
}

@test "sanitize_alphanum: strips spaces" {
    run sanitize_alphanum "hello world"
    [ "$status" -eq 0 ]
    [ "$output" = "helloworld" ]
}

@test "sanitize_alphanum: strips forward slashes" {
    run sanitize_alphanum "path/to/file"
    [ "$status" -eq 0 ]
    [ "$output" = "pathtofile" ]
}

@test "sanitize_alphanum: strips shell special characters" {
    run sanitize_alphanum 'test@#$file'
    [ "$status" -eq 0 ]
    [ "$output" = "testfile" ]
}

@test "sanitize_alphanum: returns empty string for all-special input" {
    run sanitize_alphanum '@#$%^&*()'
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "sanitize_alphanum: returns empty string for empty input" {
    run sanitize_alphanum ""
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

# ─── sanitize_path ─────────────────────────────────────────────────────────────

@test "sanitize_path: passes through a clean absolute path unchanged" {
    run sanitize_path "/var/log/wazuh"
    [ "$status" -eq 0 ]
    [ "$output" = "/var/log/wazuh" ]
}

@test "sanitize_path: passes through a clean relative path unchanged" {
    run sanitize_path "logs/wazuh.log"
    [ "$status" -eq 0 ]
    [ "$output" = "logs/wazuh.log" ]
}

@test "sanitize_path: removes leading ../ traversal" {
    run sanitize_path "../etc/passwd"
    [ "$status" -eq 0 ]
    [ "$output" = "etc/passwd" ]
}

@test "sanitize_path: removes multiple ../ traversals" {
    run sanitize_path "path/../../etc/passwd"
    [ "$status" -eq 0 ]
    [ "$output" = "path/etc/passwd" ]
}

@test "sanitize_path: neutralizes crafted ..../ double-traversal" {
    # "..../" is a known bypass attempt: single-pass removal of "../" leaves "../"
    # The iterative loop must handle this
    run sanitize_path "..../"
    [ "$status" -eq 0 ]
    [[ "$output" != *".."* ]]
}

@test "sanitize_path: strips special characters not in allowlist" {
    run sanitize_path 'file name with spaces & symbols!'
    [ "$status" -eq 0 ]
    [ "$output" = "filenamewithspacessymbols" ]
}

@test "sanitize_path: returns empty string for empty input" {
    run sanitize_path ""
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

# ─── validate_in_list ──────────────────────────────────────────────────────────

@test "validate_in_list: returns 0 when value is in the list" {
    validate_in_list "production" "development" "staging" "production"
}

@test "validate_in_list: returns 1 when value is not in the list" {
    run validate_in_list "invalid" "development" "staging" "production"
    [ "$status" -ne 0 ]
}

@test "validate_in_list: returns 0 for a single-element list match" {
    validate_in_list "only" "only"
}

@test "validate_in_list: returns 1 for empty value against non-empty list" {
    run validate_in_list "" "a" "b" "c"
    [ "$status" -ne 0 ]
}

# ─── validate_int_range ────────────────────────────────────────────────────────

@test "validate_int_range: accepts value within range" {
    validate_int_range 5 1 10
}

@test "validate_int_range: accepts value at lower boundary" {
    validate_int_range 1 1 10
}

@test "validate_int_range: accepts value at upper boundary" {
    validate_int_range 10 1 10
}

@test "validate_int_range: rejects value below minimum" {
    run validate_int_range 0 1 10
    [ "$status" -ne 0 ]
}

@test "validate_int_range: rejects value above maximum" {
    run validate_int_range 11 1 10
    [ "$status" -ne 0 ]
}

@test "validate_int_range: rejects non-numeric value" {
    run validate_int_range "abc" 1 10
    [ "$status" -ne 0 ]
}

# ─── command_exists ────────────────────────────────────────────────────────────

@test "command_exists: returns 0 for bash (always present)" {
    command_exists "bash"
}

@test "command_exists: returns 1 for a nonexistent command" {
    run command_exists "this_command_does_not_exist_xyz123"
    [ "$status" -ne 0 ]
}

# ─── file_readable ─────────────────────────────────────────────────────────────

@test "file_readable: returns 0 for a readable file" {
    local tmp
    tmp="$(mktemp)"
    file_readable "$tmp"
    rm -f "$tmp"
}

@test "file_readable: returns 1 for a nonexistent path" {
    run file_readable "/nonexistent/path/file.txt"
    [ "$status" -ne 0 ]
}

@test "file_readable: returns 1 for a directory" {
    run file_readable "/tmp"
    [ "$status" -ne 0 ]
}

# ─── dir_writable ──────────────────────────────────────────────────────────────

@test "dir_writable: returns 0 for /tmp" {
    dir_writable "/tmp"
}

@test "dir_writable: returns 1 for a nonexistent directory" {
    run dir_writable "/nonexistent/directory/xyz"
    [ "$status" -ne 0 ]
}

@test "dir_writable: returns 1 for a file path" {
    local tmp
    tmp="$(mktemp)"
    run dir_writable "$tmp"
    [ "$status" -ne 0 ]
    rm -f "$tmp"
}
