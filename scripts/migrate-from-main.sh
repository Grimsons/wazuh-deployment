#!/bin/bash

# Wazuh Deployment - Migration Script: main branch → 1.1 branch
# Converts old plaintext group_vars/all.yml to the new vault-encrypted format
#
# Handles two cases:
#   Case 1: Old flat group_vars/all.yml with plaintext passwords
#   Case 2: Partial migration (group_vars/all/main.yml exists but vault missing/broken)
#
# Usage:
#   ./scripts/migrate-from-main.sh
#
# The script will:
#   - Detect the old credential format
#   - Extract existing passwords and config
#   - Create encrypted vault with your existing credentials
#   - Generate group_vars/all/main.yml with vault references
#   - Back up old files before making changes

set -euo pipefail

# Cleanup temp files on exit
cleanup() {
    rm -f "${VAULT_DIR:-}/vault.yml.tmp" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
VAULT_DIR="$PROJECT_DIR/group_vars/all"
VAULT_FILE="$VAULT_DIR/vault.yml"
VAULT_PASSWORD_FILE="$PROJECT_DIR/.vault_password"
OLD_ALL_YML="$PROJECT_DIR/group_vars/all.yml"
NEW_MAIN_YML="$VAULT_DIR/main.yml"
TIMESTAMP="$(date +%Y%m%d%H%M%S)"

print_header() {
    echo -e "\n${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}\n"
}

print_success() { echo -e "${GREEN}[OK]${NC} $1"; }
print_info()    { echo -e "${YELLOW}[INFO]${NC} $1"; }
print_error()   { echo -e "${RED}[ERROR]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# Generate a secure random password (same as manage-vault.sh)
generate_password() {
    local length="${1:-24}"
    local password
    password=$(LC_ALL=C tr -dc 'A-Za-z0-9@^_+=-' < /dev/urandom | head -c "$length")
    local upper lower number symbol
    upper=$(LC_ALL=C tr -dc 'A-Z' < /dev/urandom | head -c 1)
    lower=$(LC_ALL=C tr -dc 'a-z' < /dev/urandom | head -c 1)
    number=$(LC_ALL=C tr -dc '0-9' < /dev/urandom | head -c 1)
    local symbols='@^_+-='
    local symbol_idx
    symbol_idx=$(head -c 4 /dev/urandom | od -An -tu4 | tr -d ' ')
    symbol="${symbols:$((symbol_idx % ${#symbols})):1}"
    password="${password}${upper}${lower}${number}${symbol}"
    echo "$password" | fold -w1 | shuf | tr -d '\n'
}

# Extract a YAML scalar value from a file
# Usage: extract_var FILE "variable_name"
# Handles: var: value, var: "value", var: 'value'
extract_var() {
    local file="$1"
    local var="$2"
    local value
    value=$(grep -E "^${var}:" "$file" 2>/dev/null | head -1 | sed -E 's/^[^:]+:\s*//' | sed -E 's/^["'\''](.*?)["'\'']$/\1/' | sed 's/\s*#.*//' | xargs)
    echo "$value"
}

# Extract a boolean value, normalizing to true/false
extract_bool() {
    local file="$1"
    local var="$2"
    local default="${3:-}"
    local value
    value=$(extract_var "$file" "$var")
    if [ -z "$value" ]; then
        echo "$default"
        return
    fi
    case "${value,,}" in
        true|yes|1) echo "true" ;;
        false|no|0) echo "false" ;;
        *) echo "$default" ;;
    esac
}

# Extract multi-line list items (returns items one per line)
# Handles YAML lists like:
#   var:
#     - name: foo
#       ip: 1.2.3.4
extract_node_list() {
    local file="$1"
    local var="$2"
    # Get everything after the variable declaration until the next top-level key
    sed -n "/^${var}:/,/^[a-zA-Z_]/p" "$file" | grep -v "^${var}:" | grep -v "^[a-zA-Z_]" | grep -v "^$" | grep -v "^#"
}

# ═══════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════

print_header "Wazuh Deployment Migration: main → 1.1"

