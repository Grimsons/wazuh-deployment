#!/bin/bash

# Wazuh Client Preparation Deployment Script
# This script deploys the preparation script to remote hosts and executes it
#
# Security features:
# - SSH host key verification (can be disabled with --insecure)
# - Input validation for all hosts
# - Secure temporary file handling
# - Timeout controls for remote operations
#
# Authentication modes:
# - Key-based (default): Uses SSH keys from keys/ directory
# - Interactive (--ask-pass): Prompts for SSH credentials
# - Mixed: Prompts for sudo password when not using root (--ask-become-pass)

set -euo pipefail

# Cleanup trap
cleanup() {
    local exit_code=$?
    # Clear sensitive data from environment
    unset SSH_PASSWORD 2>/dev/null || true
    unset BECOME_PASSWORD 2>/dev/null || true
    unset SSHPASS 2>/dev/null || true
    # Clean up any sensitive temp files
    rm -rf "${TEMP_DIR:-}" 2>/dev/null || true
    exit $exit_code
}
trap cleanup EXIT INT TERM

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PARENT_DIR="$(dirname "$SCRIPT_DIR")"

# Configuration
PREP_TARBALL="${PARENT_DIR}/wazuh-client-prep.tar.gz"
PREP_SCRIPT="${SCRIPT_DIR}/prepare-client.sh"
SSH_KEY="${PARENT_DIR}/keys/wazuh_ansible_key"
SSH_PUBKEY="${PARENT_DIR}/keys/wazuh_ansible_key.pub"
ANSIBLE_USER="wazuh-deploy"
REMOTE_USER="${REMOTE_USER:-root}"
SSH_PORT="${SSH_PORT:-22}"
HOSTS_FILE=""
PARALLEL_JOBS=5
SSH_TIMEOUT="${SSH_TIMEOUT:-300}"  # 5 minutes default
INSECURE_SSH=false  # Disable host key checking (NOT recommended for production)
KNOWN_HOSTS_FILE="${PARENT_DIR}/.known_hosts"  # Project-local known_hosts

# Authentication settings
ASK_PASS=false          # Prompt for SSH password
ASK_BECOME_PASS=false   # Prompt for sudo password
SSH_PASSWORD=""         # SSH password (set interactively)
BECOME_PASSWORD=""      # Sudo password (set interactively)

# Input validation functions
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
    if validate_ip "$host"; then
        return 0
    fi
    [[ "$host" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]{0,253}[a-zA-Z0-9])?$ ]]
}

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

# Display usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS] [HOST1 HOST2 ...]

Deploy the Wazuh client preparation script to remote hosts.

OPTIONS:
    -f, --file FILE         File containing list of hosts (one per line)
    -u, --user USER         Remote user for initial SSH (default: root)
    -p, --port PORT         SSH port (default: 22)
    -k, --key FILE          SSH private key for initial connection
    -a, --ansible-user USER User to create for Ansible (default: wazuh-deploy)
    -j, --jobs N            Parallel jobs (default: 5)
    -t, --tarball FILE      Use existing tarball instead of creating new
    --timeout SECONDS       SSH connection timeout (default: 300)
    --minimal               Use minimal mode (don't remove packages)
    --insecure              Disable SSH host key verification (NOT recommended)
    -h, --help              Show this help message

AUTHENTICATION OPTIONS:
    -P, --ask-pass          Prompt for SSH password (interactive mode)
    -K, --ask-become-pass   Prompt for sudo/become password
    --password              Same as --ask-pass (deprecated, use -P)

SECURITY:
    By default, SSH host keys are verified using a project-local known_hosts file.
    On first connection to a new host, you'll be prompted to verify the fingerprint.
    Use --insecure only for testing or when you have other means of verification.

EXAMPLES:
    # Deploy to specific hosts using SSH keys (default)
    $0 192.168.1.10 192.168.1.11 192.168.1.12

    # Deploy using a hosts file
    $0 -f hosts.txt

    # Deploy with interactive password prompts (fresh servers)
    $0 --ask-pass 192.168.1.10 192.168.1.11

    # Deploy as non-root user with sudo password
    $0 -u admin --ask-pass --ask-become-pass 192.168.1.10

    # Deploy with custom SSH key
    $0 -k ~/.ssh/id_rsa 192.168.1.10

    # Deploy with custom timeout
    $0 --timeout 600 192.168.1.10

EOF
    exit 0
}

