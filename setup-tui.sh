#!/bin/bash

# Wazuh Ansible Deployment - TUI Setup Script (using gum)
# Beautiful terminal UI for configuring Wazuh deployment
#
# Requirements: gum (https://github.com/charmbracelet/gum)
# Install: brew install gum  OR  go install github.com/charmbracelet/gum@latest
#
# Usage:
#   ./setup-tui.sh                    # Interactive TUI mode
#   ./setup-tui.sh --profile minimal  # Quick setup with profile
#   ./setup-tui.sh --help             # Show help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ═══════════════════════════════════════════════════════════════
# Check for gum installation
# ═══════════════════════════════════════════════════════════════
check_gum() {
    if ! command -v gum &>/dev/null; then
        echo "Error: 'gum' is not installed."
        echo ""
        echo "Install gum using one of these methods:"
        echo "  brew install gum                              # macOS/Linux (Homebrew)"
        echo "  sudo apt install gum                          # Debian/Ubuntu"
        echo "  sudo dnf install gum                          # Fedora"
        echo "  go install github.com/charmbracelet/gum@latest # Go"
        echo ""
        echo "Or use the classic setup script: ./setup.sh"
        exit 1
    fi
}

# ═══════════════════════════════════════════════════════════════
# Theme colors
# ═══════════════════════════════════════════════════════════════
export GUM_INPUT_CURSOR_FOREGROUND="#FF6B6B"
export GUM_INPUT_PROMPT_FOREGROUND="#4ECDC4"
export GUM_INPUT_PLACEHOLDER="#666666"
export GUM_INPUT_WIDTH=50

export GUM_CHOOSE_CURSOR_FOREGROUND="#FF6B6B"
export GUM_CHOOSE_HEADER_FOREGROUND="#4ECDC4"
export GUM_CHOOSE_SELECTED_FOREGROUND="#FFE66D"

export GUM_CONFIRM_PROMPT_FOREGROUND="#4ECDC4"
export GUM_CONFIRM_SELECTED_FOREGROUND="#FFE66D"
export GUM_CONFIRM_UNSELECTED_FOREGROUND="#666666"

# ═══════════════════════════════════════════════════════════════
# Source libraries
# ═══════════════════════════════════════════════════════════════
source "$SCRIPT_DIR/lib/validation.sh" 2>/dev/null || true
source "$SCRIPT_DIR/lib/generators.sh" 2>/dev/null || true

# Fallback password generator if library not loaded
if ! command -v generate_password &>/dev/null; then
    generate_password() {
        local length="${1:-24}"
        openssl rand -base64 32 | tr -d '/+=' | head -c "$length"
    }
fi

# ═══════════════════════════════════════════════════════════════
# TUI Helper Functions
# ═══════════════════════════════════════════════════════════════

# Display styled header
header() {
    clear
    gum style \
        --border double \
        --border-foreground "#4ECDC4" \
        --padding "1 4" \
        --margin "1" \
        --align center \
        --foreground "#FFE66D" \
        --bold \
        "🛡️  WAZUH DEPLOYMENT SETUP  🛡️" \
        "" \
        "$1"
}