# Check prerequisites
if ! command -v ansible-vault &>/dev/null; then
    print_error "ansible-vault not found. Install ansible: pip install ansible"
    exit 1
fi

# Detect migration case
SOURCE_FILE=""
MIGRATION_CASE=""

if [ -f "$OLD_ALL_YML" ]; then
    # Check if it has plaintext passwords (not vault references)
    if grep -qE '^wazuh_(indexer_admin|api|dashboard_admin)_password:\s*"[^{]' "$OLD_ALL_YML" 2>/dev/null || \
       grep -qE "^wazuh_(indexer_admin|api|dashboard_admin)_password:\s*'[^{]" "$OLD_ALL_YML" 2>/dev/null || \
       grep -qE '^wazuh_(indexer_admin|api|dashboard_admin)_password:\s*[^"{'\''$]' "$OLD_ALL_YML" 2>/dev/null; then
        MIGRATION_CASE="flat_file"
        SOURCE_FILE="$OLD_ALL_YML"
        print_info "Detected: Old flat-file format (group_vars/all.yml with plaintext passwords)"
    elif grep -qE 'vault_' "$OLD_ALL_YML" 2>/dev/null; then
        print_info "group_vars/all.yml already uses vault references - checking for vault..."
        if [ -f "$NEW_MAIN_YML" ]; then
            SOURCE_FILE="$OLD_ALL_YML"
            MIGRATION_CASE="partial"
        else
            MIGRATION_CASE="flat_file"
            SOURCE_FILE="$OLD_ALL_YML"
        fi
    else
        MIGRATION_CASE="flat_file"
        SOURCE_FILE="$OLD_ALL_YML"
        print_info "Detected: group_vars/all.yml (treating as old format)"
    fi
fi

if [ -z "$MIGRATION_CASE" ] && [ -f "$NEW_MAIN_YML" ]; then
    # Check if vault is missing or broken
    if [ ! -f "$VAULT_FILE" ]; then
        MIGRATION_CASE="partial"
        SOURCE_FILE="$NEW_MAIN_YML"
        print_info "Detected: group_vars/all/main.yml exists but vault.yml is missing"
    elif [ -f "$VAULT_PASSWORD_FILE" ]; then
        if ! ansible-vault view "$VAULT_FILE" --vault-password-file "$VAULT_PASSWORD_FILE" &>/dev/null; then
            MIGRATION_CASE="partial"
            SOURCE_FILE="$NEW_MAIN_YML"
            print_info "Detected: vault.yml exists but cannot be decrypted"
        else
            print_success "Vault is working correctly. No migration needed."
            print_info "Use './scripts/manage-vault.sh view' to see current credentials."
            exit 0
        fi
    else
        MIGRATION_CASE="partial"
        SOURCE_FILE="$NEW_MAIN_YML"
        print_info "Detected: vault.yml exists but no .vault_password file"
    fi
fi

if [ -z "$MIGRATION_CASE" ]; then
    print_error "No old configuration found to migrate."
    echo ""
    echo "Expected one of:"
    echo "  - group_vars/all.yml          (old flat-file format)"
    echo "  - group_vars/all/main.yml     (new format, missing vault)"
    echo ""
    echo "If starting fresh, run: ./setup.sh"
    exit 1
fi

echo ""
print_info "Source file: $SOURCE_FILE"
print_info "Migration type: $MIGRATION_CASE"
echo ""

# ═══════════════════════════════════════════════════════════════
# Extract credentials and config from source
# ═══════════════════════════════════════════════════════════════

print_info "Extracting configuration from old file..."

# Credentials (secrets that go into vault)
OLD_INDEXER_PASSWORD=$(extract_var "$SOURCE_FILE" "wazuh_indexer_admin_password")
OLD_API_PASSWORD=$(extract_var "$SOURCE_FILE" "wazuh_api_password")
OLD_DASHBOARD_PASSWORD=$(extract_var "$SOURCE_FILE" "wazuh_dashboard_admin_password")
OLD_CLUSTER_KEY=$(extract_var "$SOURCE_FILE" "wazuh_manager_cluster_key")
OLD_ENROLLMENT_PASSWORD=$(extract_var "$SOURCE_FILE" "wazuh_agent_enrollment_password")

