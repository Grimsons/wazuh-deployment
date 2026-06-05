#!/usr/bin/env bats
# Tests for lib/profiles.sh
# Focuses on variable-setting functions and pure logic; interactive prompts are excluded.

LIB_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)/lib"

setup() {
    # Set NC to a non-empty value so profiles.sh skips sourcing colors.sh,
    # then stub all print functions it depends on.
    NC="stub"
    CYAN="" YELLOW="" GREEN="" RED="" BOLD="" DIM="" BLUE=""
    print_info()    { :; }
    print_success() { :; }
    print_error()   { :; }
    print_header()  { :; }

    source "$LIB_DIR/profiles.sh"
}

# ─── get_profile_description ──────────────────────────────────────────────────

@test "get_profile_description: returns description for minimal" {
    run get_profile_description "minimal"
    [ "$status" -eq 0 ]
    [[ "$output" == *"testing"* || "$output" == *"development"* ]]
}

@test "get_profile_description: returns description for production" {
    run get_profile_description "production"
    [ "$status" -eq 0 ]
    [[ "$output" == *"HA"* || "$output" == *"multi-node"* || "$output" == *"security"* ]]
}

@test "get_profile_description: returns fallback for unknown profile" {
    run get_profile_description "nonexistent"
    [ "$status" -eq 0 ]
    [ "$output" = "Unknown profile" ]
}

# ─── apply_profile_minimal ────────────────────────────────────────────────────

@test "apply_profile_minimal: sets all nodes to localhost" {
    apply_profile_minimal
    [ "$INDEXER_NODES"   = "localhost" ]
    [ "$MANAGER_NODES"   = "localhost" ]
    [ "$DASHBOARD_NODES" = "localhost" ]
}

@test "apply_profile_minimal: disables agent deployment" {
    apply_profile_minimal
    [ "$DEPLOY_AGENTS" = "false" ]
    [ "$AGENT_NODES"   = "" ]
}

@test "apply_profile_minimal: sets environment to development" {
    apply_profile_minimal
    [ "$ENVIRONMENT" = "development" ]
}

@test "apply_profile_minimal: uses self-signed certificates" {
    apply_profile_minimal
    [ "$USE_SELF_SIGNED_CERTS" = "true" ]
    [ "$GENERATE_CERTS"        = "true" ]
    [ "$EXTERNAL_CA"           = "false" ]
}

@test "apply_profile_minimal: disables active response" {
    apply_profile_minimal
    [ "$ENABLE_ACTIVE_RESPONSE" = "false" ]
}

@test "apply_profile_minimal: enables core security features" {
    apply_profile_minimal
    [ "$ENABLE_VULN_DETECTION" = "true" ]
    [ "$ENABLE_FIM"            = "true" ]
    [ "$ENABLE_SCA"            = "true" ]
    [ "$ENABLE_SYSCOLLECTOR"   = "true" ]
}

@test "apply_profile_minimal: disables all external integrations" {
    apply_profile_minimal
    [ "$ENABLE_EMAIL_ALERTS"   = "false" ]
    [ "$ENABLE_SYSLOG_OUTPUT"  = "false" ]
    [ "$ENABLE_SLACK"          = "false" ]
    [ "$ENABLE_VIRUSTOTAL"     = "false" ]
}

@test "apply_profile_minimal: sets backup schedule to disabled" {
    apply_profile_minimal
    [ "$BACKUP_SCHEDULE" = "disabled" ]
}

@test "apply_profile_minimal: sets 7-day log retention" {
    apply_profile_minimal
    [ "$LOG_RETENTION_DAYS" = "7" ]
}

@test "apply_profile_minimal: does not generate SSH key" {
    apply_profile_minimal
    [ "$GENERATE_SSH_KEY" = "false" ]
}

@test "apply_profile_minimal: uses current user as ansible user" {
    apply_profile_minimal
    [ "$ANSIBLE_USER" = "$(whoami)" ]
}

@test "apply_profile_minimal: uses standard ports" {
    apply_profile_minimal
    [ "$INDEXER_HTTP_PORT" = "9200" ]
    [ "$MANAGER_API_PORT"  = "55000" ]
    [ "$AGENT_PORT"        = "1514" ]
    [ "$DASHBOARD_PORT"    = "443" ]
}

@test "apply_profile_minimal: respects pre-set WAZUH_VERSION" {
    WAZUH_VERSION="4.99.0"
    apply_profile_minimal
    [ "$WAZUH_VERSION" = "4.99.0" ]
}