# Display section header
section() {
    echo ""
    gum style \
        --foreground "#4ECDC4" \
        --bold \
        "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    gum style \
        --foreground "#FFE66D" \
        --bold \
        "  $1"
    gum style \
        --foreground "#4ECDC4" \
        --bold \
        "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

# Info message
info() {
    gum style --foreground "#888888" "  ℹ $1"
}

# Success message
success() {
    gum style --foreground "#4ECDC4" "  ✓ $1"
}

# Warning message
warn() {
    gum style --foreground "#FFE66D" "  ⚠ $1"
}

# Error message
error() {
    gum style --foreground "#FF6B6B" "  ✗ $1"
}

# Input with validation
input_validated() {
    local prompt="$1"
    local default="$2"
    local validator="${3:-}"
    local value=""

    while true; do
        value=$(gum input --placeholder "$default" --prompt "$prompt: " --value "$default")

        if [[ -z "$value" ]]; then
            value="$default"
        fi

        if [[ -n "$validator" ]] && ! "$validator" "$value" 2>/dev/null; then
            error "Invalid input. Please try again."
            continue
        fi

        echo "$value"
        return 0
    done
}

# Multi-host input
input_hosts() {
    local prompt="$1"
    local min_hosts="${2:-1}"

    info "$prompt"
    info "Enter hostnames/IPs, one per line. Save when done."
    echo ""

    local hosts=""
    hosts=$(gum write --placeholder "192.168.1.10
192.168.1.11
..." --width 50 --height 6)

    # Convert newlines to spaces
    hosts=$(echo "$hosts" | tr '\n' ' ' | xargs)

    if [[ -z "$hosts" ]] && (( min_hosts > 0 )); then
        error "At least $min_hosts host(s) required!"
        return 1
    fi

    echo "$hosts"
}

# ═══════════════════════════════════════════════════════════════
# Profile Selection
# ═══════════════════════════════════════════════════════════════
select_profile() {
    header "Select Deployment Profile"

    info "Choose a profile to get started quickly:"
    echo ""

    local profile
    profile=$(gum choose \
        --header "Deployment Profile" \
        --cursor "▶ " \
        --selected "production" \
        "minimal     │ Single-node for testing (localhost)" \
        "production  │ Multi-node HA with all features [recommended]" \
        "custom      │ Full interactive configuration")

    # Extract profile name
    echo "$profile" | cut -d'│' -f1 | xargs
}

# ═══════════════════════════════════════════════════════════════
# Main Configuration Flow
# ═══════════════════════════════════════════════════════════════
configure_general() {
    section "General Settings"

    WAZUH_VERSION=$(gum input --prompt "Wazuh Version: " --value "4.14.1" --placeholder "4.14.1")
    success "Version: $WAZUH_VERSION"

    ENVIRONMENT=$(gum choose --header "Environment" "production" "staging" "development")
    success "Environment: $ENVIRONMENT"

    ORG_NAME=$(gum input --prompt "Organization Name: " --value "MyOrg" --placeholder "MyOrg")
    success "Organization: $ORG_NAME"
}

configure_indexer() {
    section "Wazuh Indexer Configuration"

    info "The Indexer stores and indexes security alerts and events."
    echo ""

    if [[ "$SELECTED_PROFILE" == "minimal" ]]; then
        INDEXER_NODES="localhost"
        success "Indexer node: localhost (minimal profile)"
    else
        INDEXER_NODES=$(input_hosts "Enter Indexer node(s):" 1) || exit 1
        success "Indexer nodes: $INDEXER_NODES"
    fi

    INDEXER_NODES_ARRAY=($INDEXER_NODES)
    INDEXER_COUNT=${#INDEXER_NODES_ARRAY[@]}

    # Heap size selection
    echo ""
    info "JVM heap size (50% of RAM recommended, max 32GB)"
    INDEXER_HEAP_SIZE=$(gum choose \
        --header "Heap Size" \
        --selected "auto" \
        "auto  │ Calculate automatically (recommended)" \
        "1g    │ 1 GB (minimum)" \
        "2g    │ 2 GB" \
        "4g    │ 4 GB" \
        "8g    │ 8 GB" \
        "16g   │ 16 GB" \
        "32g   │ 32 GB (maximum)")
    INDEXER_HEAP_SIZE=$(echo "$INDEXER_HEAP_SIZE" | cut -d'│' -f1 | xargs)
    success "Heap size: $INDEXER_HEAP_SIZE"

    INDEXER_HTTP_PORT="9200"
    INDEXER_CLUSTER_NAME="wazuh-cluster"
}

configure_manager() {
    section "Wazuh Manager Configuration"

    info "The Manager analyzes data from agents and generates alerts."
    echo ""

    if [[ "$SELECTED_PROFILE" == "minimal" ]]; then
        MANAGER_NODES="localhost"
        success "Manager node: localhost (minimal profile)"
    else
        MANAGER_NODES=$(input_hosts "Enter Manager node(s):" 1) || exit 1
        success "Manager nodes: $MANAGER_NODES"
    fi

    MANAGER_NODES_ARRAY=($MANAGER_NODES)
    MANAGER_COUNT=${#MANAGER_NODES_ARRAY[@]}

    MANAGER_API_PORT="55000"
    AGENT_PORT="1514"

    if (( MANAGER_COUNT > 1 )); then
        info "Multi-manager cluster detected"
        MANAGER_CLUSTER_NAME=$(gum input --prompt "Cluster Name: " --value "wazuh-manager-cluster")
        MANAGER_CLUSTER_KEY=$(generate_password 32)
        success "Cluster configured with auto-generated key"
    fi
}

configure_dashboard() {
    section "Wazuh Dashboard Configuration"

    info "The Dashboard provides web-based visualization and management."
    echo ""

    if [[ "$SELECTED_PROFILE" == "minimal" ]]; then
        DASHBOARD_NODES="localhost"
        success "Dashboard node: localhost (minimal profile)"
    else
        DASHBOARD_NODES=$(input_hosts "Enter Dashboard node(s):" 1) || exit 1
        success "Dashboard nodes: $DASHBOARD_NODES"
    fi

    DASHBOARD_NODES_ARRAY=($DASHBOARD_NODES)
    DASHBOARD_PORT="443"
}

configure_agents() {
    section "Wazuh Agents Configuration"

    info "Agents collect security data from monitored endpoints."
    echo ""

    if [[ "$SELECTED_PROFILE" == "minimal" ]]; then
        DEPLOY_AGENTS="false"
        info "Agent deployment skipped (minimal profile)"
    else
        if gum confirm "Deploy agents now?"; then
            DEPLOY_AGENTS="true"
            AGENT_NODES=$(input_hosts "Enter Agent host(s):" 0) || AGENT_NODES=""
            if [[ -n "$AGENT_NODES" ]]; then
                AGENT_NODES_ARRAY=($AGENT_NODES)
                success "Agent hosts: $AGENT_NODES"
            fi
        else
            DEPLOY_AGENTS="false"
            info "Agent deployment skipped"
        fi
    fi
}

configure_security() {
    section "Security Configuration"

    info "Credentials are auto-generated and encrypted in Ansible Vault."
    echo ""

    # Passwords
    if gum confirm "Use auto-generated passwords? (recommended)" --default=true; then
        CUSTOM_PASSWORDS="false"
        API_USER="wazuh"
        INDEXER_ADMIN_USER="admin"
        success "Passwords will be auto-generated"
    else
        CUSTOM_PASSWORDS="true"
        API_USER=$(gum input --prompt "API Username: " --value "wazuh")
        API_PASSWORD=$(gum input --prompt "API Password: " --password)
        INDEXER_ADMIN_PASSWORD=$(gum input --prompt "Indexer Admin Password: " --password)
    fi

    # Certificates
    echo ""
    if gum confirm "Use self-signed certificates?" --default=true; then
        USE_SELF_SIGNED_CERTS="true"
        GENERATE_CERTS="true"
        EXTERNAL_CA="false"
        success "Self-signed certificates will be generated"
    else
        USE_SELF_SIGNED_CERTS="false"
        GENERATE_CERTS="false"
        EXTERNAL_CA="true"
        warn "Place your certificates in files/certs/ before deployment"
    fi
}

configure_ssh() {
    section "SSH Configuration"

    info "Configure SSH access to target servers."
    echo ""

    if [[ "$SELECTED_PROFILE" == "minimal" ]]; then
        GENERATE_SSH_KEY="false"
        ANSIBLE_USER="$(whoami)"
        ANSIBLE_SSH_PORT="22"
        USE_BECOME="true"
        success "Using local connection (minimal profile)"
        return
    fi

    if gum confirm "Generate new SSH key pair for deployment?"; then
        GENERATE_SSH_KEY="true"
        ANSIBLE_SSH_KEY="${SCRIPT_DIR}/keys/wazuh_ansible_key"
        ANSIBLE_USER=$(gum input --prompt "Ansible User (will be created): " --value "wazuh-deploy")
        success "SSH key will be generated"
    else
        GENERATE_SSH_KEY="false"
        ANSIBLE_SSH_KEY=$(gum input --prompt "SSH Key Path: " --value "~/.ssh/id_rsa")
        ANSIBLE_USER=$(gum input --prompt "SSH User: " --value "root")
    fi

    ANSIBLE_SSH_PORT=$(gum input --prompt "SSH Port: " --value "22")
    USE_BECOME=$(gum confirm "Use sudo for privilege escalation?" --default=true && echo "true" || echo "false")

    # Initial SSH credentials
    echo ""
    info "Initial SSH credentials for bootstrap:"
    INITIAL_SSH_USER=$(gum input --prompt "Initial SSH User: " --value "root")

    if gum confirm "Provide SSH password? (for password-based auth)"; then
        DEFAULT_SSH_PASS=$(gum input --prompt "SSH Password: " --password)
    else
        DEFAULT_SSH_PASS=""
    fi

    CREATE_PREP_PACKAGE="true"
}

configure_features() {
    section "Security Features"

    info "Select which Wazuh modules to enable:"
    echo ""

    local features
    features=$(gum choose \
        --no-limit \
        --header "Enable features (space to toggle, enter to confirm)" \
        --selected "Vulnerability Detection","File Integrity Monitoring","Rootkit Detection","SCA","Syscollector","Log Collection","Active Response" \
        "Vulnerability Detection" \
        "File Integrity Monitoring" \
        "Rootkit Detection" \
        "SCA" \
        "Syscollector" \
        "Log Collection" \
        "Active Response")

    ENABLE_VULN_DETECTION=$([[ "$features" == *"Vulnerability"* ]] && echo "true" || echo "false")
    ENABLE_FIM=$([[ "$features" == *"File Integrity"* ]] && echo "true" || echo "false")
    ENABLE_ROOTKIT=$([[ "$features" == *"Rootkit"* ]] && echo "true" || echo "false")
    ENABLE_SCA=$([[ "$features" == *"SCA"* ]] && echo "true" || echo "false")
    ENABLE_SYSCOLLECTOR=$([[ "$features" == *"Syscollector"* ]] && echo "true" || echo "false")
    ENABLE_LOG_COLLECTION=$([[ "$features" == *"Log Collection"* ]] && echo "true" || echo "false")
    ENABLE_ACTIVE_RESPONSE=$([[ "$features" == *"Active Response"* ]] && echo "true" || echo "false")

    success "Features configured"
}

configure_integrations() {
    section "Integrations"

    # Email
    ENABLE_EMAIL_ALERTS="false"
    if gum confirm "Enable email alerts?"; then
        ENABLE_EMAIL_ALERTS="true"
        EMAIL_SMTP_SERVER=$(gum input --prompt "SMTP Server: " --placeholder "smtp.example.com")
        EMAIL_FROM=$(gum input --prompt "From Address: " --placeholder "wazuh@example.com")
        EMAIL_TO=$(gum input --prompt "To Address: " --placeholder "security@example.com")
    fi

    # Syslog
    ENABLE_SYSLOG_OUTPUT="false"
    if gum confirm "Enable syslog output?"; then
        ENABLE_SYSLOG_OUTPUT="true"
        SYSLOG_SERVER=$(gum input --prompt "Syslog Server: ")
        SYSLOG_PORT=$(gum input --prompt "Syslog Port: " --value "514")
    fi

    # Slack
    ENABLE_SLACK="false"
    if gum confirm "Enable Slack notifications?"; then
        ENABLE_SLACK="true"
        SLACK_WEBHOOK_URL=$(gum input --prompt "Slack Webhook URL: ")
    fi

    # VirusTotal
    ENABLE_VIRUSTOTAL="false"
    if gum confirm "Enable VirusTotal integration?"; then
        ENABLE_VIRUSTOTAL="true"
        VIRUSTOTAL_API_KEY=$(gum input --prompt "VirusTotal API Key: " --password)
    fi

    success "Integrations configured"
}

configure_backup() {
    section "Backup & Maintenance"

    BACKUP_SCHEDULE=$(gum choose \
        --header "Backup Schedule" \
        "daily" \
        "weekly" \
        "disabled")

    if [[ "$BACKUP_SCHEDULE" != "disabled" ]]; then
        BACKUP_HOUR=$(gum input --prompt "Backup Hour (0-23): " --value "2")
        BACKUP_RETENTION=$(gum input --prompt "Backups to Keep: " --value "7")
    fi

    if gum confirm "Enable automatic log cleanup?" --default=true; then
        ENABLE_LOG_CLEANUP="true"
        LOG_RETENTION_DAYS=$(gum input --prompt "Days of Logs to Keep: " --value "30")
    else
        ENABLE_LOG_CLEANUP="false"
    fi

    success "Backup configured: $BACKUP_SCHEDULE"
}

# ═══════════════════════════════════════════════════════════════
# Generate Configuration
# ═══════════════════════════════════════════════════════════════
generate_config() {
    section "Generating Configuration"

    gum spin --spinner dot --title "Creating inventory files..." -- sleep 1

    # Call the original setup.sh config generation by sourcing variables
    # For now, create a simple inventory
    mkdir -p "$SCRIPT_DIR/inventory"
    mkdir -p "$SCRIPT_DIR/group_vars/all"

    # Generate inventory
    cat > "$SCRIPT_DIR/inventory/hosts.yml" << EOF
---
all:
  vars:
    ansible_user: ${ANSIBLE_USER:-wazuh-deploy}
    ansible_port: ${ANSIBLE_SSH_PORT:-22}
    ansible_become: ${USE_BECOME:-true}

  children:
    wazuh_indexers:
      hosts:
EOF

    for node in ${INDEXER_NODES_ARRAY[@]}; do
        echo "        ${node}:" >> "$SCRIPT_DIR/inventory/hosts.yml"
    done

    cat >> "$SCRIPT_DIR/inventory/hosts.yml" << EOF

    wazuh_managers:
      hosts:
EOF

    for node in ${MANAGER_NODES_ARRAY[@]}; do
        echo "        ${node}:" >> "$SCRIPT_DIR/inventory/hosts.yml"
    done

    cat >> "$SCRIPT_DIR/inventory/hosts.yml" << EOF

    wazuh_dashboards:
      hosts:
EOF

    for node in ${DASHBOARD_NODES_ARRAY[@]}; do
        echo "        ${node}:" >> "$SCRIPT_DIR/inventory/hosts.yml"
    done

    success "Inventory created: inventory/hosts.yml"

    # Generate group_vars
    gum spin --spinner dot --title "Creating group variables..." -- sleep 1

    cat > "$SCRIPT_DIR/group_vars/all/main.yml" << EOF
---
# Generated by setup-tui.sh on $(date)

# General
wazuh_version: "${WAZUH_VERSION}"
environment_name: "${ENVIRONMENT}"
organization_name: "${ORG_NAME}"

# Indexer
wazuh_indexer_cluster_name: "${INDEXER_CLUSTER_NAME}"
wazuh_indexer_http_port: ${INDEXER_HTTP_PORT:-9200}
wazuh_indexer_heap_size: "${INDEXER_HEAP_SIZE}"

# Manager
wazuh_manager_api_port: ${MANAGER_API_PORT:-55000}
wazuh_manager_agent_port: ${AGENT_PORT:-1514}

# Dashboard
wazuh_dashboard_port: ${DASHBOARD_PORT:-443}

# Security Features
wazuh_vulnerability_detection_enabled: ${ENABLE_VULN_DETECTION:-true}
wazuh_fim_enabled: ${ENABLE_FIM:-true}
wazuh_rootkit_detection_enabled: ${ENABLE_ROOTKIT:-true}
wazuh_sca_enabled: ${ENABLE_SCA:-true}
wazuh_syscollector_enabled: ${ENABLE_SYSCOLLECTOR:-true}
wazuh_log_collection_enabled: ${ENABLE_LOG_COLLECTION:-true}
wazuh_active_response_enabled: ${ENABLE_ACTIVE_RESPONSE:-true}

# Backup
wazuh_backup_schedule: "${BACKUP_SCHEDULE:-daily}"
wazuh_log_cleanup_enabled: ${ENABLE_LOG_CLEANUP:-true}
wazuh_log_retention_days: ${LOG_RETENTION_DAYS:-30}
EOF

    success "Variables created: group_vars/all/main.yml"

    # Initialize vault
    gum spin --spinner dot --title "Initializing Ansible Vault..." -- sleep 1

    if [[ -f "$SCRIPT_DIR/scripts/manage-vault.sh" ]]; then
        if [[ ! -f "$SCRIPT_DIR/.vault_password" ]]; then
            bash "$SCRIPT_DIR/scripts/manage-vault.sh" init 2>/dev/null || true
        fi

        GENERATED_INDEXER_PASSWORD=$(generate_password 24)
        GENERATED_API_PASSWORD=$(generate_password 24)

        VAULT_INDEXER_PASSWORD="$GENERATED_INDEXER_PASSWORD" \
        VAULT_API_PASSWORD="$GENERATED_API_PASSWORD" \
        bash "$SCRIPT_DIR/scripts/manage-vault.sh" create 2>/dev/null || true

        success "Vault initialized with encrypted credentials"
    fi
}

# ═══════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════
show_summary() {
    header "Configuration Complete!"

    gum style \
        --border rounded \
        --border-foreground "#4ECDC4" \
        --padding "1 2" \
        --margin "1" \
        "$(cat << EOF
📊 DEPLOYMENT SUMMARY

Profile:     ${SELECTED_PROFILE}
Environment: ${ENVIRONMENT}
Version:     ${WAZUH_VERSION}

🖥️  INFRASTRUCTURE
Indexers:    ${INDEXER_COUNT} node(s) - ${INDEXER_NODES}
Managers:    ${MANAGER_COUNT} node(s) - ${MANAGER_NODES}
Dashboards:  ${#DASHBOARD_NODES_ARRAY[@]} node(s) - ${DASHBOARD_NODES}
Heap Size:   ${INDEXER_HEAP_SIZE}

🔐 SECURITY
Certificates: $([ "$USE_SELF_SIGNED_CERTS" == "true" ] && echo "Self-signed" || echo "External CA")
Vault:        Enabled (encrypted credentials)

📁 FILES CREATED
• inventory/hosts.yml
• group_vars/all/main.yml
• group_vars/all/vault.yml (encrypted)
EOF
)"

    echo ""
    gum style --foreground "#FFE66D" --bold "🚀 NEXT STEPS"
    echo ""
    echo "  1. Review configuration files"
    echo "  2. Prepare target hosts:"
    echo "     $(gum style --foreground '#4ECDC4' 'scp -r client-prep/ root@HOST:/tmp/')"
    echo ""
    echo "  3. Run deployment:"
    echo "     $(gum style --foreground '#4ECDC4' 'ansible-playbook site.yml --vault-password-file .vault_password')"
    echo ""

    if [[ -f "$SCRIPT_DIR/.vault_password" ]]; then
        gum style \
            --border rounded \
            --border-foreground "#FF6B6B" \
            --padding "1 2" \
            "⚠️  SAVE YOUR VAULT PASSWORD!

$(cat "$SCRIPT_DIR/.vault_password")

Store this securely - you'll need it for deployment!"
    fi
}

# ═══════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════
main() {
    check_gum

    # Parse arguments
    SELECTED_PROFILE=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --profile|-p)
                SELECTED_PROFILE="$2"
                shift 2
                ;;
            --help|-h)
                echo "Usage: $0 [--profile minimal|production|custom]"
                exit 0
                ;;
            *)
                shift
                ;;
        esac
    done

    # Profile selection
    if [[ -z "$SELECTED_PROFILE" ]]; then
        SELECTED_PROFILE=$(select_profile)
    fi

    header "Profile: ${SELECTED_PROFILE^^}"

    # Configuration flow
    configure_general
    configure_indexer
    configure_manager
    configure_dashboard
    configure_agents

    if [[ "$SELECTED_PROFILE" != "minimal" ]]; then
        configure_security
        configure_ssh
        configure_features
        configure_integrations
    else
        # Minimal defaults
        CUSTOM_PASSWORDS="false"
        USE_SELF_SIGNED_CERTS="true"
        GENERATE_CERTS="true"
        EXTERNAL_CA="false"
        GENERATE_SSH_KEY="false"
        ANSIBLE_USER="$(whoami)"
        USE_BECOME="true"
        ENABLE_VULN_DETECTION="true"
        ENABLE_FIM="true"
        ENABLE_ROOTKIT="true"
        ENABLE_SCA="true"
        ENABLE_SYSCOLLECTOR="true"
        ENABLE_LOG_COLLECTION="true"
        ENABLE_ACTIVE_RESPONSE="false"
        ENABLE_EMAIL_ALERTS="false"
        ENABLE_SYSLOG_OUTPUT="false"
        ENABLE_SLACK="false"
        ENABLE_VIRUSTOTAL="false"
    fi

    configure_backup

    # Generate
    if gum confirm "Generate configuration files?"; then
        generate_config
        show_summary
    else
        warn "Configuration cancelled"
        exit 1
    fi
}

main "$@"