# Strip vault references - if password is a {{ vault_* }} reference, it's not a real value
strip_vault_ref() {
    local val="$1"
    if [[ "$val" == *"vault_"* ]] || [[ "$val" == *"{{"* ]]; then
        echo ""
    else
        echo "$val"
    fi
}

OLD_INDEXER_PASSWORD=$(strip_vault_ref "$OLD_INDEXER_PASSWORD")
OLD_API_PASSWORD=$(strip_vault_ref "$OLD_API_PASSWORD")
OLD_DASHBOARD_PASSWORD=$(strip_vault_ref "$OLD_DASHBOARD_PASSWORD")
OLD_CLUSTER_KEY=$(strip_vault_ref "$OLD_CLUSTER_KEY")
OLD_ENROLLMENT_PASSWORD=$(strip_vault_ref "$OLD_ENROLLMENT_PASSWORD")

# Non-secret config
WAZUH_VERSION=$(extract_var "$SOURCE_FILE" "wazuh_version")
ENVIRONMENT_NAME=$(extract_var "$SOURCE_FILE" "environment_name")
ORGANIZATION_NAME=$(extract_var "$SOURCE_FILE" "organization_name")
INDEXER_CLUSTER_NAME=$(extract_var "$SOURCE_FILE" "wazuh_indexer_cluster_name")
INDEXER_HTTP_PORT=$(extract_var "$SOURCE_FILE" "wazuh_indexer_http_port")
INDEXER_TRANSPORT_PORT=$(extract_var "$SOURCE_FILE" "wazuh_indexer_transport_port")
INDEXER_HEAP_SIZE=$(extract_var "$SOURCE_FILE" "wazuh_indexer_heap_size")
INDEXER_ADMIN_USER=$(extract_var "$SOURCE_FILE" "wazuh_indexer_admin_user")
MANAGER_API_PORT=$(extract_var "$SOURCE_FILE" "wazuh_manager_api_port")
MANAGER_AGENT_PORT=$(extract_var "$SOURCE_FILE" "wazuh_manager_agent_port")
API_USER=$(extract_var "$SOURCE_FILE" "wazuh_api_user")
CLUSTER_ENABLED=$(extract_bool "$SOURCE_FILE" "wazuh_manager_cluster_enabled" "false")
DASHBOARD_PORT=$(extract_var "$SOURCE_FILE" "wazuh_dashboard_port")

# SSL/TLS
OLD_GENERATE_CERTS=$(extract_bool "$SOURCE_FILE" "wazuh_generate_certs" "")
USE_EXTERNAL_CA=$(extract_bool "$SOURCE_FILE" "wazuh_use_external_ca" "")
CERTS_PATH=$(extract_var "$SOURCE_FILE" "wazuh_certs_path")
SSL_VERIFY=$(extract_bool "$SOURCE_FILE" "wazuh_ssl_verify_certificates" "false")

# Feature toggles
VULN_DETECTION=$(extract_bool "$SOURCE_FILE" "wazuh_vulnerability_detection_enabled" "true")
FIM_ENABLED=$(extract_bool "$SOURCE_FILE" "wazuh_fim_enabled" "true")
ROOTKIT_ENABLED=$(extract_bool "$SOURCE_FILE" "wazuh_rootkit_detection_enabled" "true")
SCA_ENABLED=$(extract_bool "$SOURCE_FILE" "wazuh_sca_enabled" "true")
SYSCOLLECTOR_ENABLED=$(extract_bool "$SOURCE_FILE" "wazuh_syscollector_enabled" "true")
LOG_COLLECTION=$(extract_bool "$SOURCE_FILE" "wazuh_log_collection_enabled" "true")
ACTIVE_RESPONSE=$(extract_bool "$SOURCE_FILE" "wazuh_active_response_enabled" "true")
EMAIL_ENABLED=$(extract_bool "$SOURCE_FILE" "wazuh_email_notification_enabled" "false")
SYSLOG_ENABLED=$(extract_bool "$SOURCE_FILE" "wazuh_syslog_output_enabled" "false")
FIREWALL_ENABLED=$(extract_bool "$SOURCE_FILE" "wazuh_configure_firewall" "true")
SELINUX_ENABLED=$(extract_bool "$SOURCE_FILE" "wazuh_configure_selinux" "true")

