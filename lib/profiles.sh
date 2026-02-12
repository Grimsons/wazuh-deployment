#!/bin/bash
# Wazuh Deployment - Deployment Profiles
# Provides predefined configurations for common deployment scenarios

# Source dependencies (use local var to avoid overwriting parent's SCRIPT_DIR)
_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -z "$NC" ]] && source "$_LIB_DIR/colors.sh"

# Available profiles
declare -A PROFILES
PROFILES["minimal"]="Single-node setup for testing/development"
PROFILES["production"]="Multi-node HA setup with all security features"
PROFILES["custom"]="Full interactive configuration"

# Get profile description
get_profile_description() {
    local profile="$1"
    echo "${PROFILES[$profile]:-Unknown profile}"
}

# List available profiles
list_profiles() {
    echo -e "${CYAN}Available Deployment Profiles:${NC}"
    echo
    for profile in "${!PROFILES[@]}"; do
        printf "  ${YELLOW}%-12s${NC} - %s\n" "$profile" "${PROFILES[$profile]}"
    done
    echo
}

# Apply minimal profile defaults
apply_profile_minimal() {
    print_info "Applying MINIMAL profile (single-node testing/development)"
    echo

    # Single node for everything
    INDEXER_NODES="localhost"
    MANAGER_NODES="localhost"
    DASHBOARD_NODES="localhost"
    AGENT_NODES=""
    DEPLOY_AGENTS="false"

    # Basic settings
    WAZUH_VERSION="${WAZUH_VERSION:-4.14.1}"
    ENVIRONMENT="development"
    ORG_NAME="TestOrg"

    # Network
    INDEXER_HTTP_PORT="9200"
    INDEXER_CLUSTER_NAME="wazuh-dev"
    INDEXER_HEAP_SIZE="auto"
    MANAGER_API_PORT="55000"
    AGENT_PORT="1514"
    DASHBOARD_PORT="443"

    # Security - auto-generate everything
    CUSTOM_PASSWORDS="false"
    API_USER="wazuh"
    INDEXER_ADMIN_USER="admin"

    # Certificates - self-signed
    USE_SELF_SIGNED_CERTS="true"
    GENERATE_CERTS="true"
    EXTERNAL_CA="false"

    # SSH - local connection
    GENERATE_SSH_KEY="false"
    ANSIBLE_USER="$(whoami)"
    ANSIBLE_SSH_PORT="22"
    USE_BECOME="true"
    SAME_SSH_CREDS="true"
    INITIAL_SSH_USER="$(whoami)"

    # Features - minimal set
    ENABLE_VULN_DETECTION="true"
    ENABLE_FIM="true"
    ENABLE_ROOTKIT="true"
    ENABLE_SCA="true"
    ENABLE_SYSCOLLECTOR="true"
    ENABLE_LOG_COLLECTION="true"
    ENABLE_ACTIVE_RESPONSE="false"

    # Integrations - disabled
    ENABLE_EMAIL_ALERTS="false"
    ENABLE_SYSLOG_OUTPUT="false"
    ENABLE_SLACK="false"
    ENABLE_VIRUSTOTAL="false"

    # Backup - minimal
    BACKUP_SCHEDULE="disabled"
    ENABLE_LOG_CLEANUP="true"
    LOG_RETENTION_DAYS="7"

    # Client prep
    CREATE_PREP_PACKAGE="false"

    print_success "Minimal profile applied"
}

