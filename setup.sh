#!/bin/bash

# Wazuh Ansible Deployment - Interactive Setup Script
# This script configures Ansible variables for Wazuh deployment
#
# Security features:
# - No use of eval for variable assignment
# - Input validation for all user inputs
# - Secure password generation
# - Credentials stored in separate protected files
# - Cleanup on exit

set -euo pipefail

# Cleanup trap for security
cleanup() {
    local exit_code=$?
    # Restore terminal echo in case of interrupt during password input
    stty echo 2>/dev/null || true
    # Clear sensitive variables
    unset API_PASSWORD INDEXER_ADMIN_PASSWORD MANAGER_CLUSTER_KEY 2>/dev/null || true
    exit $exit_code
}
trap cleanup EXIT INT TERM

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default values
DEFAULT_WAZUH_VERSION="4.14.1"
DEFAULT_INDEXER_HTTP_PORT="9200"
DEFAULT_INDEXER_TRANSPORT_PORT="9300"
DEFAULT_DASHBOARD_PORT="443"
DEFAULT_MANAGER_API_PORT="55000"
DEFAULT_AGENT_PORT="1514"

# Function to print colored output
print_header() {
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}\n"
}

print_section() {
    echo -e "\n${GREEN}▶ $1${NC}\n"
}

print_info() {
    echo -e "${YELLOW}ℹ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# Secure variable assignment without eval
set_var() {
    local var_name="$1"
    local value="$2"
    printf -v "$var_name" '%s' "$value"
}

# Input sanitization functions
sanitize_alphanum() {
    # Allow alphanumeric, dots, hyphens, underscores
    echo "$1" | tr -cd 'a-zA-Z0-9._-'
}

sanitize_path() {
    # Allow path characters but prevent traversal
    local path="$1"
    # Remove any ../ sequences
    path="${path//\.\.\//}"
    echo "$path" | tr -cd 'a-zA-Z0-9._/-'
}

validate_ip() {
    local ip="$1"
    local IFS='.'
    read -ra octets <<< "$ip"
    [[ ${#octets[@]} -eq 4 ]] || return 1
    for octet in "${octets[@]}"; do
        [[ "$octet" =~ ^[0-9]+$ ]] || return 1
        (( octet >= 0 && octet <= 255 )) || return 1
    done
    return 0
}

validate_hostname() {
    local host="$1"
    # Valid hostname or IP
    if validate_ip "$host"; then
        return 0
    fi
    # RFC 1123 hostname validation
    [[ "$host" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]{0,253}[a-zA-Z0-9])?$ ]]
}

validate_port() {
    local port="$1"
    [[ "$port" =~ ^[0-9]+$ ]] && (( port >= 1 && port <= 65535 ))
}

# Function to prompt for input with default value
prompt_with_default() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"
    local is_password="${4:-false}"
    local value=""

    if [ "$is_password" = "true" ]; then
        # For passwords, -s hides input, no -e needed since no editing visible
        read -rsp "$(echo -e "${CYAN}$prompt ${NC}[${YELLOW}hidden${NC}]: ")" value
        echo
    else
        # Use -erp with prompt passed through echo -e for color support
        read -erp "$(echo -e "${CYAN}$prompt ${NC}[${YELLOW}$default${NC}]: ")" value
    fi

    if [ -z "$value" ]; then
        set_var "$var_name" "$default"
    else
        set_var "$var_name" "$value"
    fi
}

# Function to prompt for yes/no
prompt_yes_no() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"
    local value=""

    while true; do
        read -erp "$(echo -e "${CYAN}$prompt ${NC}[${YELLOW}$default${NC}]: ")" value

        if [ -z "$value" ]; then
            value="$default"
        fi

        case "${value,,}" in
            y|yes) set_var "$var_name" "true"; return ;;
            n|no) set_var "$var_name" "false"; return ;;
            *) echo -e "${RED}Please enter yes or no${NC}" ;;
        esac
    done
}

# Function to prompt for multiple hosts
prompt_hosts() {
    local prompt="$1"
    local var_name="$2"
    local hosts=()

    echo -e "${CYAN}$prompt${NC}"
    echo -e "${YELLOW}Enter hostnames/IPs one per line. Enter empty line when done.${NC}"

    local count=1
    while true; do
        read -erp "  Host $count: " host
        if [ -z "$host" ]; then
            break
        fi
        # Validate hostname/IP
        if ! validate_hostname "$host"; then
            print_error "Invalid hostname/IP: $host"
            continue
        fi
        hosts+=("$host")
        ((count++))
    done

    # Use printf to safely assign array
    printf -v "$var_name" '%s' "${hosts[*]}"
}