# Node lists (preserve raw YAML)
INDEXER_NODES=$(extract_node_list "$SOURCE_FILE" "wazuh_indexer_nodes")
MANAGER_NODES=$(extract_node_list "$SOURCE_FILE" "wazuh_manager_nodes")
DASHBOARD_NODES=$(extract_node_list "$SOURCE_FILE" "wazuh_dashboard_nodes")

# Report what was found
echo ""
print_info "Extracted configuration:"
echo "  Version:          ${WAZUH_VERSION:-not set}"
echo "  Environment:      ${ENVIRONMENT_NAME:-not set}"
echo "  Organization:     ${ORGANIZATION_NAME:-not set}"
echo ""
echo "  Credentials found:"
if [ -n "$OLD_INDEXER_PASSWORD" ]; then
    echo "    Indexer password: ****** (found)"
else
    echo "    Indexer password: (not found - will generate)"
fi
if [ -n "$OLD_API_PASSWORD" ]; then
    echo "    API password:     ****** (found)"
else
    echo "    API password:     (not found - will generate)"
fi
if [ -n "$OLD_DASHBOARD_PASSWORD" ]; then
    echo "    Dashboard password: ****** (found, will map to indexer password)"
fi
if [ -n "$OLD_CLUSTER_KEY" ]; then
    echo "    Cluster key:      ****** (found)"
else
    echo "    Cluster key:      (not found - will generate)"
fi
if [ -n "$OLD_ENROLLMENT_PASSWORD" ]; then
    echo "    Enrollment password: ****** (found)"
else
    echo "    Enrollment password: (not found - will generate)"
fi
echo ""

# ═══════════════════════════════════════════════════════════════
# Confirm before proceeding
# ═══════════════════════════════════════════════════════════════

echo -e "${YELLOW}This will:${NC}"
echo "  1. Back up existing config files"
echo "  2. Create group_vars/all/main.yml (vault references, no plaintext passwords)"
echo "  3. Create group_vars/all/vault.yml (encrypted with your existing passwords)"
if [ "$MIGRATION_CASE" = "flat_file" ]; then
    echo "  4. Rename group_vars/all.yml → group_vars/all.yml.migrated"
fi
echo ""
read -p "Continue? (y/N): " confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    print_info "Migration cancelled."
    exit 0
fi

echo ""

# ═══════════════════════════════════════════════════════════════
# Create backups
# ═══════════════════════════════════════════════════════════════

print_info "Creating backups..."

if [ -f "$OLD_ALL_YML" ]; then
    cp "$OLD_ALL_YML" "${OLD_ALL_YML}.pre-migration-backup.${TIMESTAMP}"
    print_success "Backed up: group_vars/all.yml"
fi

if [ -f "$NEW_MAIN_YML" ]; then
    cp "$NEW_MAIN_YML" "${NEW_MAIN_YML}.pre-migration-backup.${TIMESTAMP}"
    print_success "Backed up: group_vars/all/main.yml"
fi

if [ -f "$VAULT_FILE" ]; then
    cp "$VAULT_FILE" "${VAULT_FILE}.pre-migration-backup.${TIMESTAMP}"
    print_success "Backed up: group_vars/all/vault.yml"
fi

# ═══════════════════════════════════════════════════════════════
# Generate vault password if needed
# ═══════════════════════════════════════════════════════════════

if [ ! -f "$VAULT_PASSWORD_FILE" ]; then
    print_info "Generating vault password..."
    vault_pass=$(generate_password 32)
    echo "$vault_pass" > "$VAULT_PASSWORD_FILE"
    chmod 600 "$VAULT_PASSWORD_FILE"
    print_success "Vault password created: .vault_password"
    print_warning "IMPORTANT: Back up .vault_password securely!"
else
    print_info "Using existing vault password: .vault_password"
fi