@test "apply_profile_minimal: uses default WAZUH_VERSION when unset" {
    unset WAZUH_VERSION
    apply_profile_minimal
    [ -n "$WAZUH_VERSION" ]
}

# ─── apply_profile_production ─────────────────────────────────────────────────

@test "apply_profile_production: sets environment to production" {
    apply_profile_production
    [ "$ENVIRONMENT" = "production" ]
}

@test "apply_profile_production: leaves node lists empty for manual configuration" {
    apply_profile_production
    [ "$INDEXER_NODES"   = "" ]
    [ "$MANAGER_NODES"   = "" ]
    [ "$DASHBOARD_NODES" = "" ]
}

@test "apply_profile_production: generates SSH key" {
    apply_profile_production
    [ "$GENERATE_SSH_KEY" = "true" ]
}

@test "apply_profile_production: uses dedicated deploy user" {
    apply_profile_production
    [ "$ANSIBLE_USER" = "wazuh-deploy" ]
}

@test "apply_profile_production: enables active response" {
    apply_profile_production
    [ "$ENABLE_ACTIVE_RESPONSE" = "true" ]
}

@test "apply_profile_production: enables all core security features" {
    apply_profile_production
    [ "$ENABLE_VULN_DETECTION" = "true" ]
    [ "$ENABLE_FIM"            = "true" ]
    [ "$ENABLE_ROOTKIT"        = "true" ]
    [ "$ENABLE_SCA"            = "true" ]
    [ "$ENABLE_SYSCOLLECTOR"   = "true" ]
    [ "$ENABLE_LOG_COLLECTION" = "true" ]
}

@test "apply_profile_production: sets daily backup schedule" {
    apply_profile_production
    [ "$BACKUP_SCHEDULE" = "daily" ]
}

@test "apply_profile_production: sets 30-day log retention" {
    apply_profile_production
    [ "$LOG_RETENTION_DAYS" = "30" ]
}

@test "apply_profile_production: enables client prep package creation" {
    apply_profile_production
    [ "$CREATE_PREP_PACKAGE" = "true" ]
}

@test "apply_profile_production: respects pre-set WAZUH_VERSION" {
    WAZUH_VERSION="4.99.0"
    apply_profile_production
    [ "$WAZUH_VERSION" = "4.99.0" ]
}

@test "apply_profile_production: uses standard Wazuh ports" {
    apply_profile_production
    [ "$INDEXER_HTTP_PORT" = "9200" ]
    [ "$MANAGER_API_PORT"  = "55000" ]
    [ "$AGENT_PORT"        = "1514" ]
    [ "$DASHBOARD_PORT"    = "443" ]
}

# ─── apply_profile (dispatcher) ───────────────────────────────────────────────

@test "apply_profile: dispatches 'minimal' correctly" {
    apply_profile "minimal"
    [ "$ENVIRONMENT" = "development" ]
}

@test "apply_profile: dispatches 'production' correctly" {
    apply_profile "production"
    [ "$ENVIRONMENT" = "production" ]
}

@test "apply_profile: returns 1 for unknown profile name" {
    run apply_profile "nonexistent"
    [ "$status" -ne 0 ]
}

# ─── is_quick_mode ────────────────────────────────────────────────────────────

@test "is_quick_mode: returns true when PROFILE is 'minimal'" {
    PROFILE="minimal"
    is_quick_mode
}

@test "is_quick_mode: returns true when PROFILE is 'production'" {
    PROFILE="production"
    is_quick_mode
}

@test "is_quick_mode: returns false when PROFILE is 'custom'" {
    PROFILE="custom"
    run is_quick_mode
    [ "$status" -ne 0 ]
}

@test "is_quick_mode: returns false when PROFILE is unset" {
    unset PROFILE
    run is_quick_mode
    [ "$status" -ne 0 ]
}

# ─── skip_if_set ──────────────────────────────────────────────────────────────

@test "skip_if_set: returns true when variable holds a non-empty value" {
    MY_TEST_VAR="some_value"
    skip_if_set "MY_TEST_VAR"
}

@test "skip_if_set: returns false when variable is empty" {
    MY_TEST_VAR=""
    run skip_if_set "MY_TEST_VAR"
    [ "$status" -ne 0 ]
}

@test "skip_if_set: returns false when variable is unset" {
    unset MY_TEST_VAR
    run skip_if_set "MY_TEST_VAR"
    [ "$status" -ne 0 ]
}