# Apply production profile defaults
apply_profile_production() {
    print_info "Applying PRODUCTION profile (multi-node HA setup)"
    echo

    # Will prompt for nodes
    INDEXER_NODES=""
    MANAGER_NODES=""
    DASHBOARD_NODES=""
    AGENT_NODES=""

    # Production settings
    WAZUH_VERSION="${WAZUH_VERSION:-4.14.1}"
    ENVIRONMENT="production"
    ORG_NAME="${ORG_NAME:-MyOrganization}"

    # Network - defaults
    INDEXER_HTTP_PORT="9200"
    INDEXER_CLUSTER_NAME="wazuh-cluster"
    INDEXER_HEAP_SIZE="auto"
    MANAGER_API_PORT="55000"
    AGENT_PORT="1514"
    DASHBOARD_PORT="443"

    # Security - auto-generate
    CUSTOM_PASSWORDS="false"
    API_USER="wazuh"
    INDEXER_ADMIN_USER="admin"

    # Certificates - self-signed (can override)
    USE_SELF_SIGNED_CERTS="true"
    GENERATE_CERTS="true"
    EXTERNAL_CA="false"

    # SSH - will generate key
    GENERATE_SSH_KEY="true"
    ANSIBLE_USER="wazuh-deploy"
    ANSIBLE_SSH_PORT="22"
    USE_BECOME="true"
    SAME_SSH_CREDS="true"

    # Features - all enabled
    ENABLE_VULN_DETECTION="true"
    ENABLE_FIM="true"
    ENABLE_ROOTKIT="true"
    ENABLE_SCA="true"
    ENABLE_SYSCOLLECTOR="true"
    ENABLE_LOG_COLLECTION="true"
    ENABLE_ACTIVE_RESPONSE="true"

    # Integrations - prompt for these
    ENABLE_EMAIL_ALERTS="false"
    ENABLE_SYSLOG_OUTPUT="false"
    ENABLE_SLACK="false"
    ENABLE_VIRUSTOTAL="false"

    # Backup - daily
    BACKUP_SCHEDULE="daily"
    BACKUP_HOUR="2"
    BACKUP_RETENTION="7"
    ENABLE_LOG_CLEANUP="true"
    LOG_RETENTION_DAYS="30"
    LOG_CLEANUP_SCHEDULE="daily"

    # Client prep
    CREATE_PREP_PACKAGE="true"

    print_success "Production profile applied"
}

# Apply custom profile (no defaults, full interactive)
apply_profile_custom() {
    print_info "Custom profile - all options will be prompted"
    # Don't set any defaults, let the interactive prompts handle everything
}

# Apply selected profile
apply_profile() {
    local profile="$1"

    case "$profile" in
        minimal)
            apply_profile_minimal
            ;;
        production)
            apply_profile_production
            ;;
        custom)
            apply_profile_custom
            ;;
        *)
            print_error "Unknown profile: $profile"
            return 1
            ;;
    esac
}

# Prompt for profile selection
select_profile() {
    local var_name="${1:-SELECTED_PROFILE}"

    print_header "Select Deployment Profile"

    echo -e "${CYAN}Choose a deployment profile to get started quickly:${NC}"
    echo
    echo -e "  ${YELLOW}1)${NC} ${BOLD}minimal${NC}     - Single-node setup for testing/development"
    echo -e "                   All components on localhost, minimal features"
    echo
    echo -e "  ${YELLOW}2)${NC} ${BOLD}production${NC}  - Multi-node HA setup with all security features"
    echo -e "                   Prompts for node IPs, enables all features"
    echo
    echo -e "  ${YELLOW}3)${NC} ${BOLD}custom${NC}      - Full interactive configuration"
    echo -e "                   Configure every option manually"
    echo

    local selection=""
    while true; do
        read -erp "$(echo -e "${CYAN}Select profile ${NC}[${YELLOW}2${NC}]: ")" selection

        if [[ -z "$selection" ]]; then
            selection="2"
        fi

        case "$selection" in
            1|minimal)
                set_var "$var_name" "minimal"
                return 0
                ;;
            2|production)
                set_var "$var_name" "production"
                return 0
                ;;
            3|custom)
                set_var "$var_name" "custom"
                return 0
                ;;
            *)
                print_error "Invalid selection. Please enter 1, 2, or 3"
                ;;
        esac
    done
}

# Check if running in quick mode (non-interactive with profile)
is_quick_mode() {
    [[ -n "${PROFILE:-}" && "${PROFILE}" != "custom" ]]
}

# Skip prompt if value already set (for profile mode)
skip_if_set() {
    local var_name="$1"
    local -n var_ref="$var_name"
    [[ -n "${var_ref:-}" ]]
}