# ═══════════════════════════════════════════════════════════════
# Resolve credential values
# ═══════════════════════════════════════════════════════════════

# Use old dashboard password as indexer password if indexer password wasn't set
# (old format had separate dashboard password; new format uses indexer password for both)
if [ -z "$OLD_INDEXER_PASSWORD" ] && [ -n "$OLD_DASHBOARD_PASSWORD" ]; then
    OLD_INDEXER_PASSWORD="$OLD_DASHBOARD_PASSWORD"
    print_info "Using old dashboard password as indexer admin password"
fi

# Generate any missing credentials
FINAL_INDEXER_PASSWORD="${OLD_INDEXER_PASSWORD}"
if [ -z "$FINAL_INDEXER_PASSWORD" ]; then
    FINAL_INDEXER_PASSWORD=$(generate_password 24)
    print_warning "No indexer password found - GENERATED NEW ONE"
    print_warning "If you have an existing deployment, you MUST set this to your current password!"
fi

FINAL_API_PASSWORD="${OLD_API_PASSWORD}"
if [ -z "$FINAL_API_PASSWORD" ]; then
    FINAL_API_PASSWORD=$(generate_password 24)
    print_warning "No API password found - GENERATED NEW ONE"
    print_warning "If you have an existing deployment, you MUST set this to your current password!"
fi

FINAL_ENROLLMENT_PASSWORD="${OLD_ENROLLMENT_PASSWORD}"
if [ -z "$FINAL_ENROLLMENT_PASSWORD" ]; then
    FINAL_ENROLLMENT_PASSWORD=$(generate_password 24)
    print_info "Generated new agent enrollment password"
fi

FINAL_CLUSTER_KEY="${OLD_CLUSTER_KEY}"
if [ -z "$FINAL_CLUSTER_KEY" ]; then
    FINAL_CLUSTER_KEY=$(generate_password 32)
    if [ "$CLUSTER_ENABLED" = "true" ]; then
        print_warning "No cluster key found - GENERATED NEW ONE"
        print_warning "If you have an existing cluster, you MUST set this to your current key!"
    fi
fi

# ═══════════════════════════════════════════════════════════════
# Create group_vars/all/main.yml
# ═══════════════════════════════════════════════════════════════

print_info "Creating group_vars/all/main.yml..."

mkdir -p "$VAULT_DIR"

# Handle variable translations
if [ -n "$OLD_GENERATE_CERTS" ]; then
    # Old format: wazuh_generate_certs (true = self-signed)
    # New format: wazuh_use_external_ca (false = self-signed)
    if [ "$OLD_GENERATE_CERTS" = "true" ]; then
        USE_EXTERNAL_CA="false"
    else
        USE_EXTERNAL_CA="true"
    fi
fi

cat > "$NEW_MAIN_YML" << EOF
---
# Wazuh Ansible Deployment - Group Variables
# Migrated from main branch format on $(date)

# ═══════════════════════════════════════════════════════════════
# General Settings
# ═══════════════════════════════════════════════════════════════
wazuh_version: "${WAZUH_VERSION:-4.14.2}"
environment_name: "${ENVIRONMENT_NAME:-production}"
organization_name: "${ORGANIZATION_NAME:-MyOrganization}"

# ═══════════════════════════════════════════════════════════════
# Wazuh Indexer Settings
# ═══════════════════════════════════════════════════════════════
wazuh_indexer_cluster_name: "${INDEXER_CLUSTER_NAME:-wazuh-cluster}"
wazuh_indexer_http_port: ${INDEXER_HTTP_PORT:-9200}
wazuh_indexer_transport_port: ${INDEXER_TRANSPORT_PORT:-9300}
wazuh_indexer_heap_size: "${INDEXER_HEAP_SIZE:-auto}"
# Indexer admin credentials
wazuh_indexer_admin_user: "${INDEXER_ADMIN_USER:-admin}"
# Indexer admin password loaded from Ansible Vault
# SECURITY: Password encrypted in group_vars/all/vault.yml
# To view/edit: ansible-vault view/edit group_vars/all/vault.yml --vault-password-file .vault_password
wazuh_indexer_admin_password: "{{ vault_wazuh_indexer_admin_password }}"