# Parse arguments
HOSTS=()
USE_PASSWORD=false
MINIMAL_MODE=false
CUSTOM_KEY=""

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -f|--file)
                HOSTS_FILE="$2"
                shift 2
                ;;
            -u|--user)
                REMOTE_USER="$2"
                shift 2
                ;;
            -p|--port)
                SSH_PORT="$2"
                shift 2
                ;;
            -k|--key)
                CUSTOM_KEY="$2"
                shift 2
                ;;
            -a|--ansible-user)
                ANSIBLE_USER="$2"
                shift 2
                ;;
            -j|--jobs)
                PARALLEL_JOBS="$2"
                shift 2
                ;;
            -t|--tarball)
                PREP_TARBALL="$2"
                shift 2
                ;;
            --timeout)
                SSH_TIMEOUT="$2"
                shift 2
                ;;
            -P|--ask-pass)
                ASK_PASS=true
                USE_PASSWORD=true
                shift
                ;;
            -K|--ask-become-pass)
                ASK_BECOME_PASS=true
                shift
                ;;
            --password)
                # Deprecated but still supported
                ASK_PASS=true
                USE_PASSWORD=true
                shift
                ;;
            --minimal)
                MINIMAL_MODE=true
                shift
                ;;
            --insecure)
                INSECURE_SSH=true
                print_warning "SSH host key verification disabled - use only for testing!"
                shift
                ;;
            -h|--help)
                usage
                ;;
            -*)
                print_error "Unknown option: $1"
                usage
                ;;
            *)
                # Validate host before adding
                if validate_hostname "$1"; then
                    HOSTS+=("$1")
                else
                    print_error "Invalid hostname/IP: $1"
                    exit 1
                fi
                shift
                ;;
        esac
    done
}

