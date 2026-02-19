#!/bin/bash

# Wazuh Ansible Deployment - TUI Setup Script (using gum)
# Beautiful terminal UI for configuring Wazuh deployment
#
# Requirements: gum >= 0.10 (https://github.com/charmbracelet/gum)
# Install: brew install gum  OR  go install github.com/charmbracelet/gum@latest
#
# Usage:
#   ./setup-tui.sh                    # Interactive TUI mode
#   ./setup-tui.sh --profile minimal  # Quick setup with profile
#   ./setup-tui.sh --check            # Validate gum installation
#   ./setup-tui.sh --help             # Show help

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ═══════════════════════════════════════════════════════════════
# Check for gum installation
# ═══════════════════════════════════════════════════════════════
GUM_MIN_VERSION="0.10.0"

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

# Version comparison: returns 0 if $1 >= $2
version_gte() {
    printf '%s\n%s\n' "$2" "$1" | sort -V -C
}

# Comprehensive gum validation
validate_gum() {
    local verbose="${1:-false}"
    local errors=0

    # Check installation
    if ! command -v gum &>/dev/null; then
        echo "✗ gum is not installed"
        echo ""
        echo "Install gum using one of these methods:"
        echo "  brew install gum                              # macOS/Linux (Homebrew)"
        echo "  sudo apt install gum                          # Debian/Ubuntu"
        echo "  sudo dnf install gum                          # Fedora"
        echo "  go install github.com/charmbracelet/gum@latest # Go"
        echo ""
        echo "Or use the classic setup script: ./setup.sh"
        return 1
    fi
    [[ "$verbose" == "true" ]] && echo "✓ gum is installed: $(command -v gum)"

    # Check version
    local gum_version
    gum_version=$(gum --version 2>/dev/null | head -1 | sed 's/^gum version //' | sed 's/^v//')
    if [[ -z "$gum_version" ]]; then
        echo "✗ Could not determine gum version"
        ((errors++))
    elif version_gte "$gum_version" "$GUM_MIN_VERSION"; then
        [[ "$verbose" == "true" ]] && echo "✓ gum version $gum_version >= $GUM_MIN_VERSION"
    else
        echo "✗ gum version $gum_version is below minimum $GUM_MIN_VERSION"
        echo "  Please upgrade: brew upgrade gum  OR  go install github.com/charmbracelet/gum@latest"
        ((errors++))
    fi

    # Test terminal capabilities
    if [[ -t 1 ]]; then
        [[ "$verbose" == "true" ]] && echo "✓ Running in interactive terminal"
    else
        echo "⚠ Not running in interactive terminal (some features may not work)"
    fi

    # Test gum commands work
    if gum style "test" >/dev/null 2>&1; then
        [[ "$verbose" == "true" ]] && echo "✓ gum style works"
    else
        echo "✗ gum style command failed"
        ((errors++))
    fi

    if echo "test" | gum choose --limit 1 >/dev/null 2>&1; then
        [[ "$verbose" == "true" ]] && echo "✓ gum choose works"
    else
        echo "✗ gum choose command failed"
        ((errors++))
    fi

    if gum input --value "test" >/dev/null 2>&1 </dev/null; then
        [[ "$verbose" == "true" ]] && echo "✓ gum input works"
    else
        echo "✗ gum input command failed"
        ((errors++))
    fi

    # Summary
    if [[ $errors -eq 0 ]]; then
        [[ "$verbose" == "true" ]] && echo ""
        echo "✓ All gum checks passed - ready for TUI setup"
        return 0
    else
        echo ""
        echo "✗ $errors check(s) failed"
        echo "  Consider using the classic setup script: ./setup.sh"
        return 1
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
source "$SCRIPT_DIR/lib/client-prep.sh" 2>/dev/null || true

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
# IMPORTANT: Error display goes to stderr so command substitution only captures the value.
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
            error "Invalid input. Please try again." >&2
            continue
        fi

        echo "$value"
        return 0
    done
}

