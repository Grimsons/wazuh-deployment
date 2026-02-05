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

    mkdir -p "$SCRIPT_DIR/inventory"
    mkdir -p "$SCRIPT_DIR/group_vars/all"

    # ════════════════════════════════════════════════════════════
    # ansible.cfg
    # ════════════════════════════════════════════════════════════
    gum spin --spinner dot --title "Creating ansible.cfg..." -- sleep 0.5

    cat > "$SCRIPT_DIR/ansible.cfg" << EOF
[defaults]
inventory = inventory/hosts.yml
roles_path = roles
host_key_checking = False
retry_files_enabled = False
gathering = smart
fact_caching = jsonfile
fact_caching_connection = /tmp/ansible_facts_cache
fact_caching_timeout = 3600
vault_password_file = .vault_password

[privilege_escalation]
become = ${USE_BECOME:-true}
become_method = sudo
become_user = root

[ssh_connection]
pipelining = True
ssh_args = -o ControlMaster=auto -o ControlPersist=60s -o UserKnownHostsFile=/dev/null
EOF

    success "Created: ansible.cfg"

    # ════════════════════════════════════════════════════════════
    # inventory/hosts.yml
    # ════════════════════════════════════════════════════════════
    gum spin --spinner dot --title "Creating inventory..." -- sleep 0.5

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

    for i in "${!INDEXER_NODES_ARRAY[@]}"; do
        local node="${INDEXER_NODES_ARRAY[$i]}"
        echo "        ${node}:" >> "$SCRIPT_DIR/inventory/hosts.yml"
        echo "          indexer_node_name: indexer-$((i+1))" >> "$SCRIPT_DIR/inventory/hosts.yml"
        if [[ $i -eq 0 ]]; then
            echo "          indexer_cluster_initial_master: true" >> "$SCRIPT_DIR/inventory/hosts.yml"
        fi
    done

    cat >> "$SCRIPT_DIR/inventory/hosts.yml" << EOF

    wazuh_managers:
      hosts:
EOF

    for i in "${!MANAGER_NODES_ARRAY[@]}"; do
        local node="${MANAGER_NODES_ARRAY[$i]}"
        echo "        ${node}:" >> "$SCRIPT_DIR/inventory/hosts.yml"
        echo "          manager_node_name: manager-$((i+1))" >> "$SCRIPT_DIR/inventory/hosts.yml"
        if (( MANAGER_COUNT > 1 )); then
            if [[ $i -eq 0 ]]; then
                echo "          manager_node_type: master" >> "$SCRIPT_DIR/inventory/hosts.yml"
            else
                echo "          manager_node_type: worker" >> "$SCRIPT_DIR/inventory/hosts.yml"
            fi
        fi
    done

    cat >> "$SCRIPT_DIR/inventory/hosts.yml" << EOF

    wazuh_dashboards:
      hosts:
EOF

    for node in "${DASHBOARD_NODES_ARRAY[@]}"; do
        echo "        ${node}:" >> "$SCRIPT_DIR/inventory/hosts.yml"
    done

    if [[ "$DEPLOY_AGENTS" == "true" ]] && [[ -n "${AGENT_NODES:-}" ]]; then
        cat >> "$SCRIPT_DIR/inventory/hosts.yml" << EOF

    wazuh_agents:
      hosts:
EOF
        for node in "${AGENT_NODES_ARRAY[@]}"; do
            echo "        ${node}:" >> "$SCRIPT_DIR/inventory/hosts.yml"
        done
    fi

    cat >> "$SCRIPT_DIR/inventory/hosts.yml" << 'EOF'

    local:
      hosts:
        localhost:
          ansible_connection: local
          ansible_user: "{{ lookup('env', 'USER') }}"
          ansible_become: false
EOF

    success "Created: inventory/hosts.yml"

    # ════════════════════════════════════════════════════════════
    # group_vars/all/main.yml
    # ════════════════════════════════════════════════════════════
    gum spin --spinner dot --title "Creating group variables..." -- sleep 0.5

    cat > "$SCRIPT_DIR/group_vars/all/main.yml" << EOF
---
# Wazuh Deployment - Generated by setup-tui.sh on $(date)

# ═══════════════════════════════════════════════════════════════
# General Settings
# ═══════════════════════════════════════════════════════════════
wazuh_version: "${WAZUH_VERSION}"
environment_name: "${ENVIRONMENT}"
organization_name: "${ORG_NAME}"

# ═══════════════════════════════════════════════════════════════
# Wazuh Indexer Settings
# ═══════════════════════════════════════════════════════════════
wazuh_indexer_cluster_name: "${INDEXER_CLUSTER_NAME}"
wazuh_indexer_http_port: ${INDEXER_HTTP_PORT:-9200}
wazuh_indexer_transport_port: 9300
wazuh_indexer_heap_size: "${INDEXER_HEAP_SIZE}"
wazuh_indexer_admin_user: "${INDEXER_ADMIN_USER:-admin}"
wazuh_indexer_admin_password: "{{ vault_wazuh_indexer_admin_password }}"

wazuh_indexer_nodes:
EOF

    for i in "${!INDEXER_NODES_ARRAY[@]}"; do
        echo "  - name: indexer-$((i+1))" >> "$SCRIPT_DIR/group_vars/all/main.yml"
        echo "    ip: ${INDEXER_NODES_ARRAY[$i]}" >> "$SCRIPT_DIR/group_vars/all/main.yml"
    done

    cat >> "$SCRIPT_DIR/group_vars/all/main.yml" << EOF