# Indexer node list for cluster configuration
wazuh_indexer_nodes:
${INDEXER_NODES:-  - name: indexer-1
    ip: 127.0.0.1}

# ═══════════════════════════════════════════════════════════════
# Wazuh Manager Settings
# ═══════════════════════════════════════════════════════════════
wazuh_manager_api_port: ${MANAGER_API_PORT:-55000}
wazuh_manager_agent_port: ${MANAGER_AGENT_PORT:-1514}
wazuh_api_user: "${API_USER:-wazuh}"
# API password loaded from Ansible Vault
# SECURITY: Password encrypted in group_vars/all/vault.yml
wazuh_api_password: "{{ vault_wazuh_api_password }}"
wazuh_agent_enrollment_password: "{{ vault_wazuh_agent_enrollment_password }}"
wazuh_manager_cluster_enabled: ${CLUSTER_ENABLED}

# Manager node list
wazuh_manager_nodes:
${MANAGER_NODES:-  - name: manager-1
    ip: 127.0.0.1}

# ═══════════════════════════════════════════════════════════════
# Wazuh Dashboard Settings
# ═══════════════════════════════════════════════════════════════
wazuh_dashboard_port: ${DASHBOARD_PORT:-443}
# Dashboard uses the indexer admin credentials (admin user)

# Dashboard node list
wazuh_dashboard_nodes:
${DASHBOARD_NODES:-  - ip: 127.0.0.1}

# ═══════════════════════════════════════════════════════════════
# SSL/TLS Configuration
# ═══════════════════════════════════════════════════════════════

# Certificate type: self-signed or external CA
wazuh_use_external_ca: ${USE_EXTERNAL_CA:-false}

# Local path where certificates are stored (source for Ansible copy)
wazuh_certs_path: "${CERTS_PATH:-files/certs}"

# Certificate paths on target hosts (destination)
wazuh_indexer_certs_path: /etc/wazuh-indexer/certs
wazuh_manager_certs_path: /var/ossec/etc/certs
wazuh_dashboard_certs_path: /etc/wazuh-dashboard/certs

# SSL certificate verification (set to false for self-signed certs)
wazuh_ssl_verify_certificates: ${SSL_VERIFY:-false}

# ═══════════════════════════════════════════════════════════════
# Security Feature Toggles
# ═══════════════════════════════════════════════════════════════
wazuh_vulnerability_detection_enabled: ${VULN_DETECTION}
wazuh_fim_enabled: ${FIM_ENABLED}
wazuh_rootkit_detection_enabled: ${ROOTKIT_ENABLED}
wazuh_sca_enabled: ${SCA_ENABLED}
wazuh_syscollector_enabled: ${SYSCOLLECTOR_ENABLED}
wazuh_log_collection_enabled: ${LOG_COLLECTION}
wazuh_active_response_enabled: ${ACTIVE_RESPONSE}

# Email alerts
wazuh_email_notification_enabled: ${EMAIL_ENABLED}

# Syslog output
wazuh_syslog_output_enabled: ${SYSLOG_ENABLED}

# Integrations
wazuh_integrations: []

# ═══════════════════════════════════════════════════════════════
# Network/Firewall Settings
# ═══════════════════════════════════════════════════════════════
wazuh_configure_firewall: ${FIREWALL_ENABLED}
wazuh_configure_selinux: ${SELINUX_ENABLED}

# Package repository settings
wazuh_repo_gpg_key: "https://packages.wazuh.com/key/GPG-KEY-WAZUH"
wazuh_repo_url_apt: "https://packages.wazuh.com/4.x/apt/"
wazuh_repo_url_yum: "https://packages.wazuh.com/4.x/yum/"

# ═══════════════════════════════════════════════════════════════
# Backup & Maintenance
# ═══════════════════════════════════════════════════════════════
wazuh_backup_schedule: "daily"
wazuh_backup_hour: 2
wazuh_backup_day: 0
wazuh_backup_retention: 7