# Function to generate cryptographically secure random password
# Wazuh requires: upper, lower, number, and symbol
generate_password() {
    local length="${1:-24}"
    local password=""
    local symbols='!@#$%^&*'

    # Generate base password with mixed characters
    local base_len=$((length - 4))

    if command -v openssl &>/dev/null; then
        # Generate more than needed and take what we need
        password=$(openssl rand -base64 100 2>/dev/null | tr -d '/+=\n' | head -c "$base_len")
    fi

    # Fallback to /dev/urandom if openssl failed or didn't generate enough
    while [ ${#password} -lt "$base_len" ]; do
        password="${password}$(head -c 200 /dev/urandom 2>/dev/null | LC_ALL=C tr -dc 'a-zA-Z0-9' | head -c $((base_len - ${#password})))"
    done

    # Ensure we have exactly base_len characters
    password="${password:0:$base_len}"

    # Generate guaranteed characters (use more bytes to ensure we get one)
    local upper=$(head -c 100 /dev/urandom | LC_ALL=C tr -dc 'A-Z' | head -c 1)
    local lower=$(head -c 100 /dev/urandom | LC_ALL=C tr -dc 'a-z' | head -c 1)
    local number=$(head -c 100 /dev/urandom | LC_ALL=C tr -dc '0-9' | head -c 1)
    local symbol="${symbols:$((RANDOM % ${#symbols})):1}"

    # Fallback if any character generation failed
    [ -z "$upper" ] && upper="A"
    [ -z "$lower" ] && lower="z"
    [ -z "$number" ] && number="7"

    password="${password}${upper}${lower}${number}${symbol}"

    # Shuffle the password to distribute special chars
    password=$(echo "$password" | fold -w1 | shuf | tr -d '\n')

    echo "$password"
}

# Main setup function
main() {
    clear
    print_header "Wazuh Ansible Deployment - Interactive Setup"

    echo -e "${YELLOW}This script will help you configure the Ansible variables for${NC}"
    echo -e "${YELLOW}deploying Wazuh (Manager, Indexer, Dashboard, and Agents).${NC}"
    echo

    # ═══════════════════════════════════════════════════════════════
    # GENERAL SETTINGS
    # ═══════════════════════════════════════════════════════════════
    print_section "General Settings"

    prompt_with_default "Wazuh version to install" "$DEFAULT_WAZUH_VERSION" "WAZUH_VERSION"
    prompt_with_default "Environment name (e.g., production, staging)" "production" "ENVIRONMENT"
    prompt_with_default "Organization name" "MyOrg" "ORG_NAME"

    # ═══════════════════════════════════════════════════════════════
    # WAZUH INDEXER CONFIGURATION
    # ═══════════════════════════════════════════════════════════════
    print_section "Wazuh Indexer Configuration"

    print_info "The Wazuh Indexer stores and indexes alerts and events."
    echo

    prompt_hosts "Enter Wazuh Indexer node(s)" "INDEXER_NODES"

    if [ -z "$INDEXER_NODES" ]; then
        print_error "At least one Indexer node is required!"
        exit 1
    fi

    INDEXER_NODES_ARRAY=($INDEXER_NODES)
    INDEXER_COUNT=${#INDEXER_NODES_ARRAY[@]}

    prompt_with_default "Indexer HTTP port" "$DEFAULT_INDEXER_HTTP_PORT" "INDEXER_HTTP_PORT"
    prompt_with_default "Indexer cluster name" "wazuh-cluster" "INDEXER_CLUSTER_NAME"

    # Indexer memory settings
    prompt_with_default "Indexer JVM heap size (e.g., 1g, 2g, 4g)" "1g" "INDEXER_HEAP_SIZE"

    # ═══════════════════════════════════════════════════════════════
    # WAZUH MANAGER CONFIGURATION
    # ═══════════════════════════════════════════════════════════════
    print_section "Wazuh Manager Configuration"

    print_info "The Wazuh Manager analyzes data received from agents."
    echo

    prompt_hosts "Enter Wazuh Manager node(s)" "MANAGER_NODES"

    if [ -z "$MANAGER_NODES" ]; then
        print_error "At least one Manager node is required!"
        exit 1
    fi

    MANAGER_NODES_ARRAY=($MANAGER_NODES)
    MANAGER_COUNT=${#MANAGER_NODES_ARRAY[@]}

    prompt_with_default "Manager API port" "$DEFAULT_MANAGER_API_PORT" "MANAGER_API_PORT"
    prompt_with_default "Agent registration port" "$DEFAULT_AGENT_PORT" "AGENT_PORT"

    if [ $MANAGER_COUNT -gt 1 ]; then
        print_info "Multiple managers detected. Configuring cluster..."
        prompt_with_default "Manager cluster name" "wazuh-manager-cluster" "MANAGER_CLUSTER_NAME"

        # Generate secure cluster key - fail if we can't generate one securely
        local cluster_key_default=""
        if command -v openssl &>/dev/null; then
            cluster_key_default=$(openssl rand -hex 16 2>/dev/null)
        fi
        if [ -z "$cluster_key_default" ]; then
            # Fallback to /dev/urandom
            cluster_key_default=$(head -c 16 /dev/urandom 2>/dev/null | od -An -tx1 | tr -d ' \n' | head -c 32)
        fi
        if [ -z "$cluster_key_default" ] || [ ${#cluster_key_default} -lt 32 ]; then
            print_error "FATAL: Cannot generate secure cluster key. OpenSSL and /dev/urandom both failed."
            print_error "Please install OpenSSL or ensure /dev/urandom is available."
            exit 1
        fi
        prompt_with_default "Cluster key (32 characters)" "$cluster_key_default" "MANAGER_CLUSTER_KEY"
    fi

    # ═══════════════════════════════════════════════════════════════
    # WAZUH DASHBOARD CONFIGURATION
    # ═══════════════════════════════════════════════════════════════
    print_section "Wazuh Dashboard Configuration"

    print_info "The Wazuh Dashboard provides a web interface for data visualization."
    echo

    prompt_hosts "Enter Wazuh Dashboard node(s)" "DASHBOARD_NODES"

    if [ -z "$DASHBOARD_NODES" ]; then
        print_error "At least one Dashboard node is required!"
        exit 1
    fi

    DASHBOARD_NODES_ARRAY=($DASHBOARD_NODES)

    prompt_with_default "Dashboard HTTPS port" "$DEFAULT_DASHBOARD_PORT" "DASHBOARD_PORT"

    # ═══════════════════════════════════════════════════════════════
    # WAZUH AGENTS CONFIGURATION
    # ═══════════════════════════════════════════════════════════════
    print_section "Wazuh Agents Configuration"

    print_info "Wazuh Agents collect and forward security data from monitored systems."
    echo

    prompt_yes_no "Do you want to deploy agents now?" "yes" "DEPLOY_AGENTS"

    if [ "$DEPLOY_AGENTS" = "true" ]; then
        prompt_hosts "Enter Agent host(s)" "AGENT_NODES"
        AGENT_NODES_ARRAY=($AGENT_NODES)
    fi

    # ═══════════════════════════════════════════════════════════════
    # SECURITY CONFIGURATION
    # ═══════════════════════════════════════════════════════════════
    print_section "Security Configuration"

    print_info "All passwords are auto-generated during deployment for security."
    print_info "Credentials will be encrypted in Ansible Vault and displayed at the end."
    echo

    prompt_yes_no "Provide custom passwords instead of auto-generating?" "no" "CUSTOM_PASSWORDS"

    if [ "$CUSTOM_PASSWORDS" = "true" ]; then
        prompt_with_default "Wazuh API admin username" "wazuh" "API_USER"
        prompt_with_default "Wazuh API admin password" "" "API_PASSWORD" "true"
        prompt_with_default "Indexer admin password" "" "INDEXER_ADMIN_PASSWORD" "true"
    else
        API_USER="wazuh"
        API_PASSWORD=""
        INDEXER_ADMIN_PASSWORD=""
        print_info "All passwords will be auto-generated during deployment"
    fi

    # Indexer admin username is always 'admin' (OpenSearch default)
    INDEXER_ADMIN_USER="admin"

    # ═══════════════════════════════════════════════════════════════
    # SECRETS MANAGEMENT (ANSIBLE VAULT)
    # ═══════════════════════════════════════════════════════════════
    print_section "Secrets Management (Ansible Vault)"

    print_info "Ansible Vault encrypts sensitive data like passwords and keys."
    print_info "This is the recommended secure approach for credential management."
    echo

    # Vault is enabled by default for security
    USE_VAULT="true"
    print_success "Ansible Vault will be used for credential encryption"
    print_info "Vault password will be stored in: .vault_password"
    print_info "Encrypted credentials will be in: group_vars/all/vault.yml"

    # ═══════════════════════════════════════════════════════════════
    # SSL/TLS CONFIGURATION
    # ═══════════════════════════════════════════════════════════════
    print_section "SSL/TLS Configuration"

    print_info "Wazuh requires TLS certificates for secure communication."
    print_info "You can use self-signed certificates or your own CA certificates."
    echo

    prompt_yes_no "Use self-signed certificates? (No = provide your own)" "yes" "USE_SELF_SIGNED_CERTS"

    if [ "$USE_SELF_SIGNED_CERTS" = "true" ]; then
        GENERATE_CERTS="true"
        EXTERNAL_CA="false"
        print_info "Self-signed certificates will be generated automatically"
    else
        GENERATE_CERTS="false"
        EXTERNAL_CA="true"
        echo
        print_info "External CA mode: You must provide certificates in ./files/certs/"
        print_info "Required files:"
        print_info "  - root-ca.pem, root-ca-key.pem (Root CA)"
        print_info "  - admin.pem, admin-key.pem (Admin certificate)"
        print_info "  - indexer-N.pem, indexer-N-key.pem (Indexer nodes)"
        print_info "  - manager-N.pem, manager-N-key.pem (Manager nodes)"
        print_info "  - dashboard.pem, dashboard-key.pem (Dashboard)"
        echo
        print_warning "Ensure your certificates include proper SANs for all hostnames/IPs"
    fi

    # ═══════════════════════════════════════════════════════════════
    # SSH CONFIGURATION
    # ═══════════════════════════════════════════════════════════════
    print_section "SSH Configuration"

    print_info "Configure SSH access to your Wazuh servers"
    print_info "(indexers, managers, dashboard hosts, and agents)"
    echo

    # Collect all hosts for per-host credential prompts (including agents if configured)
    ALL_INFRA_HOSTS=()
    for h in "${INDEXER_NODES_ARRAY[@]}" "${MANAGER_NODES_ARRAY[@]}" "${DASHBOARD_NODES_ARRAY[@]}" "${AGENT_NODES_ARRAY[@]}"; do
        # Add only unique hosts
        local found=0
        if [ ${#ALL_INFRA_HOSTS[@]} -gt 0 ]; then
            for existing in "${ALL_INFRA_HOSTS[@]}"; do
                if [ "$existing" = "$h" ]; then
                    found=1
                    break
                fi
            done
        fi
        [ $found -eq 0 ] && ALL_INFRA_HOSTS+=("$h")
    done

    prompt_yes_no "Generate new SSH key pair for Ansible?" "yes" "GENERATE_SSH_KEY"

    if [ "$GENERATE_SSH_KEY" = "true" ]; then
        ANSIBLE_SSH_KEY="${SCRIPT_DIR}/keys/wazuh_ansible_key"
        print_info "SSH key will be generated at: ${ANSIBLE_SSH_KEY}"
        echo
        print_info "Ansible user: A dedicated user to create for Ansible deployments"
        prompt_with_default "Ansible deployment user (will be created)" "wazuh-deploy" "ANSIBLE_USER"
    else
        prompt_with_default "SSH private key path" "~/.ssh/id_rsa" "ANSIBLE_SSH_KEY"
        prompt_with_default "Default SSH user for Ansible" "root" "ANSIBLE_USER"
    fi

    prompt_with_default "Default SSH port" "22" "ANSIBLE_SSH_PORT"
    prompt_yes_no "Use sudo for privilege escalation?" "yes" "USE_BECOME"

    # Per-host SSH credentials
    echo
    print_info "You can configure SSH credentials per host, or use the same for all."
    prompt_yes_no "Do all hosts use the same initial SSH user/password?" "yes" "SAME_SSH_CREDS"

    # Declare associative arrays for per-host credentials
    declare -gA HOST_SSH_USER
    declare -gA HOST_SSH_PASS

    if [ "$SAME_SSH_CREDS" = "true" ]; then
        echo
        print_info "Initial SSH user: The existing user on your servers to connect with"
        prompt_with_default "Initial SSH user for all hosts" "root" "INITIAL_SSH_USER"
        echo
        print_info "SSH password is used if not using key-based authentication."
        print_info "Leave empty if using SSH keys only."
        prompt_with_default "SSH password for all hosts" "" "DEFAULT_SSH_PASS" "true"

        # Set same credentials for all hosts
        for host in "${ALL_INFRA_HOSTS[@]}"; do
            HOST_SSH_USER["$host"]="$INITIAL_SSH_USER"
            HOST_SSH_PASS["$host"]="$DEFAULT_SSH_PASS"
        done
    else
        echo
        print_info "Enter SSH credentials for each infrastructure host:"
        echo
        for host in "${ALL_INFRA_HOSTS[@]}"; do
            echo -e "${CYAN}Host: ${host}${NC}"
            local user_var=""
            local pass_var=""
            prompt_with_default "  SSH user" "root" "user_var"
            prompt_with_default "  SSH password (empty for key auth)" "" "pass_var" "true"
            HOST_SSH_USER["$host"]="$user_var"
            HOST_SSH_PASS["$host"]="$pass_var"
            echo
        done
        INITIAL_SSH_USER="root"  # Default fallback
    fi

    # Sudo/become password configuration
    if [ "$USE_BECOME" = "true" ]; then
        echo
        print_info "Sudo password configuration for privilege escalation."

        # Check if we have an SSH password to potentially reuse
        if [ -n "${DEFAULT_SSH_PASS:-}" ]; then
            prompt_yes_no "Is the sudo password the same as the SSH password?" "yes" "SUDO_SAME_AS_SSH"
            if [ "$SUDO_SAME_AS_SSH" = "true" ]; then
                BECOME_PASS="$DEFAULT_SSH_PASS"
                print_info "Using SSH password for sudo"
            else
                prompt_with_default "Sudo password" "" "BECOME_PASS" "true"
            fi
        else
            # No SSH password was provided, ask for sudo password
            prompt_with_default "Sudo password (required for privilege escalation)" "" "BECOME_PASS" "true"
        fi
    fi

    prompt_yes_no "Create client preparation package?" "yes" "CREATE_PREP_PACKAGE"

    # ═══════════════════════════════════════════════════════════════
    # SECURITY FEATURES
    # ═══════════════════════════════════════════════════════════════
    print_section "Security Features"

    print_info "Configure which Wazuh security modules to enable."
    echo

    prompt_yes_no "Enable Vulnerability Detection?" "yes" "ENABLE_VULN_DETECTION"
    prompt_yes_no "Enable File Integrity Monitoring (FIM)?" "yes" "ENABLE_FIM"
    prompt_yes_no "Enable Rootkit Detection?" "yes" "ENABLE_ROOTKIT"
    prompt_yes_no "Enable Security Configuration Assessment (SCA)?" "yes" "ENABLE_SCA"
    prompt_yes_no "Enable System Inventory (Syscollector)?" "yes" "ENABLE_SYSCOLLECTOR"
    prompt_yes_no "Enable Log Collection?" "yes" "ENABLE_LOG_COLLECTION"
    prompt_yes_no "Enable Active Response?" "yes" "ENABLE_ACTIVE_RESPONSE"

    # ═══════════════════════════════════════════════════════════════
    # EMAIL ALERTS CONFIGURATION
    # ═══════════════════════════════════════════════════════════════
    print_section "Email Alerts Configuration"

    prompt_yes_no "Enable email alerts?" "no" "ENABLE_EMAIL_ALERTS"

    if [ "$ENABLE_EMAIL_ALERTS" = "true" ]; then
        print_info "Configure SMTP settings for email alerts."
        echo
        prompt_with_default "SMTP server address" "smtp.example.com" "EMAIL_SMTP_SERVER"
        prompt_with_default "Email from address" "wazuh@${ORG_NAME,,}.local" "EMAIL_FROM"
        prompt_with_default "Email to address (alerts recipient)" "security@${ORG_NAME,,}.local" "EMAIL_TO"
        prompt_with_default "Minimum alert level for email (1-15)" "12" "EMAIL_ALERT_LEVEL"
    fi

    # ═══════════════════════════════════════════════════════════════
    # SYSLOG OUTPUT CONFIGURATION
    # ═══════════════════════════════════════════════════════════════
    print_section "Syslog Output Configuration"

    print_info "Forward alerts to external SIEM/log collector via syslog."
    echo

    prompt_yes_no "Enable syslog output?" "no" "ENABLE_SYSLOG_OUTPUT"

    if [ "$ENABLE_SYSLOG_OUTPUT" = "true" ]; then
        prompt_with_default "Syslog server address" "" "SYSLOG_SERVER"
        while [ -z "$SYSLOG_SERVER" ]; do
            print_error "Syslog server address is required when syslog output is enabled."
            prompt_with_default "Syslog server address" "" "SYSLOG_SERVER"
        done
        prompt_with_default "Syslog port" "514" "SYSLOG_PORT"
        echo -e "${CYAN}Syslog format options: default, json, cef${NC}"
        prompt_with_default "Syslog format" "json" "SYSLOG_FORMAT"
        prompt_with_default "Minimum alert level for syslog (1-15, leave empty for all)" "" "SYSLOG_LEVEL"
    fi

    # ═══════════════════════════════════════════════════════════════
    # INTEGRATIONS
    # ═══════════════════════════════════════════════════════════════
    print_section "Integrations"

    print_info "Configure third-party integrations for alerts."
    echo

    prompt_yes_no "Enable Slack notifications?" "no" "ENABLE_SLACK"

    if [ "$ENABLE_SLACK" = "true" ]; then
        print_info "Get your Slack webhook URL from: https://api.slack.com/messaging/webhooks"
        prompt_with_default "Slack webhook URL" "" "SLACK_WEBHOOK_URL"
        while [ -z "$SLACK_WEBHOOK_URL" ]; do
            print_error "Slack webhook URL is required when Slack is enabled."
            prompt_with_default "Slack webhook URL" "" "SLACK_WEBHOOK_URL"
        done
        prompt_with_default "Minimum alert level for Slack (1-15)" "10" "SLACK_ALERT_LEVEL"
    fi

    prompt_yes_no "Enable VirusTotal integration?" "no" "ENABLE_VIRUSTOTAL"

    if [ "$ENABLE_VIRUSTOTAL" = "true" ]; then
        print_info "Get your API key from: https://www.virustotal.com/gui/my-apikey"
        prompt_with_default "VirusTotal API key" "" "VIRUSTOTAL_API_KEY" "true"
        while [ -z "$VIRUSTOTAL_API_KEY" ]; do
            print_error "VirusTotal API key is required when VirusTotal is enabled."
            prompt_with_default "VirusTotal API key" "" "VIRUSTOTAL_API_KEY" "true"
        done
    fi

    # ═══════════════════════════════════════════════════════════════
    # BACKUP & MAINTENANCE
    # ═══════════════════════════════════════════════════════════════
    print_section "Backup & Maintenance"

    print_info "Configure automated backups and log retention."
    echo

    # Backup schedule
    echo -e "${CYAN}Backup schedule options:${NC}"
    echo "  1) Daily (recommended for production)"
    echo "  2) Weekly"
    echo "  3) Disabled (manual backups only)"
    echo
    read -erp "$(echo -e "${YELLOW}Select backup schedule [1]: ${NC}")" BACKUP_SCHEDULE_CHOICE
    BACKUP_SCHEDULE_CHOICE=${BACKUP_SCHEDULE_CHOICE:-1}

    case $BACKUP_SCHEDULE_CHOICE in
        1)
            BACKUP_SCHEDULE="daily"
            prompt_with_default "Backup hour (0-23)" "2" "BACKUP_HOUR"
            ;;
        2)
            BACKUP_SCHEDULE="weekly"
            prompt_with_default "Backup hour (0-23)" "2" "BACKUP_HOUR"
            echo -e "${CYAN}Day options: 0=Sunday, 1=Monday, ..., 6=Saturday${NC}"
            prompt_with_default "Backup day of week (0-6)" "0" "BACKUP_DAY"
            ;;
        3)
            BACKUP_SCHEDULE="disabled"
            ;;
        *)
            BACKUP_SCHEDULE="daily"
            BACKUP_HOUR="2"
            ;;
    esac

    if [ "$BACKUP_SCHEDULE" != "disabled" ]; then
        prompt_with_default "Number of backups to keep" "7" "BACKUP_RETENTION"
    fi

    echo

    # Log cleanup
    prompt_yes_no "Enable automatic log cleanup on manager?" "yes" "ENABLE_LOG_CLEANUP"

    if [ "$ENABLE_LOG_CLEANUP" = "true" ]; then
        prompt_with_default "Days of logs to keep" "30" "LOG_RETENTION_DAYS"
        echo -e "${CYAN}Log cleanup schedule:${NC}"
        echo "  1) Daily (recommended)"
        echo "  2) Weekly"
        echo
        read -erp "$(echo -e "${YELLOW}Select log cleanup schedule [1]: ${NC}")" LOG_CLEANUP_SCHEDULE_CHOICE
        LOG_CLEANUP_SCHEDULE_CHOICE=${LOG_CLEANUP_SCHEDULE_CHOICE:-1}

        case $LOG_CLEANUP_SCHEDULE_CHOICE in
            1) LOG_CLEANUP_SCHEDULE="daily" ;;
            2) LOG_CLEANUP_SCHEDULE="weekly" ;;
            *) LOG_CLEANUP_SCHEDULE="daily" ;;
        esac
    fi

    # ═══════════════════════════════════════════════════════════════
    # GENERATE CONFIGURATION FILES
    # ═══════════════════════════════════════════════════════════════
    print_section "Generating Configuration Files"

    # Create inventory file
    print_info "Creating inventory file..."

    cat > "$SCRIPT_DIR/inventory/hosts.yml" << 'EOF'
---
all:
  vars:
    ansible_user: "{{ vault_ansible_user }}"
EOF
    cat >> "$SCRIPT_DIR/inventory/hosts.yml" << EOF
    ansible_ssh_private_key_file: ${ANSIBLE_SSH_KEY}
    ansible_port: ${ANSIBLE_SSH_PORT}
    ansible_become: ${USE_BECOME}
EOF

    # Add become password if sudo is enabled and password is set
    if [ "$USE_BECOME" = "true" ] && [ -n "${BECOME_PASS:-}" ]; then
        echo '    ansible_become_pass: "{{ vault_ansible_become_password }}"' >> "$SCRIPT_DIR/inventory/hosts.yml"
    fi

    cat >> "$SCRIPT_DIR/inventory/hosts.yml" << EOF

  children:
    wazuh_indexers:
      hosts:
EOF

    # Add indexer hosts with per-host SSH credentials
    for i in "${!INDEXER_NODES_ARRAY[@]}"; do
        node="${INDEXER_NODES_ARRAY[$i]}"
        node_name="indexer-$((i+1))"
        cat >> "$SCRIPT_DIR/inventory/hosts.yml" << EOF
        ${node}:
          indexer_node_name: ${node_name}
EOF
        # Add per-host SSH credentials from vault
        if [ -n "${HOST_SSH_USER[$node]:-}" ]; then
            echo "          ansible_user: \"{{ vault_ssh_user_${node//./_} }}\"" >> "$SCRIPT_DIR/inventory/hosts.yml"
        fi
        if [ -n "${HOST_SSH_PASS[$node]:-}" ]; then
            echo "          ansible_ssh_pass: \"{{ vault_ssh_pass_${node//./_} }}\"" >> "$SCRIPT_DIR/inventory/hosts.yml"
        fi
        if [ $i -eq 0 ]; then
            echo "          indexer_cluster_initial_master: true" >> "$SCRIPT_DIR/inventory/hosts.yml"
        fi
    done

    cat >> "$SCRIPT_DIR/inventory/hosts.yml" << EOF

    wazuh_managers:
      hosts:
EOF

    # Add manager hosts with per-host SSH credentials
    for i in "${!MANAGER_NODES_ARRAY[@]}"; do
        node="${MANAGER_NODES_ARRAY[$i]}"
        node_name="manager-$((i+1))"
        cat >> "$SCRIPT_DIR/inventory/hosts.yml" << EOF
        ${node}:
          manager_node_name: ${node_name}
EOF
        # Add per-host SSH credentials from vault
        if [ -n "${HOST_SSH_USER[$node]:-}" ]; then
            echo "          ansible_user: \"{{ vault_ssh_user_${node//./_} }}\"" >> "$SCRIPT_DIR/inventory/hosts.yml"
        fi
        if [ -n "${HOST_SSH_PASS[$node]:-}" ]; then
            echo "          ansible_ssh_pass: \"{{ vault_ssh_pass_${node//./_} }}\"" >> "$SCRIPT_DIR/inventory/hosts.yml"
        fi
        if [ $MANAGER_COUNT -gt 1 ]; then
            if [ $i -eq 0 ]; then
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

    # Add dashboard hosts with per-host SSH credentials
    for node in "${DASHBOARD_NODES_ARRAY[@]}"; do
        echo "        ${node}:" >> "$SCRIPT_DIR/inventory/hosts.yml"
        # Add per-host SSH credentials from vault
        if [ -n "${HOST_SSH_USER[$node]:-}" ]; then
            echo "          ansible_user: \"{{ vault_ssh_user_${node//./_} }}\"" >> "$SCRIPT_DIR/inventory/hosts.yml"
        fi
        if [ -n "${HOST_SSH_PASS[$node]:-}" ]; then
            echo "          ansible_ssh_pass: \"{{ vault_ssh_pass_${node//./_} }}\"" >> "$SCRIPT_DIR/inventory/hosts.yml"
        fi
    done

    if [ "$DEPLOY_AGENTS" = "true" ] && [ -n "$AGENT_NODES" ]; then
        cat >> "$SCRIPT_DIR/inventory/hosts.yml" << EOF

    wazuh_agents:
      hosts:
EOF
        # Add agent hosts with per-host SSH credentials
        for node in "${AGENT_NODES_ARRAY[@]}"; do
            echo "        ${node}:" >> "$SCRIPT_DIR/inventory/hosts.yml"
            # Add per-host SSH user if different from default
            if [ -n "${HOST_SSH_USER[$node]:-}" ]; then
                echo "          ansible_user: ${HOST_SSH_USER[$node]}" >> "$SCRIPT_DIR/inventory/hosts.yml"
            fi
            # Add per-host SSH password if set
            if [ -n "${HOST_SSH_PASS[$node]:-}" ]; then
                echo "          ansible_ssh_pass: \"{{ vault_ssh_pass_${node//./_} }}\"" >> "$SCRIPT_DIR/inventory/hosts.yml"
            fi
        done
    fi

    # Add localhost with local connection (doesn't use vault credentials)
    cat >> "$SCRIPT_DIR/inventory/hosts.yml" << 'EOF'

    # Local deployment host (for running maintenance tasks)
    local:
      hosts:
        localhost:
          ansible_connection: local
          ansible_user: "{{ lookup('env', 'USER') }}"
          ansible_become: false
          ansible_become_pass: ""
          ansible_ssh_pass: ""
EOF

    print_success "Inventory file created: inventory/hosts.yml"

    # Create group_vars/all/main.yml
    print_info "Creating group variables..."
    mkdir -p "$SCRIPT_DIR/group_vars/all"

    cat > "$SCRIPT_DIR/group_vars/all/main.yml" << EOF
---
# Wazuh Ansible Deployment - Group Variables
# Generated by setup.sh on $(date)

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
wazuh_indexer_http_port: ${INDEXER_HTTP_PORT}
wazuh_indexer_transport_port: ${DEFAULT_INDEXER_TRANSPORT_PORT}
wazuh_indexer_heap_size: "${INDEXER_HEAP_SIZE}"
# Indexer admin credentials
wazuh_indexer_admin_user: "${INDEXER_ADMIN_USER}"
EOF

    # Generate or use provided indexer admin password
    if [ -n "${INDEXER_ADMIN_PASSWORD:-}" ]; then
        GENERATED_INDEXER_PASSWORD="${INDEXER_ADMIN_PASSWORD}"
        print_info "Using custom indexer password"
    else
        GENERATED_INDEXER_PASSWORD=$(generate_password 24)
        print_info "Generated indexer admin password"
    fi

    # Reference password via Ansible Vault
    cat >> "$SCRIPT_DIR/group_vars/all/main.yml" << 'EOF'
# Indexer admin password loaded from Ansible Vault
# SECURITY: Password encrypted in group_vars/all/vault.yml
# To view/edit: ansible-vault view/edit group_vars/all/vault.yml --vault-password-file .vault_password
wazuh_indexer_admin_password: "{{ vault_wazuh_indexer_admin_password }}"
EOF

    cat >> "$SCRIPT_DIR/group_vars/all/main.yml" << EOF

# Indexer node list for cluster configuration
wazuh_indexer_nodes:
EOF

    for i in "${!INDEXER_NODES_ARRAY[@]}"; do
        node="${INDEXER_NODES_ARRAY[$i]}"
        echo "  - name: indexer-$((i+1))" >> "$SCRIPT_DIR/group_vars/all/main.yml"
        echo "    ip: ${node}" >> "$SCRIPT_DIR/group_vars/all/main.yml"
    done

    cat >> "$SCRIPT_DIR/group_vars/all/main.yml" << EOF

# ═══════════════════════════════════════════════════════════════
# Wazuh Manager Settings
# ═══════════════════════════════════════════════════════════════
wazuh_manager_api_port: ${MANAGER_API_PORT}
wazuh_manager_agent_port: ${AGENT_PORT}
wazuh_api_user: "${API_USER}"
EOF

    # Generate or use provided API password
    if [ -n "${API_PASSWORD:-}" ]; then
        GENERATED_API_PASSWORD="${API_PASSWORD}"
        print_info "Using custom API password"
    else
        GENERATED_API_PASSWORD=$(generate_password 24)
        print_info "Generated API password"
    fi

    # Reference password via Ansible Vault
    cat >> "$SCRIPT_DIR/group_vars/all/main.yml" << 'EOF'
# API password loaded from Ansible Vault
# SECURITY: Password encrypted in group_vars/all/vault.yml
wazuh_api_password: "{{ vault_wazuh_api_password }}"
EOF

    # Build per-host SSH credentials string for vault (format: host1:user1:pass1,host2:user2:pass2)
    HOST_CREDENTIALS_STRING=""
    for host in "${ALL_INFRA_HOSTS[@]}"; do
        local user="${HOST_SSH_USER[$host]:-${INITIAL_SSH_USER:-root}}"
        local pass="${HOST_SSH_PASS[$host]:-${DEFAULT_SSH_PASS:-}}"
        if [ -n "$pass" ]; then
            if [ -n "$HOST_CREDENTIALS_STRING" ]; then
                HOST_CREDENTIALS_STRING="${HOST_CREDENTIALS_STRING},"
            fi
            HOST_CREDENTIALS_STRING="${HOST_CREDENTIALS_STRING}${host}:${user}:${pass}"
        fi
    done

    # Generate enrollment password
    GENERATED_ENROLLMENT_PASSWORD=$(generate_password 24)
    print_info "Generated agent enrollment password"

    if [ $MANAGER_COUNT -gt 1 ]; then
        cat >> "$SCRIPT_DIR/group_vars/all/main.yml" << EOF

# Manager cluster settings
wazuh_manager_cluster_enabled: true
wazuh_manager_cluster_name: "${MANAGER_CLUSTER_NAME}"
EOF
        # Reference cluster key via Ansible Vault
        cat >> "$SCRIPT_DIR/group_vars/all/main.yml" << 'EOF'
# Cluster key loaded from Ansible Vault
wazuh_manager_cluster_key: "{{ vault_wazuh_manager_cluster_key }}"
EOF
    else
        echo "wazuh_manager_cluster_enabled: false" >> "$SCRIPT_DIR/group_vars/all/main.yml"
    fi

    cat >> "$SCRIPT_DIR/group_vars/all/main.yml" << EOF

# Manager node list
wazuh_manager_nodes:
EOF

    for i in "${!MANAGER_NODES_ARRAY[@]}"; do
        node="${MANAGER_NODES_ARRAY[$i]}"
        echo "  - name: manager-$((i+1))" >> "$SCRIPT_DIR/group_vars/all/main.yml"
        echo "    ip: ${node}" >> "$SCRIPT_DIR/group_vars/all/main.yml"
    done

    cat >> "$SCRIPT_DIR/group_vars/all/main.yml" << EOF

# ═══════════════════════════════════════════════════════════════
# Wazuh Dashboard Settings
# ═══════════════════════════════════════════════════════════════
wazuh_dashboard_port: ${DASHBOARD_PORT}
# Dashboard uses the indexer admin credentials (admin user)

# Dashboard node list
wazuh_dashboard_nodes:
EOF

    for node in "${DASHBOARD_NODES_ARRAY[@]}"; do
        echo "  - ip: ${node}" >> "$SCRIPT_DIR/group_vars/all/main.yml"
    done

    cat >> "$SCRIPT_DIR/group_vars/all/main.yml" << EOF

# ═══════════════════════════════════════════════════════════════
# SSL/TLS Configuration
# ═══════════════════════════════════════════════════════════════

# Certificate type: self-signed or external CA
wazuh_use_external_ca: ${EXTERNAL_CA:-false}

# Local path where certificates are stored (source for Ansible copy)
wazuh_certs_path: "files/certs"

# Certificate paths on target hosts (destination)
wazuh_indexer_certs_path: /etc/wazuh-indexer/certs
wazuh_manager_certs_path: /var/ossec/etc/certs
wazuh_dashboard_certs_path: /etc/wazuh-dashboard/certs

# SSL certificate verification (set to false for self-signed certs)
# For external CA with proper chain, set to true
wazuh_ssl_verify_certificates: ${EXTERNAL_CA:-false}

# ═══════════════════════════════════════════════════════════════
# Security Feature Toggles
# ═══════════════════════════════════════════════════════════════
wazuh_vulnerability_detection_enabled: ${ENABLE_VULN_DETECTION}
wazuh_fim_enabled: ${ENABLE_FIM}
wazuh_rootkit_detection_enabled: ${ENABLE_ROOTKIT}
wazuh_sca_enabled: ${ENABLE_SCA:-true}
wazuh_syscollector_enabled: ${ENABLE_SYSCOLLECTOR:-true}
wazuh_log_collection_enabled: ${ENABLE_LOG_COLLECTION}
wazuh_active_response_enabled: ${ENABLE_ACTIVE_RESPONSE}
EOF

    # Add email alerts configuration if enabled
    if [ "$ENABLE_EMAIL_ALERTS" = "true" ]; then
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
        cat >> "$SCRIPT_DIR/group_vars/all/main.yml" << EOF

# Email alerts disabled
wazuh_email_notification_enabled: false
EOF
    fi

    # Add syslog output configuration if enabled
    if [ "$ENABLE_SYSLOG_OUTPUT" = "true" ]; then
        cat >> "$SCRIPT_DIR/group_vars/all/main.yml" << EOF

# ═══════════════════════════════════════════════════════════════
# Syslog Output Configuration
# ═══════════════════════════════════════════════════════════════
wazuh_syslog_output_enabled: true
wazuh_syslog_output_server: "${SYSLOG_SERVER}"
wazuh_syslog_output_port: ${SYSLOG_PORT:-514}
wazuh_syslog_output_format: "${SYSLOG_FORMAT:-json}"
EOF
        if [ -n "$SYSLOG_LEVEL" ]; then
            echo "wazuh_syslog_output_level: ${SYSLOG_LEVEL}" >> "$SCRIPT_DIR/group_vars/all/main.yml"
        fi
    else
        cat >> "$SCRIPT_DIR/group_vars/all/main.yml" << EOF

# Syslog output disabled
wazuh_syslog_output_enabled: false
EOF
    fi

    # Add integrations configuration
    local has_integrations=false
    if [ "$ENABLE_SLACK" = "true" ] || [ "$ENABLE_VIRUSTOTAL" = "true" ]; then
        has_integrations=true
        cat >> "$SCRIPT_DIR/group_vars/all/main.yml" << EOF

# ═══════════════════════════════════════════════════════════════
# Integrations
# ═══════════════════════════════════════════════════════════════
wazuh_integrations:
EOF
    fi

    if [ "$ENABLE_SLACK" = "true" ]; then
        cat >> "$SCRIPT_DIR/group_vars/all/main.yml" << EOF
  - name: slack
    hook_url: "${SLACK_WEBHOOK_URL}"
    level: ${SLACK_ALERT_LEVEL:-10}
    alert_format: json
EOF
    fi

    if [ "$ENABLE_VIRUSTOTAL" = "true" ]; then
        cat >> "$SCRIPT_DIR/group_vars/all/main.yml" << EOF
  - name: virustotal
    api_key: "${VIRUSTOTAL_API_KEY}"
    group: "syscheck"
    alert_format: json
EOF
    fi

    if [ "$has_integrations" = "false" ]; then
        cat >> "$SCRIPT_DIR/group_vars/all/main.yml" << EOF

# No integrations configured
wazuh_integrations: []
EOF
    fi

    cat >> "$SCRIPT_DIR/group_vars/all/main.yml" << EOF

# ═══════════════════════════════════════════════════════════════
# Network/Firewall Settings
# ═══════════════════════════════════════════════════════════════
# Firewall configuration (installs and enables UFW/firewalld if needed)
wazuh_configure_firewall: true

# Network subnets are auto-detected from the host's default interface.
# Uncomment below to override with specific subnets:
# wazuh_allowed_agent_networks:
#   - "10.0.0.0/24"
#   - "192.168.1.0/24"
# wazuh_allowed_cluster_networks:
#   - "10.0.0.0/24"

# SELinux configuration
wazuh_configure_selinux: true

# Package repository settings
wazuh_repo_gpg_key: "https://packages.wazuh.com/key/GPG-KEY-WAZUH"
wazuh_repo_url_apt: "https://packages.wazuh.com/4.x/apt/"
wazuh_repo_url_yum: "https://packages.wazuh.com/4.x/yum/"

# ═══════════════════════════════════════════════════════════════
# Backup & Maintenance
# ═══════════════════════════════════════════════════════════════
# Automated backup schedule: daily, weekly, or disabled
wazuh_backup_schedule: "${BACKUP_SCHEDULE:-daily}"
wazuh_backup_hour: ${BACKUP_HOUR:-2}
wazuh_backup_day: ${BACKUP_DAY:-0}
wazuh_backup_retention: ${BACKUP_RETENTION:-7}

# Log cleanup settings
wazuh_log_cleanup_enabled: ${ENABLE_LOG_CLEANUP:-true}
wazuh_log_retention_days: ${LOG_RETENTION_DAYS:-30}
wazuh_log_cleanup_schedule: "${LOG_CLEANUP_SCHEDULE:-daily}"

# ═══════════════════════════════════════════════════════════════
# Post-Deployment Security
# ═══════════════════════════════════════════════════════════════
# Lock down the ansible deployment user after deployment completes
# When locked, the user can only run the unlock script and check Wazuh status
# Set to false to keep full sudo access after deployment
wazuh_lockdown_deploy_user: true
EOF

    print_success "Group variables created: group_vars/all/main.yml"

    # Create ansible.cfg
    print_info "Creating Ansible configuration..."

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
become = ${USE_BECOME}
become_method = sudo
become_user = root

[ssh_connection]
pipelining = True
ssh_args = -o ControlMaster=auto -o ControlPersist=60s -o UserKnownHostsFile=/dev/null
EOF

    print_success "Ansible configuration created: ansible.cfg"

    # ═══════════════════════════════════════════════════════════════
    # SSH KEY GENERATION
    # ═══════════════════════════════════════════════════════════════
    if [ "$GENERATE_SSH_KEY" = "true" ]; then
        print_section "Generating SSH Key Pair"

        mkdir -p "${SCRIPT_DIR}/keys"

        if [ -f "$ANSIBLE_SSH_KEY" ]; then
            print_warning "SSH key already exists: $ANSIBLE_SSH_KEY"
            prompt_yes_no "Overwrite existing key?" "no" "OVERWRITE_KEY"
            if [ "$OVERWRITE_KEY" = "true" ]; then
                rm -f "$ANSIBLE_SSH_KEY" "${ANSIBLE_SSH_KEY}.pub"
            fi
        fi

        if [ ! -f "$ANSIBLE_SSH_KEY" ]; then
            ssh-keygen -t ed25519 -f "$ANSIBLE_SSH_KEY" -N "" -C "wazuh-ansible-deploy"
            chmod 600 "$ANSIBLE_SSH_KEY"
            chmod 644 "${ANSIBLE_SSH_KEY}.pub"
            print_success "SSH key pair generated"
            print_info "Private key: ${ANSIBLE_SSH_KEY}"
            print_info "Public key: ${ANSIBLE_SSH_KEY}.pub"
        fi
    fi

    # ═══════════════════════════════════════════════════════════════
    # CLIENT PREPARATION PACKAGE
    # ═══════════════════════════════════════════════════════════════
    if [ "$CREATE_PREP_PACKAGE" = "true" ]; then
        print_section "Creating Client Preparation Package"

        local prep_dir="${SCRIPT_DIR}/client-prep"
        local tarball="${SCRIPT_DIR}/wazuh-client-prep.tar.gz"

        mkdir -p "$prep_dir"

        # Copy preparation script
        if [ -f "${SCRIPT_DIR}/scripts/prepare-client.sh" ]; then
            cp "${SCRIPT_DIR}/scripts/prepare-client.sh" "$prep_dir/"
        else
            print_warning "Preparation script not found, skipping..."
        fi

        # Copy SSH public key
        if [ -f "${ANSIBLE_SSH_KEY}.pub" ]; then
            cp "${ANSIBLE_SSH_KEY}.pub" "$prep_dir/ansible_key.pub"
        elif [ -f "${SCRIPT_DIR}/keys/wazuh_ansible_key.pub" ]; then
            cp "${SCRIPT_DIR}/keys/wazuh_ansible_key.pub" "$prep_dir/ansible_key.pub"
        fi

        # Create install script for easy deployment
        cat > "$prep_dir/install.sh" << 'INSTALL_EOF'
#!/bin/bash
# Quick install script - run this on target machines
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
chmod +x "${SCRIPT_DIR}/prepare-client.sh"
sudo "${SCRIPT_DIR}/prepare-client.sh" -k "${SCRIPT_DIR}/ansible_key.pub" "$@"
INSTALL_EOF
        chmod +x "$prep_dir/install.sh"

        # Create README
        cat > "$prep_dir/README.txt" << README_EOF
Wazuh Client Preparation Package
=================================

This package prepares target machines for Wazuh deployment via Ansible.

Quick Start:
1. Copy this entire folder to the target machine
2. Run: sudo ./install.sh

Or run with options:
  sudo ./prepare-client.sh -k ansible_key.pub --minimal

Supported Operating Systems:
- Ubuntu 20.04+, Debian 10+
- RHEL/CentOS 8+, Rocky Linux 8+, Fedora
- SUSE Linux Enterprise, openSUSE
- Arch Linux

Options:
  -u, --user NAME     Ansible user to create (default: wazuh-deploy)
  -p, --port PORT     SSH port (default: 22)
  -k, --key FILE      Path to SSH public key file
  -m, --minimal       Skip package removal (faster)
  -d, --dry-run       Show what would happen
  -h, --help          Show help

What this script does:
- Detects your OS automatically
- Removes unnecessary packages (desktop, games, office suites, etc.)
- Installs required packages (Python, SSH, sudo, etc.)
- Creates an Ansible deployment user with sudo access
- Deploys the SSH public key for passwordless access
- Configures firewall for Wazuh ports (UFW, firewalld, iptables, or nftables)
- Optimizes system settings
- Installs unlock script for post-deployment reactivation

Firewall Ports Configured:
- 1514/tcp  - Agent communication
- 1515/tcp  - Agent enrollment
- 1516/tcp  - Manager cluster
- 9200/tcp  - Indexer API
- 9300/tcp  - Indexer cluster
- 443/tcp   - Dashboard HTTPS
- 55000/tcp - Manager API

Post-Deployment:
After Wazuh deployment, the ansible user is automatically locked down
for security. To run future deployments:

  # From your Ansible control node:
  ansible-playbook unlock-deploy-user.yml

  # Or manually on each host:
  sudo /usr/local/bin/wazuh-unlock-deploy

SSH User: ${ANSIBLE_USER}
README_EOF

        # Create tarball
        tar -czf "$tarball" -C "${SCRIPT_DIR}" "client-prep"

        # Also create a self-extracting script
        cat > "${SCRIPT_DIR}/wazuh-client-prep.sh" << 'SELFEXTRACT_EOF'
#!/bin/bash
# Wazuh Client Preparation - Self-extracting installer
# Usage: curl -sSL http://your-server/wazuh-client-prep.sh | sudo bash

set -e

TEMP_DIR=$(mktemp -d)
ARCHIVE_START=$(awk '/^__ARCHIVE_START__$/{print NR + 1; exit 0; }' "$0")

echo "Extracting Wazuh client preparation package..."
tail -n+$ARCHIVE_START "$0" | tar -xz -C "$TEMP_DIR"

cd "$TEMP_DIR/client-prep"
chmod +x prepare-client.sh install.sh

echo "Running preparation script..."
sudo ./prepare-client.sh -k ansible_key.pub "$@"

# Cleanup
rm -rf "$TEMP_DIR"

exit 0

__ARCHIVE_START__
SELFEXTRACT_EOF

        # Append tarball to self-extracting script
        cat "$tarball" >> "${SCRIPT_DIR}/wazuh-client-prep.sh"
        chmod +x "${SCRIPT_DIR}/wazuh-client-prep.sh"

        print_success "Client preparation package created:"
        print_info "  Folder: ${prep_dir}/"
        print_info "  Tarball: ${tarball}"
        print_info "  Self-extracting: ${SCRIPT_DIR}/wazuh-client-prep.sh"
    fi

    # ═══════════════════════════════════════════════════════════════
    # ANSIBLE VAULT INITIALIZATION
    # ═══════════════════════════════════════════════════════════════
    print_section "Initializing Ansible Vault"

    if [ -f "${SCRIPT_DIR}/scripts/manage-vault.sh" ]; then
        chmod +x "${SCRIPT_DIR}/scripts/manage-vault.sh"

        # Initialize vault (creates vault password)
        if [ -f "${SCRIPT_DIR}/.vault_password" ]; then
            print_info "Vault password file already exists"
        else
            print_info "Generating vault password..."
            bash "${SCRIPT_DIR}/scripts/manage-vault.sh" init
            print_success "Vault password created: .vault_password"
        fi

        # Create encrypted vault with credentials via environment variables
        print_info "Creating encrypted vault with credentials..."
        VAULT_INDEXER_PASSWORD="$GENERATED_INDEXER_PASSWORD" \
        VAULT_API_PASSWORD="$GENERATED_API_PASSWORD" \
        VAULT_ENROLLMENT_PASSWORD="$GENERATED_ENROLLMENT_PASSWORD" \
        VAULT_ANSIBLE_USER="$ANSIBLE_USER" \
        VAULT_CONNECTION_PASSWORD="${DEFAULT_SSH_PASS:-}" \
        VAULT_BECOME_PASSWORD="${BECOME_PASS:-}" \
        VAULT_HOST_CREDENTIALS="$HOST_CREDENTIALS_STRING" \
        VAULT_CLUSTER_KEY="${MANAGER_CLUSTER_KEY:-}" \
        bash "${SCRIPT_DIR}/scripts/manage-vault.sh" create
        print_success "Encrypted credentials stored in: group_vars/all/vault.yml"

        print_warning "IMPORTANT: Back up .vault_password securely!"
        print_warning "Without it, you cannot decrypt your credentials."
    else
        print_warning "Vault management script not found, using plaintext credentials"
        print_info "Run: ./scripts/manage-vault.sh create - after setup to encrypt credentials"
    fi

    # ═══════════════════════════════════════════════════════════════
    # CERTIFICATE GENERATION
    # ═══════════════════════════════════════════════════════════════
    print_section "SSL/TLS Certificates"

    if [ "$EXTERNAL_CA" = "true" ]; then
        print_info "External CA mode enabled"
        mkdir -p "${SCRIPT_DIR}/files/certs"

        # Check if external certs exist
        if [ -f "${SCRIPT_DIR}/files/certs/root-ca.pem" ]; then
            print_success "Found root-ca.pem"
            # Validate the certificate
            if [ -f "${SCRIPT_DIR}/playbooks/certificate-management.yml" ]; then
                print_info "Validating certificates..."
                ansible-playbook "${SCRIPT_DIR}/playbooks/certificate-management.yml" --tags validate 2>/dev/null || {
                    print_warning "Certificate validation requires ansible. Run manually after setup:"
                    print_info "  ansible-playbook playbooks/certificate-management.yml --tags validate"
                }
            fi
        else
            print_warning "External CA certificates not found in files/certs/"
            print_info "Please place your certificates before running deployment"
            print_info "Required: root-ca.pem, admin.pem, admin-key.pem, and node certificates"
        fi
    else
        # Self-signed certificate generation
        if [ -f "${SCRIPT_DIR}/generate-certs.sh" ]; then
            # Check if certs already exist
            if [ -f "${SCRIPT_DIR}/files/certs/root-ca.pem" ]; then
                print_warning "Certificates already exist in files/certs/"
                prompt_yes_no "Regenerate certificates?" "no" "REGEN_CERTS"
                if [ "$REGEN_CERTS" = "true" ]; then
                    print_info "Regenerating certificates..."
                    bash "${SCRIPT_DIR}/generate-certs.sh"
                    print_success "Certificates regenerated"
                else
                    print_info "Using existing certificates"
                fi
            else
                print_info "Generating self-signed SSL/TLS certificates..."
                bash "${SCRIPT_DIR}/generate-certs.sh"
                print_success "Certificates generated in files/certs/"
            fi
        else
            print_error "Certificate generation script not found: generate-certs.sh"
            print_info "You will need to generate certificates manually"
        fi
    fi

    # ═══════════════════════════════════════════════════════════════
    # SUMMARY
    # ═══════════════════════════════════════════════════════════════
    print_header "Configuration Summary"

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

    if [ "$DEPLOY_AGENTS" = "true" ] && [ -n "$AGENT_NODES" ]; then
        echo
        echo -e "${GREEN}Agent Nodes (${#AGENT_NODES_ARRAY[@]}):${NC}"
        for node in "${AGENT_NODES_ARRAY[@]}"; do
            echo "  - $node"
        done
    fi

    echo
    echo -e "${CYAN}SSH Configuration:${NC}"
    if [ "$GENERATE_SSH_KEY" = "true" ]; then
        echo "  - Initial SSH user: ${INITIAL_SSH_USER}"
        echo "  - Ansible deployment user: ${ANSIBLE_USER} (will be created)"
        echo "  - SSH key: ${ANSIBLE_SSH_KEY} (will be generated)"
    else
        echo "  - SSH user: ${ANSIBLE_USER}"
        echo "  - SSH key: ${ANSIBLE_SSH_KEY}"
    fi
    echo "  - SSH port: ${ANSIBLE_SSH_PORT}"

    echo
    echo -e "${CYAN}Security:${NC}"
    echo "  - Ansible Vault: Enabled (encrypted credentials)"
    echo "  - Vault password: .vault_password"
    echo "  - Encrypted vault: group_vars/all/vault.yml"
    if [ "$EXTERNAL_CA" = "true" ]; then
        echo "  - Certificates: External CA (user-provided)"
    else
        echo "  - Certificates: Self-signed (auto-generated)"
    fi
    if [ "$CUSTOM_PASSWORDS" = "true" ]; then
        echo "  - Passwords: Custom (user-provided)"
    else
        echo "  - Passwords: Auto-generated"
    fi

    echo
    echo -e "${CYAN}Security Features Enabled:${NC}"
    [ "$ENABLE_VULN_DETECTION" = "true" ] && echo "  - Vulnerability Detection"
    [ "$ENABLE_FIM" = "true" ] && echo "  - File Integrity Monitoring"
    [ "$ENABLE_ROOTKIT" = "true" ] && echo "  - Rootkit Detection"
    [ "${ENABLE_SCA:-true}" = "true" ] && echo "  - Security Configuration Assessment (SCA)"
    [ "${ENABLE_SYSCOLLECTOR:-true}" = "true" ] && echo "  - System Inventory (Syscollector)"
    [ "$ENABLE_LOG_COLLECTION" = "true" ] && echo "  - Log Collection"
    [ "$ENABLE_ACTIVE_RESPONSE" = "true" ] && echo "  - Active Response"

    echo
    echo -e "${CYAN}Alerting & Integrations:${NC}"
    if [ "$ENABLE_EMAIL_ALERTS" = "true" ]; then
        echo "  - Email Alerts: ${EMAIL_TO} (via ${EMAIL_SMTP_SERVER})"
    fi
    if [ "$ENABLE_SYSLOG_OUTPUT" = "true" ]; then
        echo "  - Syslog Output: ${SYSLOG_SERVER}:${SYSLOG_PORT} (${SYSLOG_FORMAT})"
    fi
    if [ "$ENABLE_SLACK" = "true" ]; then
        echo "  - Slack Notifications (level >= ${SLACK_ALERT_LEVEL})"
    fi
    if [ "$ENABLE_VIRUSTOTAL" = "true" ]; then
        echo "  - VirusTotal Integration"
    fi
    if [ "$ENABLE_EMAIL_ALERTS" != "true" ] && [ "$ENABLE_SYSLOG_OUTPUT" != "true" ] && \
       [ "$ENABLE_SLACK" != "true" ] && [ "$ENABLE_VIRUSTOTAL" != "true" ]; then
        echo "  - None configured (alerts will only appear in Wazuh Dashboard)"
    fi

    echo
    echo -e "${CYAN}Backup & Maintenance:${NC}"
    case "${BACKUP_SCHEDULE:-daily}" in
        daily)
            echo "  - Automated Backups: Daily at ${BACKUP_HOUR:-2}:00, keep ${BACKUP_RETENTION:-7} backups"
            ;;
        weekly)
            DAYS=("Sunday" "Monday" "Tuesday" "Wednesday" "Thursday" "Friday" "Saturday")
            echo "  - Automated Backups: Weekly on ${DAYS[${BACKUP_DAY:-0}]} at ${BACKUP_HOUR:-2}:00, keep ${BACKUP_RETENTION:-7} backups"
            ;;
        disabled)
            echo "  - Automated Backups: Disabled (manual only)"
            ;;
    esac
    if [ "${ENABLE_LOG_CLEANUP:-true}" = "true" ]; then
        echo "  - Log Cleanup: ${LOG_CLEANUP_SCHEDULE:-daily}, keep ${LOG_RETENTION_DAYS:-30} days"
    else
        echo "  - Log Cleanup: Disabled"
    fi

    print_header "Next Steps"

    echo -e "1. Review the generated configuration files:"
    echo -e "   ${CYAN}inventory/hosts.yml${NC}    - Inventory file"
    echo -e "   ${CYAN}group_vars/all/main.yml${NC}     - Variables file"
    echo -e "   ${CYAN}group_vars/all/vault.yml${NC} - Encrypted credentials"
    echo -e "   ${CYAN}ansible.cfg${NC}            - Ansible configuration"
    echo -e "   ${CYAN}.vault_password${NC}        - Vault encryption key (KEEP SECURE!)"
    echo

    if [ "$CREATE_PREP_PACKAGE" = "true" ]; then
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
    echo -e "   ${YELLOW}ansible all -m ping${NC}"
    echo

    if [ "$CREATE_PREP_PACKAGE" = "true" ]; then
        echo -e "4. Run the deployment:"
    else
        echo -e "3. Run the deployment:"
    fi
    echo -e "   ${YELLOW}ansible-playbook site.yml${NC}"
    echo
    echo -e "   Or deploy components individually:"
    echo -e "   ${YELLOW}ansible-playbook playbooks/wazuh-indexer.yml${NC}"
    echo -e "   ${YELLOW}ansible-playbook playbooks/wazuh-manager.yml${NC}"
    echo -e "   ${YELLOW}ansible-playbook playbooks/wazuh-dashboard.yml${NC}"
    echo -e "   ${YELLOW}ansible-playbook playbooks/wazuh-agents.yml${NC}"
    echo

    if [ "$CREATE_PREP_PACKAGE" = "true" ]; then
        echo -e "5. After deployment, view your credentials:"
    else
        echo -e "4. After deployment, view your credentials:"
    fi
    echo -e "   ${YELLOW}./scripts/manage-vault.sh view${NC}"
    echo

    if [ "$CREATE_PREP_PACKAGE" = "true" ]; then
        echo -e "6. Certificate management:"
    else
        echo -e "5. Certificate management:"
    fi
    echo -e "   ${YELLOW}ansible-playbook playbooks/certificate-management.yml --tags check-expiry${NC}"
    echo -e "   ${YELLOW}ansible-playbook playbooks/certificate-management.yml --tags rotate${NC}"
    echo

    if [ "$GENERATE_SSH_KEY" = "true" ]; then
        print_header "SSH Key Information"
        echo -e "SSH keys have been generated for Ansible deployment:"
        echo -e "  Private key: ${CYAN}${ANSIBLE_SSH_KEY}${NC}"
        echo -e "  Public key:  ${CYAN}${ANSIBLE_SSH_KEY}.pub${NC}"
        echo
        echo -e "${YELLOW}Keep the private key secure! It provides access to all managed hosts.${NC}"
        echo
    fi

    print_header "Credential Management"
    echo -e "Manage encrypted credentials with:"
    echo -e "  ${YELLOW}./scripts/manage-vault.sh view${NC}    - View current credentials"
    echo -e "  ${YELLOW}./scripts/manage-vault.sh edit${NC}    - Edit credentials"
    echo -e "  ${YELLOW}./scripts/manage-vault.sh rotate${NC}  - Rotate all credentials"
    echo -e "  ${YELLOW}./scripts/manage-vault.sh rekey${NC}   - Change vault password"
    echo

    print_warning "SECURITY REMINDERS:"
    echo -e "  - Back up ${CYAN}.vault_password${NC} securely (required to decrypt credentials)"
    echo -e "  - Keep ${CYAN}keys/wazuh_ansible_key${NC} private (provides host access)"
    echo

    # Display vault password prominently
    if [ -f "$SCRIPT_DIR/.vault_password" ]; then
        print_header "CRITICAL: SAVE YOUR VAULT PASSWORD"
        echo -e "${RED}════════════════════════════════════════════════════════════════${NC}"
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

    # Display admin credentials
    print_header "WAZUH ADMIN CREDENTIALS"
    echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  SAVE THESE CREDENTIALS - THEY ARE STORED IN THE VAULT${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
    echo
    echo -e "  ${CYAN}Wazuh Dashboard / Indexer Admin:${NC}"
    echo -e "    Username: ${YELLOW}${INDEXER_ADMIN_USER}${NC}"
    echo -e "    Password: ${YELLOW}${GENERATED_INDEXER_PASSWORD}${NC}"
    echo
    echo -e "  ${CYAN}Wazuh API:${NC}"
    echo -e "    Username: ${YELLOW}${API_USER}${NC}"
    echo -e "    Password: ${YELLOW}${GENERATED_API_PASSWORD}${NC}"
    echo
    echo -e "  ${CYAN}Dashboard URL:${NC} https://${DASHBOARD_NODES_ARRAY[0]}:${DASHBOARD_PORT}"
    echo -e "  ${CYAN}API URL:${NC} https://${MANAGER_NODES_ARRAY[0]}:${MANAGER_API_PORT}"
    echo
    echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}⚠ These credentials are encrypted in the vault.${NC}"
    echo -e "${YELLOW}⚠ Use './scripts/manage-vault.sh view' to see them later.${NC}"
    echo -e "${GREEN}════════════════════════════════════════════════════════════════${NC}"
    echo

    print_success "Setup complete!"
}

# Run main function
main "$@"