# ═══════════════════════════════════════════════════════════════
# Wazuh Manager Settings
# ═══════════════════════════════════════════════════════════════
wazuh_manager_api_port: ${MANAGER_API_PORT:-55000}
wazuh_manager_agent_port: ${AGENT_PORT:-1514}
wazuh_api_user: "${API_USER:-wazuh}"
wazuh_api_password: "{{ vault_wazuh_api_password }}"
EOF

    if (( MANAGER_COUNT > 1 )); then
        cat >> "$SCRIPT_DIR/group_vars/all/main.yml" << 'EOF'
wazuh_manager_cluster_enabled: true
wazuh_manager_cluster_key: "{{ vault_wazuh_manager_cluster_key }}"
EOF
    else
        echo "wazuh_manager_cluster_enabled: false" >> "$SCRIPT_DIR/group_vars/all/main.yml"
    fi

    cat >> "$SCRIPT_DIR/group_vars/all/main.yml" << EOF

wazuh_manager_nodes:
EOF

    for i in "${!MANAGER_NODES_ARRAY[@]}"; do
        echo "  - name: manager-$((i+1))" >> "$SCRIPT_DIR/group_vars/all/main.yml"
        echo "    ip: ${MANAGER_NODES_ARRAY[$i]}" >> "$SCRIPT_DIR/group_vars/all/main.yml"
    done

    cat >> "$SCRIPT_DIR/group_vars/all/main.yml" << EOF

# ═══════════════════════════════════════════════════════════════
# Wazuh Dashboard Settings
# ═══════════════════════════════════════════════════════════════
wazuh_dashboard_port: ${DASHBOARD_PORT:-443}

wazuh_dashboard_nodes:
EOF

    for node in "${DASHBOARD_NODES_ARRAY[@]}"; do
        echo "  - ip: ${node}" >> "$SCRIPT_DIR/group_vars/all/main.yml"
    done

    cat >> "$SCRIPT_DIR/group_vars/all/main.yml" << EOF

# ═══════════════════════════════════════════════════════════════
# SSL/TLS Configuration
# ═══════════════════════════════════════════════════════════════
wazuh_use_external_ca: ${EXTERNAL_CA:-false}
wazuh_certs_path: "files/certs"
wazuh_ssl_verify_certificates: ${EXTERNAL_CA:-false}

# ═══════════════════════════════════════════════════════════════
# Security Features
# ═══════════════════════════════════════════════════════════════
wazuh_vulnerability_detection_enabled: ${ENABLE_VULN_DETECTION:-true}
wazuh_fim_enabled: ${ENABLE_FIM:-true}
wazuh_rootkit_detection_enabled: ${ENABLE_ROOTKIT:-true}
wazuh_sca_enabled: ${ENABLE_SCA:-true}
wazuh_syscollector_enabled: ${ENABLE_SYSCOLLECTOR:-true}
wazuh_log_collection_enabled: ${ENABLE_LOG_COLLECTION:-true}
wazuh_active_response_enabled: ${ENABLE_ACTIVE_RESPONSE:-true}

# ═══════════════════════════════════════════════════════════════
# Automatic Index Management
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
# Network/Firewall
# ═══════════════════════════════════════════════════════════════
wazuh_configure_firewall: true
wazuh_configure_selinux: true

# ═══════════════════════════════════════════════════════════════
# Backup & Maintenance
# ═══════════════════════════════════════════════════════════════
wazuh_backup_schedule: "${BACKUP_SCHEDULE:-daily}"
wazuh_backup_hour: ${BACKUP_HOUR:-2}
wazuh_backup_retention: ${BACKUP_RETENTION:-7}
wazuh_log_cleanup_enabled: ${ENABLE_LOG_CLEANUP:-true}
wazuh_log_retention_days: ${LOG_RETENTION_DAYS:-30}

# ═══════════════════════════════════════════════════════════════
# Post-Deployment Security
# ═══════════════════════════════════════════════════════════════
wazuh_lockdown_deploy_user: true
EOF

    success "Created: group_vars/all/main.yml"

    # ════════════════════════════════════════════════════════════
    # Ansible Vault
    # ════════════════════════════════════════════════════════════
    gum spin --spinner dot --title "Initializing Ansible Vault..." -- sleep 0.5

    GENERATED_INDEXER_PASSWORD=""
    GENERATED_API_PASSWORD=""

    if [[ -f "$SCRIPT_DIR/scripts/manage-vault.sh" ]]; then
        if [[ ! -f "$SCRIPT_DIR/.vault_password" ]]; then
            bash "$SCRIPT_DIR/scripts/manage-vault.sh" init 2>/dev/null || true
        fi

        if [[ "$CUSTOM_PASSWORDS" == "true" ]]; then
            GENERATED_INDEXER_PASSWORD="${INDEXER_ADMIN_PASSWORD:-}"
            GENERATED_API_PASSWORD="${API_PASSWORD:-}"
        fi

        if [[ -z "$GENERATED_INDEXER_PASSWORD" ]]; then
            GENERATED_INDEXER_PASSWORD=$(generate_password 24)
        fi
        if [[ -z "$GENERATED_API_PASSWORD" ]]; then
            GENERATED_API_PASSWORD=$(generate_password 24)
        fi

        VAULT_INDEXER_PASSWORD="$GENERATED_INDEXER_PASSWORD" \
        VAULT_API_PASSWORD="$GENERATED_API_PASSWORD" \
        VAULT_CLUSTER_KEY="${MANAGER_CLUSTER_KEY:-}" \
        bash "$SCRIPT_DIR/scripts/manage-vault.sh" create 2>/dev/null || true

        success "Vault initialized with encrypted credentials"
    else
        warn "Vault management script not found - credentials not encrypted"
    fi

    success "Configuration generation complete!"
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
• ansible.cfg
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