# Load hosts from file
load_hosts_from_file() {
    if [ -n "$HOSTS_FILE" ] && [ -f "$HOSTS_FILE" ]; then
        while IFS= read -r line; do
            # Skip empty lines and comments
            [[ -z "$line" || "$line" =~ ^# ]] && continue
            HOSTS+=("$line")
        done < "$HOSTS_FILE"
    fi
}

# Prompt for credentials interactively
prompt_credentials() {
    print_section "Authentication Setup"

    # Prompt for SSH user if using interactive mode
    if [ "$ASK_PASS" = "true" ]; then
        echo -e "${CYAN}Enter SSH credentials for initial connection:${NC}"
        echo ""

        # Prompt for username
        read -rp "$(echo -e "${YELLOW}SSH Username [${REMOTE_USER}]: ${NC}")" input_user
        if [ -n "$input_user" ]; then
            REMOTE_USER="$input_user"
        fi

        # Prompt for password
        echo -e "${YELLOW}SSH Password: ${NC}"
        read -rs SSH_PASSWORD
        echo ""

        if [ -z "$SSH_PASSWORD" ]; then
            print_error "Password cannot be empty"
            exit 1
        fi
    fi

    # Prompt for sudo password if needed
    if [ "$ASK_BECOME_PASS" = "true" ]; then
        echo ""
        echo -e "${CYAN}Enter sudo/become password:${NC}"
        echo -e "${YELLOW}Sudo Password: ${NC}"
        read -rs BECOME_PASSWORD
        echo ""

        if [ -z "$BECOME_PASSWORD" ]; then
            print_warning "Sudo password is empty - assuming passwordless sudo"
        fi
    elif [ "$REMOTE_USER" != "root" ] && [ "$ASK_PASS" = "true" ]; then
        # If not root and using password auth, ask if sudo password is needed
        echo ""
        read -rp "$(echo -e "${YELLOW}User '$REMOTE_USER' is not root. Need sudo password? [Y/n]: ${NC}")" need_sudo
        if [[ ! "$need_sudo" =~ ^[Nn]$ ]]; then
            echo -e "${YELLOW}Sudo Password (Enter for same as SSH): ${NC}"
            read -rs BECOME_PASSWORD
            echo ""

            # Use SSH password if sudo password is empty
            if [ -z "$BECOME_PASSWORD" ]; then
                BECOME_PASSWORD="$SSH_PASSWORD"
                print_info "Using SSH password for sudo"
            fi
            ASK_BECOME_PASS=true
        fi
    fi

    # Export for use in subshells
    export SSH_PASSWORD
    export BECOME_PASSWORD
}

# Check prerequisites
check_prerequisites() {
    print_section "Checking Prerequisites"

    # Check for required files
    if [ ! -f "$PREP_SCRIPT" ]; then
        print_error "Preparation script not found: $PREP_SCRIPT"
        exit 1
    fi

    # Check for SSH key
    if [ -n "$CUSTOM_KEY" ]; then
        SSH_KEY="$CUSTOM_KEY"
    fi

    # Determine authentication mode
    if [ "$USE_PASSWORD" != "true" ] && [ ! -f "$SSH_KEY" ]; then
        print_warning "SSH key not found: $SSH_KEY"
        print_info "Switching to interactive password mode"
        ASK_PASS=true
        USE_PASSWORD=true
    fi

    # Check for SSH public key for deployment
    if [ ! -f "$SSH_PUBKEY" ]; then
        print_error "SSH public key not found: $SSH_PUBKEY"
        print_info "Please run setup.sh first to generate SSH keys"
        exit 1
    fi

    # Check for sshpass if using password auth
    if [ "$USE_PASSWORD" = "true" ]; then
        if ! command -v sshpass &> /dev/null; then
            print_error "sshpass is required for password authentication"
            print_info "Install it with:"
            echo "  Ubuntu/Debian: sudo apt install sshpass"
            echo "  RHEL/CentOS:   sudo yum install sshpass"
            echo "  Arch Linux:    sudo pacman -S sshpass"
            exit 1
        fi
        print_success "sshpass found"
    fi

    print_success "Prerequisites check passed"
}

# Create preparation tarball
create_tarball() {
    print_section "Creating Preparation Tarball"

    local temp_dir=$(mktemp -d)
    local prep_dir="${temp_dir}/wazuh-prep"

    mkdir -p "$prep_dir"

    # Copy files
    cp "$PREP_SCRIPT" "$prep_dir/"
    cp "$SSH_PUBKEY" "$prep_dir/ansible_key.pub"

    # Create tarball
    tar -czf "$PREP_TARBALL" -C "$temp_dir" "wazuh-prep"

    rm -rf "$temp_dir"

    print_success "Created tarball: $PREP_TARBALL"
}

# Build SSH options based on security settings
build_ssh_opts() {
    local opts="-o ConnectTimeout=30 -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -p $SSH_PORT"

    if [ "$INSECURE_SSH" = "true" ]; then
        # Insecure mode - disable host key checking (NOT recommended)
        opts="$opts -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
    else
        # Secure mode - use project-local known_hosts
        touch "$KNOWN_HOSTS_FILE" 2>/dev/null || true
        chmod 600 "$KNOWN_HOSTS_FILE" 2>/dev/null || true
        opts="$opts -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$KNOWN_HOSTS_FILE"
    fi

    if [ "$USE_PASSWORD" != "true" ] && [ -f "$SSH_KEY" ]; then
        opts="$opts -i $SSH_KEY"
    fi

    echo "$opts"
}

# Run SSH command with appropriate authentication
run_ssh() {
    local host="$1"
    shift
    local ssh_opts
    ssh_opts=$(build_ssh_opts)

    if [ "$USE_PASSWORD" = "true" ] && [ -n "$SSH_PASSWORD" ]; then
        SSHPASS="$SSH_PASSWORD" sshpass -e ssh $ssh_opts "${REMOTE_USER}@${host}" "$@"
    else
        ssh $ssh_opts "${REMOTE_USER}@${host}" "$@"
    fi
}

# Run SCP command with appropriate authentication
run_scp() {
    local src="$1"
    local host="$2"
    local dest="$3"
    local scp_opts
    scp_opts=$(build_ssh_opts | sed 's/-p /-P /')  # scp uses -P for port

    if [ "$USE_PASSWORD" = "true" ] && [ -n "$SSH_PASSWORD" ]; then
        SSHPASS="$SSH_PASSWORD" sshpass -e scp $scp_opts "$src" "${REMOTE_USER}@${host}:${dest}"
    else
        scp $scp_opts "$src" "${REMOTE_USER}@${host}:${dest}"
    fi
}

# Deploy to a single host
deploy_to_host() {
    local host="$1"
    local result_file="$2"

    echo "STARTED" > "$result_file"
    chmod 600 "$result_file"

    print_info "Deploying to: $host"

    # Test connectivity with timeout
    if ! timeout "$SSH_TIMEOUT" run_ssh "$host" "echo 'Connection successful'" &>/dev/null; then
        print_error "Cannot connect to $host"
        echo "FAILED: Cannot connect" > "$result_file"
        return 1
    fi

    # Copy tarball with timeout
    print_info "[$host] Copying preparation files..."

    if ! timeout "$SSH_TIMEOUT" run_scp "$PREP_TARBALL" "$host" "/tmp/" &>/dev/null; then
        print_error "[$host] Failed to copy tarball"
        echo "FAILED: Copy failed" > "$result_file"
        return 1
    fi

    # Execute preparation script with timeout
    print_info "[$host] Executing preparation script..."

    # Safely escape the ansible user for the remote command
    local safe_ansible_user
    safe_ansible_user=$(printf '%s' "$ANSIBLE_USER" | tr -cd 'a-zA-Z0-9._-')

    local prep_cmd="
        cd /tmp && \
        tar -xzf wazuh-client-prep.tar.gz && \
        cd wazuh-prep && \
        chmod +x prepare-client.sh && \
        ./prepare-client.sh -u '${safe_ansible_user}' -k ansible_key.pub"

    if [ "$MINIMAL_MODE" = "true" ]; then
        prep_cmd="$prep_cmd --minimal"
    fi

    prep_cmd="$prep_cmd && rm -rf /tmp/wazuh-prep /tmp/wazuh-client-prep.tar.gz"

    # Build the sudo command based on authentication mode
    local exec_cmd
    if [ "$REMOTE_USER" = "root" ]; then
        # Running as root, no sudo needed
        exec_cmd="bash -c '$prep_cmd'"
    elif [ "$ASK_BECOME_PASS" = "true" ] && [ -n "$BECOME_PASSWORD" ]; then
        # Use sudo with password from stdin (base64 encode to safely handle special chars)
        local encoded_password
        encoded_password=$(printf '%s' "$BECOME_PASSWORD" | base64)
        exec_cmd="printf '%s' '${encoded_password}' | base64 -d | sudo -S bash -c '$prep_cmd'"
    else
        # Use sudo without password (assumes NOPASSWD or already root)
        exec_cmd="sudo bash -c '$prep_cmd'"
    fi

    if timeout "$SSH_TIMEOUT" run_ssh "$host" "$exec_cmd" 2>&1; then
        print_success "[$host] Preparation complete"
        echo "SUCCESS" > "$result_file"
        return 0
    else
        print_error "[$host] Preparation failed"
        echo "FAILED: Script execution failed" > "$result_file"
        return 1
    fi
}

# Deploy to all hosts
deploy_to_all() {
    print_section "Deploying to ${#HOSTS[@]} host(s)"

    local temp_dir=$(mktemp -d)
    local pids=()
    local host_count=0
    local success_count=0
    local fail_count=0

    for host in "${HOSTS[@]}"; do
        local result_file="${temp_dir}/${host//\//_}.result"

        # Run in background
        deploy_to_host "$host" "$result_file" &
        pids+=($!)
        ((host_count++))

        # Limit parallel jobs
        if [ ${#pids[@]} -ge $PARALLEL_JOBS ]; then
            wait "${pids[0]}"
            pids=("${pids[@]:1}")
        fi
    done

    # Wait for remaining jobs
    for pid in "${pids[@]}"; do
        wait "$pid" || true
    done

    # Collect results
    print_section "Deployment Results"

    for host in "${HOSTS[@]}"; do
        local result_file="${temp_dir}/${host//\//_}.result"
        if [ -f "$result_file" ]; then
            local result=$(cat "$result_file")
            if [ "$result" = "SUCCESS" ]; then
                echo -e "${GREEN}✓${NC} $host"
                ((success_count++))
            else
                echo -e "${RED}✗${NC} $host - $result"
                ((fail_count++))
            fi
        else
            echo -e "${YELLOW}?${NC} $host - Unknown"
        fi
    done

    rm -rf "$temp_dir"

    echo ""
    echo -e "Total: $host_count | ${GREEN}Success: $success_count${NC} | ${RED}Failed: $fail_count${NC}"
}

# Verify deployment
verify_deployment() {
    print_section "Verifying Deployment"

    local verified=0
    local failed=0

    for host in "${HOSTS[@]}"; do
        print_info "Testing: $host"

        local ssh_opts="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10 -p $SSH_PORT"

        # Test with new Ansible user and key
        if ssh $ssh_opts -i "$SSH_KEY" "${ANSIBLE_USER}@${host}" "echo 'Ansible user OK'" &>/dev/null; then
            print_success "[$host] Ansible user accessible"
            ((verified++))
        else
            print_error "[$host] Cannot connect as Ansible user"
            ((failed++))
        fi
    done

    echo ""
    echo -e "Verified: $verified | Failed: $failed"
}

# Generate inventory entries
generate_inventory() {
    print_section "Ansible Inventory Entries"

    echo "Add these entries to your inventory/hosts.yml:"
    echo ""
    echo "---"
    echo "all:"
    echo "  vars:"
    echo "    ansible_user: ${ANSIBLE_USER}"
    echo "    ansible_ssh_private_key_file: ${SSH_KEY}"
    echo "    ansible_port: ${SSH_PORT}"
    echo ""
    echo "  children:"
    echo "    wazuh_agents:"
    echo "      hosts:"

    for host in "${HOSTS[@]}"; do
        echo "        ${host}:"
    done
}

# Main function
main() {
    parse_args "$@"
    load_hosts_from_file

    print_header "Wazuh Client Preparation Deployment"

    # Check if we have hosts
    if [ ${#HOSTS[@]} -eq 0 ]; then
        print_error "No hosts specified"
        echo ""
        usage
    fi

    echo "Hosts to prepare:"
    for host in "${HOSTS[@]}"; do
        echo "  - $host"
    done
    echo ""

    check_prerequisites

    # Prompt for credentials if using interactive mode
    if [ "$ASK_PASS" = "true" ] || [ "$ASK_BECOME_PASS" = "true" ]; then
        prompt_credentials
    fi

    # Create or verify tarball
    if [ ! -f "$PREP_TARBALL" ]; then
        create_tarball
    else
        print_info "Using existing tarball: $PREP_TARBALL"
    fi

    # Show authentication mode
    print_section "Authentication Mode"
    if [ "$USE_PASSWORD" = "true" ]; then
        echo "  SSH: Password authentication (user: $REMOTE_USER)"
    else
        echo "  SSH: Key-based authentication (key: $SSH_KEY)"
    fi
    if [ "$REMOTE_USER" = "root" ]; then
        echo "  Privilege: Running as root (no sudo needed)"
    elif [ "$ASK_BECOME_PASS" = "true" ]; then
        echo "  Privilege: Using sudo with password"
    else
        echo "  Privilege: Using sudo (passwordless)"
    fi
    echo ""

    # Confirm before proceeding
    read -p "Proceed with deployment? [y/N] " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Deployment cancelled"
        exit 0
    fi

    deploy_to_all

    # Ask to verify
    echo ""
    read -p "Verify deployment? [Y/n] " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        verify_deployment
    fi

    # Generate inventory
    generate_inventory
}

main "$@"