# Multi-host input
# IMPORTANT: All display output goes to stderr so command substitution
# only captures the return value (the host list), not decorative text.
input_hosts() {
    local prompt="$1"
    local min_hosts="${2:-1}"

    info "$prompt" >&2
    info "Enter hostnames/IPs, one per line. Save when done." >&2
    echo "" >&2

    local hosts=""
    hosts=$(gum write --placeholder "192.168.1.10
192.168.1.11
..." --width 50 --height 6)

    # Convert newlines to spaces and filter to valid hostnames/IPs only
    hosts=$(echo "$hosts" | tr '\n' ' ' | xargs)

    # Sanitize: keep only entries that look like hostnames or IPs
    local clean_hosts=""
    for entry in $hosts; do
        # Match IPv4, IPv6, or valid hostname (alphanumeric, dots, hyphens, colons)
        if [[ "$entry" =~ ^[a-zA-Z0-9.:_-]+$ ]]; then
            clean_hosts="${clean_hosts:+$clean_hosts }$entry"
        else
            warn "Skipping invalid entry: $entry" >&2
        fi
    done
    hosts="$clean_hosts"

    if [[ -z "$hosts" ]] && (( min_hosts > 0 )); then
        error "At least $min_hosts host(s) required!" >&2
        return 1
    fi

    echo "$hosts"
}

# ═══════════════════════════════════════════════════════════════
# Profile Selection
# ═══════════════════════════════════════════════════════════════
select_profile() {
    # Display output goes to stderr so command substitution only captures the profile name
    header "Select Deployment Profile" >&2

    info "Choose a profile to get started quickly:" >&2
    echo "" >&2

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
        SLACK_ALERT_LEVEL=$(gum input --prompt "Minimum alert level (1-15): " --value "10")
    fi

    # MS Teams
    ENABLE_TEAMS="false"
    if gum confirm "Enable MS Teams notifications?"; then
        ENABLE_TEAMS="true"
        info "Create an Incoming Webhook in Teams: Channel → Connectors → Incoming Webhook"
        TEAMS_WEBHOOK_URL=$(gum input --prompt "Teams Webhook URL: ")
        TEAMS_ALERT_LEVEL=$(gum input --prompt "Minimum alert level (1-15): " --value "10")
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

configure_load_balancer() {
    section "Load Balancer Configuration"

    info "Angie LB distributes dashboard/agent/API traffic across multiple nodes."
    info "Enable for HA deployments or to front the dashboard with a company cert."
    echo ""

    ENABLE_LB="false"
    LB_NODE=""
    LB_ADDRESS=""
    LB_SSL_TERMINATION="false"
    LB_SSL_CERT_SRC=""
    LB_SSL_KEY_SRC=""
    LB_SSL_CERT_PATH="/etc/angie/certs/lb-fullchain.pem"
    LB_SSL_KEY_PATH="/etc/angie/certs/lb-key.pem"

    if gum confirm "Enable Angie load balancer?"; then
        ENABLE_LB="true"
        LB_NODE=$(gum input --prompt "Load balancer host IP/hostname: " --placeholder "192.168.1.5")
        LB_ADDRESS="$LB_NODE"

        echo ""
        info "SSL Termination: company cert on LB (browsers see it), LB re-encrypts to dashboard."
        if gum confirm "Enable SSL termination on LB?"; then
            LB_SSL_TERMINATION="true"
            local lb_cert_method
            lb_cert_method=$(gum choose \
                --header "Certificate Supply Method" \
                "A  │ Copy cert/key from Ansible controller to LB" \
                "B  │ Cert/key already on LB host (Let's Encrypt, etc.)")
            lb_cert_method=$(echo "$lb_cert_method" | cut -d'│' -f1 | xargs)

            if [[ "${lb_cert_method,,}" == "a"* ]]; then
                LB_SSL_CERT_SRC=$(gum input --prompt "Fullchain PEM on controller: " --value "files/certs/lb/lb-fullchain.pem")
                LB_SSL_KEY_SRC=$(gum input --prompt "Key PEM on controller: " --value "files/certs/lb/lb-key.pem")
                LB_SSL_CERT_PATH="/etc/angie/certs/lb-fullchain.pem"
                LB_SSL_KEY_PATH="/etc/angie/certs/lb-key.pem"
            else
                LB_SSL_CERT_SRC=""
                LB_SSL_KEY_SRC=""
                LB_SSL_CERT_PATH=$(gum input --prompt "Fullchain PEM on LB host: " --value "/etc/angie/certs/lb-fullchain.pem")
                LB_SSL_KEY_PATH=$(gum input --prompt "Key PEM on LB host: " --value "/etc/angie/certs/lb-key.pem")
            fi
        fi
        success "Load balancer configured: ${LB_NODE}"
    else
        info "Load balancer skipped"
    fi
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
EOF

    # Add SSH private key path if key was generated
    if [[ "${GENERATE_SSH_KEY:-false}" == "true" ]]; then
        echo "    ansible_ssh_private_key_file: ${ANSIBLE_SSH_KEY:-keys/wazuh_ansible_key}" >> "$SCRIPT_DIR/inventory/hosts.yml"
    fi

    cat >> "$SCRIPT_DIR/inventory/hosts.yml" << EOF

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
        if [[ $i -eq 0 ]]; then
            echo "          manager_node_type: master" >> "$SCRIPT_DIR/inventory/hosts.yml"
        else
            echo "          manager_node_type: worker" >> "$SCRIPT_DIR/inventory/hosts.yml"
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

    if [[ "${ENABLE_LB:-false}" == "true" ]] && [[ -n "${LB_NODE:-}" ]]; then
        cat >> "$SCRIPT_DIR/inventory/hosts.yml" << EOF

    wazuh_lb:
      hosts:
        ${LB_NODE}:
EOF
    fi

    cat >> "$SCRIPT_DIR/inventory/hosts.yml" << 'EOF'

    # Local deployment host
    local:
      hosts:
        localhost:
          ansible_connection: local
          ansible_user: "{{ lookup('env', 'USER') }}"
          ansible_become: false
EOF

    success "Created: inventory/hosts.yml"

    # ════════════════════════════════════════════════════════════
    # SSH Key Generation
    # ════════════════════════════════════════════════════════════
    if [[ "${GENERATE_SSH_KEY:-false}" == "true" ]]; then
        gum spin --spinner dot --title "Generating SSH key pair..." -- sleep 0.5

        mkdir -p "$SCRIPT_DIR/keys"
        if [[ ! -f "$SCRIPT_DIR/keys/wazuh_ansible_key" ]]; then
            ssh-keygen -t ed25519 -f "$SCRIPT_DIR/keys/wazuh_ansible_key" -N "" -C "wazuh-ansible-deploy" >/dev/null 2>&1
            chmod 600 "$SCRIPT_DIR/keys/wazuh_ansible_key"
            chmod 644 "$SCRIPT_DIR/keys/wazuh_ansible_key.pub"
            success "Generated: keys/wazuh_ansible_key"
        else
            success "SSH key already exists: keys/wazuh_ansible_key"
        fi
    fi

    # ════════════════════════════════════════════════════════════
    # inventory/bootstrap.yml (for initial host preparation)
    # ════════════════════════════════════════════════════════════
    if [[ "$SELECTED_PROFILE" != "minimal" ]]; then
        gum spin --spinner dot --title "Creating bootstrap inventory..." -- sleep 0.5

        cat > "$SCRIPT_DIR/inventory/bootstrap.yml" << EOF
---
# Bootstrap Inventory - For initial setup ONLY
# Connects as ${INITIAL_SSH_USER:-root} to create the ${ANSIBLE_USER} user
# After bootstrap, use hosts.yml for all operations
all:
  vars:
    ansible_user: ${INITIAL_SSH_USER:-root}
    ansible_port: ${ANSIBLE_SSH_PORT:-22}
    ansible_become: ${USE_BECOME:-true}
EOF

        # Add SSH password if provided
        if [[ -n "${DEFAULT_SSH_PASS:-}" ]]; then
            echo "    ansible_ssh_pass: \"{{ vault_ansible_connection_password }}\"" >> "$SCRIPT_DIR/inventory/bootstrap.yml"
        fi

        cat >> "$SCRIPT_DIR/inventory/bootstrap.yml" << EOF

  children:
    wazuh_indexers:
      hosts:
EOF

        for i in "${!INDEXER_NODES_ARRAY[@]}"; do
            local node="${INDEXER_NODES_ARRAY[$i]}"
            echo "        ${node}:" >> "$SCRIPT_DIR/inventory/bootstrap.yml"
            echo "          indexer_node_name: indexer-$((i+1))" >> "$SCRIPT_DIR/inventory/bootstrap.yml"
            if [[ $i -eq 0 ]]; then
                echo "          indexer_cluster_initial_master: true" >> "$SCRIPT_DIR/inventory/bootstrap.yml"
            fi
        done

        cat >> "$SCRIPT_DIR/inventory/bootstrap.yml" << EOF

    wazuh_managers:
      hosts:
EOF

        for i in "${!MANAGER_NODES_ARRAY[@]}"; do
            local node="${MANAGER_NODES_ARRAY[$i]}"
            echo "        ${node}:" >> "$SCRIPT_DIR/inventory/bootstrap.yml"
            echo "          manager_node_name: manager-$((i+1))" >> "$SCRIPT_DIR/inventory/bootstrap.yml"
            if [[ $i -eq 0 ]]; then
                echo "          manager_node_type: master" >> "$SCRIPT_DIR/inventory/bootstrap.yml"
            else
                echo "          manager_node_type: worker" >> "$SCRIPT_DIR/inventory/bootstrap.yml"
            fi
        done

        cat >> "$SCRIPT_DIR/inventory/bootstrap.yml" << EOF

    wazuh_dashboards:
      hosts:
EOF

        for node in "${DASHBOARD_NODES_ARRAY[@]}"; do
            echo "        ${node}:" >> "$SCRIPT_DIR/inventory/bootstrap.yml"
        done

        if [[ "$DEPLOY_AGENTS" == "true" ]] && [[ -n "${AGENT_NODES:-}" ]]; then
            cat >> "$SCRIPT_DIR/inventory/bootstrap.yml" << EOF

    wazuh_agents:
      hosts:
EOF
            for node in "${AGENT_NODES_ARRAY[@]}"; do
                echo "        ${node}:" >> "$SCRIPT_DIR/inventory/bootstrap.yml"
            done
        fi

        if [[ "${ENABLE_LB:-false}" == "true" ]] && [[ -n "${LB_NODE:-}" ]]; then
            cat >> "$SCRIPT_DIR/inventory/bootstrap.yml" << EOF

    wazuh_lb:
      hosts:
        ${LB_NODE}:
EOF
        fi

        cat >> "$SCRIPT_DIR/inventory/bootstrap.yml" << 'EOF'

    # Local deployment host
    local:
      hosts:
        localhost:
          ansible_connection: local
          ansible_user: "{{ lookup('env', 'USER') }}"
          ansible_become: false
EOF

        success "Created: inventory/bootstrap.yml"
    fi

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
wazuh_ansible_user: "${ANSIBLE_USER:-wazuh-deploy}"

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

# Agent enrollment password loaded from Ansible Vault
wazuh_agent_enrollment_password: "{{ vault_wazuh_agent_enrollment_password }}"
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
wazuh_indexer_certs_path: /etc/wazuh-indexer/certs
wazuh_manager_certs_path: /var/ossec/etc/certs
wazuh_dashboard_certs_path: /etc/wazuh-dashboard/certs
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
# Network/Firewall
# ═══════════════════════════════════════════════════════════════
wazuh_configure_firewall: true
wazuh_configure_selinux: true
wazuh_repo_gpg_key: "https://packages.wazuh.com/key/GPG-KEY-WAZUH"
wazuh_repo_url_apt: "https://packages.wazuh.com/4.x/apt/"
wazuh_repo_url_yum: "https://packages.wazuh.com/4.x/yum/"

# ═══════════════════════════════════════════════════════════════
# Backup & Maintenance
# ═══════════════════════════════════════════════════════════════
wazuh_backup_schedule: "${BACKUP_SCHEDULE:-daily}"
wazuh_backup_hour: ${BACKUP_HOUR:-2}
wazuh_backup_day: ${BACKUP_DAY:-0}
wazuh_backup_retention: ${BACKUP_RETENTION:-7}
wazuh_log_cleanup_enabled: ${ENABLE_LOG_CLEANUP:-true}
wazuh_log_retention_days: ${LOG_RETENTION_DAYS:-30}
wazuh_log_cleanup_schedule: "daily"

# ═══════════════════════════════════════════════════════════════
# Bootstrap Settings (used by --tags bootstrap)
# ═══════════════════════════════════════════════════════════════
wazuh_bootstrap_user: "${INITIAL_SSH_USER:-root}"

# ═══════════════════════════════════════════════════════════════
# Post-Deployment Security
# ═══════════════════════════════════════════════════════════════
wazuh_lockdown_deploy_user: true

# ═══════════════════════════════════════════════════════════════
# Log Rotation
# ═══════════════════════════════════════════════════════════════
wazuh_log_rotation_enabled: true
wazuh_log_rotation_keep_days: 30
wazuh_log_rotation_max_size: "100M"
wazuh_log_rotation_compress: true
EOF

    # Add email alerts configuration if enabled
    if [[ "${ENABLE_EMAIL_ALERTS:-false}" == "true" ]]; then
        cat >> "$SCRIPT_DIR/group_vars/all/main.yml" << EOF

# ═══════════════════════════════════════════════════════════════
# Email Alerts Configuration
# ═══════════════════════════════════════════════════════════════
wazuh_email_notification_enabled: true
wazuh_email_smtp_server: "${EMAIL_SMTP_SERVER}"
wazuh_email_from: "${EMAIL_FROM}"
wazuh_email_to: "${EMAIL_TO}"
wazuh_email_alert_level: ${EMAIL_ALERT_LEVEL:-12}
EOF
    else
        cat >> "$SCRIPT_DIR/group_vars/all/main.yml" << 'EOF'

# Email alerts disabled
wazuh_email_notification_enabled: false
EOF
    fi

    # Add syslog output configuration if enabled
    if [[ "${ENABLE_SYSLOG_OUTPUT:-false}" == "true" ]]; then
        cat >> "$SCRIPT_DIR/group_vars/all/main.yml" << EOF

# ═══════════════════════════════════════════════════════════════
# Syslog Output Configuration
# ═══════════════════════════════════════════════════════════════
wazuh_syslog_output_enabled: true
wazuh_syslog_output_server: "${SYSLOG_SERVER}"
wazuh_syslog_output_port: ${SYSLOG_PORT:-514}
wazuh_syslog_output_format: "${SYSLOG_FORMAT:-json}"
EOF
    else
        cat >> "$SCRIPT_DIR/group_vars/all/main.yml" << 'EOF'

# Syslog output disabled
wazuh_syslog_output_enabled: false
EOF
    fi

    # Add integrations configuration
    local has_integrations=false
    if [[ "${ENABLE_SLACK:-false}" == "true" ]] || [[ "${ENABLE_TEAMS:-false}" == "true" ]] || \
       [[ "${ENABLE_VIRUSTOTAL:-false}" == "true" ]]; then
        has_integrations=true
        cat >> "$SCRIPT_DIR/group_vars/all/main.yml" << 'EOF'

# ═══════════════════════════════════════════════════════════════
# Integrations
# ═══════════════════════════════════════════════════════════════
wazuh_integrations:
EOF
    fi

    if [[ "${ENABLE_SLACK:-false}" == "true" ]]; then
        cat >> "$SCRIPT_DIR/group_vars/all/main.yml" << 'EOF'
  - name: slack
    # SECURITY: webhook URL encrypted in group_vars/all/vault.yml
    hook_url: "{{ vault_slack_webhook_url }}"
EOF
        cat >> "$SCRIPT_DIR/group_vars/all/main.yml" << EOF
    level: ${SLACK_ALERT_LEVEL:-10}
    alert_format: json
EOF
    fi

    if [[ "${ENABLE_TEAMS:-false}" == "true" ]]; then
        cat >> "$SCRIPT_DIR/group_vars/all/main.yml" << 'EOF'
  - name: ms-teams
    # SECURITY: webhook URL encrypted in group_vars/all/vault.yml
    hook_url: "{{ vault_teams_webhook_url }}"
EOF
        cat >> "$SCRIPT_DIR/group_vars/all/main.yml" << EOF
    level: ${TEAMS_ALERT_LEVEL:-10}
    alert_format: json
EOF
    fi

    if [[ "${ENABLE_VIRUSTOTAL:-false}" == "true" ]]; then
        cat >> "$SCRIPT_DIR/group_vars/all/main.yml" << 'EOF'
  - name: virustotal
    # SECURITY: API key encrypted in group_vars/all/vault.yml
    api_key: "{{ vault_virustotal_api_key }}"
    group: "syscheck"
    alert_format: json
EOF
    fi

    if [[ "$has_integrations" == "false" ]]; then
        cat >> "$SCRIPT_DIR/group_vars/all/main.yml" << 'EOF'

# No integrations configured
wazuh_integrations: []
EOF
    fi

    # Add LB configuration block
    if [[ "${ENABLE_LB:-false}" == "true" ]]; then
        cat >> "$SCRIPT_DIR/group_vars/all/main.yml" << EOF

# ═══════════════════════════════════════════════════════════════
# Load Balancer (Angie)
# ═══════════════════════════════════════════════════════════════
wazuh_lb_enabled: true
wazuh_lb_address: "${LB_ADDRESS}"
wazuh_lb_ssl_termination_enabled: ${LB_SSL_TERMINATION}
EOF
        if [[ "${LB_SSL_TERMINATION:-false}" == "true" ]]; then
            cat >> "$SCRIPT_DIR/group_vars/all/main.yml" << EOF
wazuh_lb_ssl_cert_src: "${LB_SSL_CERT_SRC}"
wazuh_lb_ssl_key_src: "${LB_SSL_KEY_SRC}"
wazuh_lb_ssl_cert_path: "${LB_SSL_CERT_PATH}"
wazuh_lb_ssl_key_path: "${LB_SSL_KEY_PATH}"
EOF
        fi
    else
        cat >> "$SCRIPT_DIR/group_vars/all/main.yml" << 'EOF'

# ═══════════════════════════════════════════════════════════════
# Load Balancer (Angie) - disabled
# ═══════════════════════════════════════════════════════════════
# Set wazuh_lb_enabled: true and configure wazuh_lb_address to enable
wazuh_lb_enabled: false
# wazuh_lb_address: "192.168.1.5"
# wazuh_lb_ssl_termination_enabled: false
EOF
    fi

    success "Created: group_vars/all/main.yml"

    # ════════════════════════════════════════════════════════════
    # Client Preparation Package
    # ════════════════════════════════════════════════════════════
    if [[ "${CREATE_PREP_PACKAGE:-false}" == "true" ]]; then
        gum spin --spinner dot --title "Creating client preparation package..." -- sleep 0.3

        # Wire up log callbacks for TUI
        _prep_info()    { info "$@"; }
        _prep_success() { success "$@"; }
        _prep_warn()    { warn "$@"; }

        create_client_prep_package "$SCRIPT_DIR" "${ANSIBLE_SSH_KEY:-$SCRIPT_DIR/keys/wazuh_ansible_key}" "${ANSIBLE_USER:-wazuh-deploy}"
    fi

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

        GENERATED_ENROLLMENT_PASSWORD=$(generate_password 24)

        VAULT_INDEXER_PASSWORD="$GENERATED_INDEXER_PASSWORD" \
        VAULT_API_PASSWORD="$GENERATED_API_PASSWORD" \
        VAULT_ENROLLMENT_PASSWORD="$GENERATED_ENROLLMENT_PASSWORD" \
        VAULT_CLUSTER_KEY="${MANAGER_CLUSTER_KEY:-}" \
        VAULT_CONNECTION_PASSWORD="${DEFAULT_SSH_PASS:-}" \
        VAULT_ANSIBLE_USER="${ANSIBLE_USER:-wazuh-deploy}" \
        VAULT_SLACK_WEBHOOK_URL="${SLACK_WEBHOOK_URL:-}" \
        VAULT_VIRUSTOTAL_API_KEY="${VIRUSTOTAL_API_KEY:-}" \
        VAULT_TEAMS_WEBHOOK_URL="${TEAMS_WEBHOOK_URL:-}" \
        bash "$SCRIPT_DIR/scripts/manage-vault.sh" create 2>/dev/null || true

        success "Vault initialized with encrypted credentials"
    else
        warn "Vault management script not found - credentials not encrypted"
    fi

    # ════════════════════════════════════════════════════════════
    # Certificate Generation
    # ════════════════════════════════════════════════════════════
    section "SSL/TLS Certificates"

    if [[ "${EXTERNAL_CA:-false}" == "true" ]]; then
        info "External CA mode enabled"
        mkdir -p "${SCRIPT_DIR}/files/certs"

        if [[ -f "${SCRIPT_DIR}/files/certs/root-ca.pem" ]]; then
            success "Found root-ca.pem"
        else
            warn "External CA certificates not found in files/certs/"
            info "Please place your certificates before running deployment"
            info "Required: root-ca.pem, admin.pem, admin-key.pem, and node certificates"
        fi
    else
        if [[ -f "${SCRIPT_DIR}/generate-certs.sh" ]]; then
            if [[ -f "${SCRIPT_DIR}/files/certs/root-ca.pem" ]]; then
                warn "Certificates already exist in files/certs/"
                if gum confirm "Regenerate certificates?"; then
                    gum spin --spinner dot --title "Generating certificates..." -- bash "${SCRIPT_DIR}/generate-certs.sh" 2>/dev/null
                    success "Certificates regenerated"
                else
                    info "Using existing certificates"
                fi
            else
                gum spin --spinner dot --title "Generating self-signed certificates..." -- bash "${SCRIPT_DIR}/generate-certs.sh" 2>/dev/null
                success "Certificates generated in files/certs/"
            fi
        else
            warn "Certificate generation script not found: generate-certs.sh"
            info "You will need to generate certificates manually"
        fi
    fi

    success "Configuration generation complete!"
}

# ═══════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════

# Colors for summary output (matching setup.sh)
BLUE='\033[0;34m'
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

show_summary() {
    # ─── Configuration Summary ───────────────────────────────────
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  Configuration Summary${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}\n"

    echo -e "${CYAN}Wazuh Version:${NC} ${WAZUH_VERSION}"
    echo -e "${CYAN}Environment:${NC} ${ENVIRONMENT}"
    echo
    echo -e "${GREEN}Indexer Nodes (${INDEXER_COUNT}):${NC}"
    for node in "${INDEXER_NODES_ARRAY[@]}"; do
        echo "  - $node"
    done
    echo
    echo -e "${GREEN}Manager Nodes (${MANAGER_COUNT}):${NC}"
    for node in "${MANAGER_NODES_ARRAY[@]}"; do
        echo "  - $node"
    done
    echo
    echo -e "${GREEN}Dashboard Nodes (${#DASHBOARD_NODES_ARRAY[@]}):${NC}"
    for node in "${DASHBOARD_NODES_ARRAY[@]}"; do
        echo "  - $node"
    done

    if [[ "${DEPLOY_AGENTS:-false}" == "true" ]] && [[ -n "${AGENT_NODES:-}" ]]; then
        echo
        echo -e "${GREEN}Agent Nodes (${#AGENT_NODES_ARRAY[@]}):${NC}"
        for node in "${AGENT_NODES_ARRAY[@]}"; do
            echo "  - $node"
        done
    fi

    if [[ "${ENABLE_LB:-false}" == "true" ]]; then
        echo
        echo -e "${GREEN}Load Balancer (Angie):${NC}"
        echo "  - Host: ${LB_NODE}"
        if [[ "${LB_SSL_TERMINATION:-false}" == "true" ]]; then
            echo "  - Dashboard: SSL termination (company cert on LB)"
        else
            echo "  - Dashboard: TCP passthrough (TLS end-to-end)"
        fi
        echo "  - Agent/API ports: TCP passthrough"
    fi

    echo
    echo -e "${CYAN}SSH Configuration:${NC}"
    if [[ "${GENERATE_SSH_KEY:-false}" == "true" ]]; then
        echo "  - Initial SSH user: ${INITIAL_SSH_USER:-root}"
        echo "  - Ansible deployment user: ${ANSIBLE_USER:-wazuh-deploy} (will be created)"
        echo "  - SSH key: ${ANSIBLE_SSH_KEY:-keys/wazuh_ansible_key} (will be generated)"
    else
        echo "  - SSH user: ${ANSIBLE_USER:-$(whoami)}"
        echo "  - SSH key: ${ANSIBLE_SSH_KEY:-~/.ssh/id_rsa}"
    fi
    echo "  - SSH port: ${ANSIBLE_SSH_PORT:-22}"

    echo
    echo -e "${CYAN}Security:${NC}"
    echo "  - Ansible Vault: Enabled (encrypted credentials)"
    echo "  - Vault password: .vault_password"
    echo "  - Encrypted vault: group_vars/all/vault.yml"
    if [[ "${EXTERNAL_CA:-false}" == "true" ]]; then
        echo "  - Certificates: External CA (user-provided)"
    else
        echo "  - Certificates: Self-signed (auto-generated)"
    fi
    if [[ "${CUSTOM_PASSWORDS:-false}" == "true" ]]; then
        echo "  - Passwords: Custom (user-provided)"
    else
        echo "  - Passwords: Auto-generated"
    fi

    echo
    echo -e "${CYAN}Security Features Enabled:${NC}"
    [[ "${ENABLE_VULN_DETECTION:-true}" == "true" ]] && echo "  - Vulnerability Detection"
    [[ "${ENABLE_FIM:-true}" == "true" ]] && echo "  - File Integrity Monitoring"
    [[ "${ENABLE_ROOTKIT:-true}" == "true" ]] && echo "  - Rootkit Detection"
    [[ "${ENABLE_SCA:-true}" == "true" ]] && echo "  - Security Configuration Assessment (SCA)"
    [[ "${ENABLE_SYSCOLLECTOR:-true}" == "true" ]] && echo "  - System Inventory (Syscollector)"
    [[ "${ENABLE_LOG_COLLECTION:-true}" == "true" ]] && echo "  - Log Collection"
    [[ "${ENABLE_ACTIVE_RESPONSE:-false}" == "true" ]] && echo "  - Active Response"

    echo
    echo -e "${CYAN}Alerting & Integrations:${NC}"
    if [[ "${ENABLE_EMAIL_ALERTS:-false}" == "true" ]]; then
        echo "  - Email Alerts: ${EMAIL_TO} (via ${EMAIL_SMTP_SERVER})"
    fi
    if [[ "${ENABLE_SYSLOG_OUTPUT:-false}" == "true" ]]; then
        echo "  - Syslog Output: ${SYSLOG_SERVER}:${SYSLOG_PORT:-514} (${SYSLOG_FORMAT:-json})"
    fi
    if [[ "${ENABLE_SLACK:-false}" == "true" ]]; then
        echo "  - Slack Notifications (level >= ${SLACK_ALERT_LEVEL:-10})"
    fi
    if [[ "${ENABLE_TEAMS:-false}" == "true" ]]; then
        echo "  - MS Teams Notifications (level >= ${TEAMS_ALERT_LEVEL:-10})"
    fi
    if [[ "${ENABLE_VIRUSTOTAL:-false}" == "true" ]]; then
        echo "  - VirusTotal Integration"
    fi
    if [[ "${ENABLE_EMAIL_ALERTS:-false}" != "true" ]] && [[ "${ENABLE_SYSLOG_OUTPUT:-false}" != "true" ]] && \
       [[ "${ENABLE_SLACK:-false}" != "true" ]] && [[ "${ENABLE_TEAMS:-false}" != "true" ]] && \
       [[ "${ENABLE_VIRUSTOTAL:-false}" != "true" ]]; then
        echo "  - None configured (alerts will only appear in Wazuh Dashboard)"
    fi

    echo
    echo -e "${CYAN}Backup & Maintenance:${NC}"
    case "${BACKUP_SCHEDULE:-daily}" in
        daily)
            echo "  - Automated Backups: Daily at ${BACKUP_HOUR:-2}:00, keep ${BACKUP_RETENTION:-7} backups"
            ;;
        weekly)
            local days=("Sunday" "Monday" "Tuesday" "Wednesday" "Thursday" "Friday" "Saturday")
            echo "  - Automated Backups: Weekly on ${days[${BACKUP_DAY:-0}]} at ${BACKUP_HOUR:-2}:00, keep ${BACKUP_RETENTION:-7} backups"
            ;;
        disabled)
            echo "  - Automated Backups: Disabled (manual only)"
            ;;
    esac
    if [[ "${ENABLE_LOG_CLEANUP:-true}" == "true" ]]; then
        echo "  - Log Cleanup: daily, keep ${LOG_RETENTION_DAYS:-30} days"
    else
        echo "  - Log Cleanup: Disabled"
    fi

    # ─── Next Steps ──────────────────────────────────────────────
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  Next Steps${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}\n"

    echo -e "1. Review the generated configuration files:"
    echo -e "   ${CYAN}inventory/hosts.yml${NC}       - Main inventory (SSH key auth)"
    echo -e "   ${CYAN}inventory/bootstrap.yml${NC}   - Bootstrap inventory (password auth)"
    echo -e "   ${CYAN}group_vars/all/main.yml${NC}   - Variables file"
    echo -e "   ${CYAN}group_vars/all/vault.yml${NC}  - Encrypted credentials"
    echo -e "   ${CYAN}ansible.cfg${NC}            - Ansible configuration"
    echo -e "   ${CYAN}.vault_password${NC}        - Vault encryption key (KEEP SECURE!)"
    echo

    if [[ "${CREATE_PREP_PACKAGE:-false}" == "true" ]]; then
        echo -e "2. ${GREEN}Prepare target machines${NC} (choose one method):"
        echo
        echo -e "   ${YELLOW}Method A: Copy and run the preparation folder${NC}"
        echo -e "   scp -r client-prep/ root@TARGET_HOST:/tmp/"
        echo -e "   ssh root@TARGET_HOST 'cd /tmp/client-prep && sudo ./install.sh'"
        echo
        echo -e "   ${YELLOW}Method B: Use the self-extracting script${NC}"
        echo -e "   scp wazuh-client-prep.sh root@TARGET_HOST:/tmp/"
        echo -e "   ssh root@TARGET_HOST 'sudo bash /tmp/wazuh-client-prep.sh'"
        echo
        echo -e "   ${YELLOW}Method C: Use the deployment script for multiple hosts${NC}"
        echo -e "   ./scripts/deploy-prep.sh -f hosts.txt"
        echo -e "   ./scripts/deploy-prep.sh 192.168.1.10 192.168.1.11 192.168.1.12"
        echo
        echo -e "3. Test connectivity to your hosts:"
    else
        echo -e "2. Test connectivity to your hosts:"
    fi
    echo -e "   ${YELLOW}ansible all -m ping -i inventory/bootstrap.yml --vault-password-file .vault_password${NC}"
    echo

    if [[ "${CREATE_PREP_PACKAGE:-false}" == "true" ]]; then
        echo -e "4. Bootstrap + deploy (one command):"
    else
        echo -e "3. Bootstrap + deploy (one command):"
    fi
    echo -e "   ${YELLOW}ansible-playbook site.yml --tags bootstrap,all${NC}"
    echo
    echo -e "   This first connects as '${CYAN}${INITIAL_SSH_USER:-root}${NC}' to create the '${CYAN}${ANSIBLE_USER:-wazuh-deploy}${NC}' user"
    echo -e "   with SSH key auth and passwordless sudo, then runs the full deployment."
    echo
    echo -e "   Subsequent deployments (no bootstrap needed):"
    echo -e "   ${YELLOW}ansible-playbook site.yml${NC}"
    echo
    echo -e "   Or deploy components individually:"
    echo -e "   ${YELLOW}ansible-playbook playbooks/wazuh-indexer.yml --vault-password-file .vault_password${NC}"
    echo -e "   ${YELLOW}ansible-playbook playbooks/wazuh-manager.yml --vault-password-file .vault_password${NC}"
    echo -e "   ${YELLOW}ansible-playbook playbooks/wazuh-dashboard.yml --vault-password-file .vault_password${NC}"
    echo -e "   ${YELLOW}ansible-playbook playbooks/wazuh-agents.yml --vault-password-file .vault_password${NC}"
    echo

    if [[ "${CREATE_PREP_PACKAGE:-false}" == "true" ]]; then
        echo -e "6. After deployment, view your credentials:"
    else
        echo -e "5. After deployment, view your credentials:"
    fi
    echo -e "   ${YELLOW}./scripts/manage-vault.sh view${NC}"
    echo

    if [[ "${CREATE_PREP_PACKAGE:-false}" == "true" ]]; then
        echo -e "7. Certificate management:"
    else
        echo -e "6. Certificate management:"
    fi
    echo -e "   ${YELLOW}ansible-playbook playbooks/certificate-management.yml --tags check-expiry${NC}"
    echo -e "   ${YELLOW}ansible-playbook playbooks/certificate-management.yml --tags rotate${NC}"
    echo

    # ─── SSH Key Information ─────────────────────────────────────
    if [[ "${GENERATE_SSH_KEY:-false}" == "true" ]]; then
        echo -e "\n${BLUE}═══════════════════════════════════════════════════════════════${NC}"
        echo -e "${CYAN}  SSH Key Information${NC}"
        echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}\n"
        echo -e "SSH keys have been generated for Ansible deployment:"
        echo -e "  Private key: ${CYAN}${ANSIBLE_SSH_KEY:-keys/wazuh_ansible_key}${NC}"
        echo -e "  Public key:  ${CYAN}${ANSIBLE_SSH_KEY:-keys/wazuh_ansible_key}.pub${NC}"
        echo
        echo -e "${YELLOW}Keep the private key secure! It provides access to all managed hosts.${NC}"
        echo
    fi

    # ─── Credential Management ───────────────────────────────────
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  Credential Management${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}\n"
    echo -e "Manage encrypted credentials with:"
    echo -e "  ${YELLOW}./scripts/manage-vault.sh view${NC}    - View current credentials"
    echo -e "  ${YELLOW}./scripts/manage-vault.sh edit${NC}    - Edit credentials"
    echo -e "  ${YELLOW}./scripts/manage-vault.sh rotate${NC}  - Rotate all credentials"
    echo -e "  ${YELLOW}./scripts/manage-vault.sh rekey${NC}   - Change vault password"
    echo

    echo -e "${YELLOW}⚠ SECURITY REMINDERS:${NC}"
    echo -e "  - Back up ${CYAN}.vault_password${NC} securely (required to decrypt credentials)"
    echo -e "  - Keep ${CYAN}keys/wazuh_ansible_key${NC} private (provides host access)"
    echo

    # ─── Vault Password ───────────────────────────────────────────
    if [[ -f "$SCRIPT_DIR/.vault_password" ]]; then
        echo -e "\n${RED}════════════════════════════════════════════════════════════════${NC}"
        echo -e "${RED}  ANSIBLE VAULT PASSWORD - SAVE THIS NOW!${NC}"
        echo -e "${RED}════════════════════════════════════════════════════════════════${NC}"
        echo
        echo -e "  ${YELLOW}Vault Password:${NC} ${CYAN}$(cat "$SCRIPT_DIR/.vault_password")${NC}"
        echo
        echo -e "${RED}════════════════════════════════════════════════════════════════${NC}"
        echo -e "${YELLOW}⚠ WARNING: You will need this password to:${NC}"
        echo -e "  - Deploy or redeploy the Wazuh cluster"
        echo -e "  - View or edit encrypted credentials"
        echo -e "  - Make any changes that require credential access"
        echo
        echo -e "${YELLOW}⚠ Store this password securely (password manager, secure vault)${NC}"
        echo -e "${YELLOW}⚠ The .vault_password file will be needed on this machine${NC}"
        echo -e "${RED}════════════════════════════════════════════════════════════════${NC}"
        echo
    fi

    # ─── Wazuh Admin Credentials ─────────────────────────────────
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  WAZUH ADMIN CREDENTIALS${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}\n"
    echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  SAVE THESE CREDENTIALS - THEY ARE STORED IN THE VAULT${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
    echo
    echo -e "  ${CYAN}Wazuh Dashboard / Indexer Admin:${NC}"
    echo -e "    Username: ${YELLOW}${INDEXER_ADMIN_USER:-admin}${NC}"
    echo -e "    Password: ${YELLOW}${GENERATED_INDEXER_PASSWORD}${NC}"
    echo
    echo -e "  ${CYAN}Wazuh API:${NC}"
    echo -e "    Username: ${YELLOW}${API_USER:-wazuh}${NC}"
    echo -e "    Password: ${YELLOW}${GENERATED_API_PASSWORD}${NC}"
    echo
    echo -e "  ${CYAN}Dashboard URL:${NC} https://${DASHBOARD_NODES_ARRAY[0]}:${DASHBOARD_PORT:-443}"
    echo -e "  ${CYAN}API URL:${NC} https://${MANAGER_NODES_ARRAY[0]}:${MANAGER_API_PORT:-55000}"
    echo
    echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}⚠ These credentials are encrypted in the vault.${NC}"
    echo -e "${YELLOW}⚠ Use './scripts/manage-vault.sh view' to see them later.${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
    echo

    echo -e "${GREEN}✓ Setup complete!${NC}"
}