wazuh_log_cleanup_enabled: true
wazuh_log_retention_days: 30
wazuh_log_cleanup_schedule: "daily"

# ═══════════════════════════════════════════════════════════════
# Post-Deployment Security
# ═══════════════════════════════════════════════════════════════
wazuh_lockdown_deploy_user: true

# ═══════════════════════════════════════════════════════════════
# Automatic Index Management (Prevents 1000 Index Limit)
# ═══════════════════════════════════════════════════════════════
wazuh_rollover_enabled: true

wazuh_rollover_max_size: "30gb"
wazuh_rollover_max_age: "1d"
wazuh_rollover_max_docs: 50000000

wazuh_retention_enabled: true
wazuh_retention_days: 365
wazuh_retention_warm_after_days: 7
wazuh_retention_cold_after_days: 30

wazuh_close_cold_indices: true

wazuh_monitoring_retention_days: 7
wazuh_statistics_retention_days: 7

wazuh_alerts_primary_shards: 1
wazuh_alerts_replica_shards: 0

# ═══════════════════════════════════════════════════════════════
# Health Check & Timeout Settings
# ═══════════════════════════════════════════════════════════════
wazuh_indexer_startup_timeout: 300
wazuh_indexer_health_check_retries: 30
wazuh_indexer_health_check_delay: 10

wazuh_service_start_timeout: 300
wazuh_api_check_retries: 30
wazuh_api_check_delay: 10

wazuh_dashboard_startup_timeout: 300
wazuh_dashboard_health_check_retries: 30
wazuh_dashboard_health_check_delay: 10

# ═══════════════════════════════════════════════════════════════
# Log Rotation
# ═══════════════════════════════════════════════════════════════
wazuh_log_rotation_enabled: true
wazuh_log_rotation_keep_days: 30
wazuh_log_rotation_max_size: "100M"
wazuh_log_rotation_compress: true
EOF

print_success "Created: group_vars/all/main.yml"

# ═══════════════════════════════════════════════════════════════
# Create encrypted vault
# ═══════════════════════════════════════════════════════════════

print_info "Creating encrypted vault..."

vault_content="---
# Wazuh Deployment - Encrypted Credentials
# Migrated from main branch format on $(date -Iseconds)
# DO NOT COMMIT THIS FILE UNENCRYPTED!

# Ansible SSH user for deployment
vault_ansible_user: \"wazuh-deploy\"

# Ansible connection password (SSH/WinRM)
vault_ansible_connection_password: \"\"

# Ansible become (sudo) password
vault_ansible_become_password: \"\"

# Bootstrap SSH password (for initial setup only)
vault_bootstrap_ssh_pass: \"\"

# Indexer/Dashboard admin credentials
vault_wazuh_indexer_admin_password: \"${FINAL_INDEXER_PASSWORD}\"

# Wazuh API credentials
vault_wazuh_api_password: \"${FINAL_API_PASSWORD}\"

# Agent enrollment password
vault_wazuh_agent_enrollment_password: \"${FINAL_ENROLLMENT_PASSWORD}\"

# Manager cluster key (for multi-node deployments)
vault_wazuh_manager_cluster_key: \"${FINAL_CLUSTER_KEY}\"
"

echo "$vault_content" > "${VAULT_FILE}.tmp"
ansible-vault encrypt "${VAULT_FILE}.tmp" --vault-password-file "$VAULT_PASSWORD_FILE" --encrypt-vault-id default --output "$VAULT_FILE"
rm -f "${VAULT_FILE}.tmp"
chmod 600 "$VAULT_FILE"

print_success "Created: group_vars/all/vault.yml (encrypted)"

# ═══════════════════════════════════════════════════════════════
# Rename old all.yml
# ═══════════════════════════════════════════════════════════════

if [ "$MIGRATION_CASE" = "flat_file" ] && [ -f "$OLD_ALL_YML" ]; then
    mv "$OLD_ALL_YML" "${OLD_ALL_YML}.migrated"
    print_success "Renamed: group_vars/all.yml → group_vars/all.yml.migrated"
fi

# ═══════════════════════════════════════════════════════════════
# Validate
# ═══════════════════════════════════════════════════════════════