# ═══════════════════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════════════════
main() {
    # Parse arguments first (before gum check, so --check can run without gum)
    SELECTED_PROFILE=""
    local do_check="false"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --profile|-p)
                SELECTED_PROFILE="$2"
                shift 2
                ;;
            --check|-c)
                do_check="true"
                shift
                ;;
            --help|-h)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --profile, -p PROFILE   Set deployment profile (minimal|production|custom)"
                echo "  --check, -c             Validate gum installation and exit"
                echo "  --help, -h              Show this help message"
                echo ""
                echo "Examples:"
                echo "  $0                      # Interactive TUI mode"
                echo "  $0 --profile minimal    # Quick setup with minimal profile"
                echo "  $0 --check              # Verify gum is properly installed"
                exit 0
                ;;
            *)
                shift
                ;;
        esac
    done

    # Handle --check flag
    if [[ "$do_check" == "true" ]]; then
        echo "Validating gum installation..."
        echo ""
        if validate_gum true; then
            exit 0
        else
            exit 1
        fi
    fi

    check_gum

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
        configure_load_balancer
    else
        # Minimal defaults
        CUSTOM_PASSWORDS="false"
        API_USER="wazuh"
        INDEXER_ADMIN_USER="admin"
        USE_SELF_SIGNED_CERTS="true"
        GENERATE_CERTS="true"
        EXTERNAL_CA="false"
        GENERATE_SSH_KEY="false"
        ANSIBLE_USER="$(whoami)"
        ANSIBLE_SSH_PORT="22"
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
        ENABLE_TEAMS="false"
        TEAMS_WEBHOOK_URL=""
        TEAMS_ALERT_LEVEL="10"
        ENABLE_VIRUSTOTAL="false"
        ENABLE_LB="false"
        LB_NODE=""
        LB_ADDRESS=""
        LB_SSL_TERMINATION="false"
        LB_SSL_CERT_SRC=""
        LB_SSL_KEY_SRC=""
        LB_SSL_CERT_PATH="/etc/angie/certs/lb-fullchain.pem"
        LB_SSL_KEY_PATH="/etc/angie/certs/lb-key.pem"
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