print_info "Validating migration..."

validation_ok=true
vault_output=$(ansible-vault view "$VAULT_FILE" --vault-password-file "$VAULT_PASSWORD_FILE" 2>/dev/null)

for var in vault_wazuh_indexer_admin_password vault_wazuh_api_password vault_wazuh_agent_enrollment_password vault_wazuh_manager_cluster_key vault_ansible_user; do
    if echo "$vault_output" | grep -q "^${var}:"; then
        print_success "Vault contains: $var"
    else
        print_error "Vault MISSING: $var"
        validation_ok=false
    fi
done

if [ "$validation_ok" = "true" ]; then
    echo ""
    print_success "Validation passed!"
else
    echo ""
    print_error "Validation failed - check the errors above"
    exit 1
fi

# ═══════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════

print_header "Migration Complete"

echo -e "  ${GREEN}Files created:${NC}"
echo "    group_vars/all/main.yml   - Configuration (vault references)"
echo "    group_vars/all/vault.yml  - Encrypted credentials"
echo ""
echo -e "  ${GREEN}Backups:${NC}"
[ -f "${OLD_ALL_YML}.pre-migration-backup.${TIMESTAMP}" ] && echo "    group_vars/all.yml.pre-migration-backup.${TIMESTAMP}"
[ -f "${NEW_MAIN_YML}.pre-migration-backup.${TIMESTAMP}" ] && echo "    group_vars/all/main.yml.pre-migration-backup.${TIMESTAMP}"
[ -f "${VAULT_FILE}.pre-migration-backup.${TIMESTAMP}" ] && echo "    group_vars/all/vault.yml.pre-migration-backup.${TIMESTAMP}"

echo ""
echo -e "  ${GREEN}Credential status:${NC}"
if [ -n "$OLD_INDEXER_PASSWORD" ]; then
    echo -e "    Indexer password:    ${GREEN}migrated from old config${NC}"
else
    echo -e "    Indexer password:    ${YELLOW}NEWLY GENERATED${NC}"
fi
if [ -n "$OLD_API_PASSWORD" ]; then
    echo -e "    API password:        ${GREEN}migrated from old config${NC}"
else
    echo -e "    API password:        ${YELLOW}NEWLY GENERATED${NC}"
fi
if [ -n "$OLD_ENROLLMENT_PASSWORD" ]; then
    echo -e "    Enrollment password: ${GREEN}migrated from old config${NC}"
else
    echo -e "    Enrollment password: ${YELLOW}newly generated (new in 1.1)${NC}"
fi
if [ -n "$OLD_CLUSTER_KEY" ]; then
    echo -e "    Cluster key:         ${GREEN}migrated from old config${NC}"
else
    echo -e "    Cluster key:         ${YELLOW}newly generated${NC}"
fi

echo ""
echo -e "  ${CYAN}New features in 1.1 (review in main.yml):${NC}"
echo "    - Index rollover & ISM lifecycle management"
echo "    - Deploy user lockdown after deployment"
echo "    - Automated backup scheduling"
echo "    - Health check timeouts (configurable)"
echo "    - Split certificate paths per component"

echo ""
echo -e "  ${YELLOW}Next steps:${NC}"
echo "    1. Review credentials:    ./scripts/manage-vault.sh view"
echo "    2. Review main.yml:       cat group_vars/all/main.yml"
echo "    3. Update node IPs if needed in main.yml and inventory/hosts.yml"
echo "    4. Test connectivity:     ansible all -m ping"
echo "    5. Deploy:                ansible-playbook site.yml"

if [ -z "$OLD_INDEXER_PASSWORD" ] || [ -z "$OLD_API_PASSWORD" ]; then
    echo ""
    echo -e "  ${RED}WARNING: Some passwords were newly generated because they${NC}"
    echo -e "  ${RED}weren't found in the old config. If you have an existing${NC}"
    echo -e "  ${RED}deployment, edit the vault to set your current passwords:${NC}"
    echo -e "  ${YELLOW}  sudo ./scripts/manage-vault.sh edit${NC}"
fi

echo ""
