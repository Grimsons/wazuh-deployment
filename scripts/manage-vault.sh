#!/bin/bash

# Wazuh Deployment - Ansible Vault Management Script
# Manages encrypted credentials for secure deployment

set -euo pipefail

# Ensure plaintext temp files are cleaned up on exit/interrupt
trap 'rm -f "${VAULT_FILE:-}.tmp" "${VAULT_PASSWORD_FILE:-}.new"' EXIT INT TERM

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
# Use group_vars/all/ directory structure for proper Ansible auto-loading
VAULT_DIR="$PROJECT_DIR/group_vars/all"
VAULT_FILE="$VAULT_DIR/vault.yml"
VAULT_PASSWORD_FILE="$PROJECT_DIR/.vault_password"
CREDENTIALS_DIR="$PROJECT_DIR/credentials"

print_header() {
    echo -e "\n${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}\n"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}ℹ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

# Escape a string for safe interpolation into a double-quoted YAML scalar.
# Escapes backslashes, double-quotes, and rejects embedded newlines.
yaml_escape() {
    local s="$1"
    if [[ "$s" == *$'\n'* ]]; then
        print_error "yaml_escape: value contains a newline — refusing to interpolate"
        return 1
    fi
    s="${s//\\/\\\\}"   # backslash first
    s="${s//\"/\\\"}"   # then double-quote
    printf '%s' "$s"
}

# Generate a secure random password of exactly the requested length
generate_password() {
    local length="${1:-24}"
    # Reserve 4 characters for mandatory complexity chars; fill the rest randomly.
    # Exclude YAML-breaking characters: ! # $ { } [ ] : , & * ? | > ' " ` %
    local base_len=$(( length - 4 ))
    [[ "$base_len" -lt 1 ]] && base_len=1
    local password
    password=$(LC_ALL=C tr -dc 'A-Za-z0-9@^_+=-' < /dev/urandom | head -c "$base_len")
    local upper lower number symbol symbols
    upper=$(LC_ALL=C tr -dc 'A-Z' < /dev/urandom | head -c 1)
    lower=$(LC_ALL=C tr -dc 'a-z' < /dev/urandom | head -c 1)
    number=$(LC_ALL=C tr -dc '0-9' < /dev/urandom | head -c 1)
    symbols='@^_+-='
    local symbol_idx
    symbol_idx=$(head -c 4 /dev/urandom | od -An -tu4 | tr -d ' \n')
    symbol="${symbols:$((symbol_idx % ${#symbols})):1}"
    printf '%s%s%s%s%s' "$password" "$upper" "$lower" "$number" "$symbol" | fold -w1 | shuf | tr -d '\n'
    printf '\n'
}

# Initialize vault with a new password
init_vault() {
    print_header "Initializing Ansible Vault"

    if [ -f "$VAULT_PASSWORD_FILE" ]; then
        print_warning "Vault password file already exists: $VAULT_PASSWORD_FILE"
        read -p "Overwrite existing vault password? (y/N): " overwrite
        if [[ ! "$overwrite" =~ ^[Yy]$ ]]; then
            print_info "Keeping existing vault password"
            return 0
        fi
    fi

    # Generate vault password
    local vault_password=$(generate_password 32)
    echo "$vault_password" > "$VAULT_PASSWORD_FILE"
    chmod 600 "$VAULT_PASSWORD_FILE"

    print_success "Vault password generated and saved to: $VAULT_PASSWORD_FILE"
    print_warning "IMPORTANT: Back up this file securely! Without it, you cannot decrypt your credentials."

    # Add to .gitignore if not already there
    if ! grep -q ".vault_password" "$PROJECT_DIR/.gitignore" 2>/dev/null; then
        echo ".vault_password" >> "$PROJECT_DIR/.gitignore"
        print_info "Added .vault_password to .gitignore"
    fi
}

# Create or update vault file with credentials.
# Preferred: pass --creds-file <path> (mode-0600 key=value file) to avoid
# leaking secrets via /proc/<pid>/environ.
# Fallback: reads VAULT_* environment variables when no --creds-file is given.
#   VAULT_INDEXER_PASSWORD, VAULT_API_PASSWORD, VAULT_ENROLLMENT_PASSWORD
#   VAULT_ANSIBLE_USER, VAULT_CONNECTION_PASSWORD, VAULT_BECOME_PASSWORD
#   VAULT_HOST_CREDENTIALS (format: "host1:user1:pass1,host2:user2:pass2")
#   VAULT_CLUSTER_KEY
create_vault() {
    local creds_file=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --creds-file)
                creds_file="$2"
                shift 2
                ;;
            *)
                print_error "Unknown argument: $1"
                exit 1
                ;;
        esac
    done

    if [[ -n "$creds_file" ]]; then
        if [[ ! -f "$creds_file" ]]; then
            print_error "Creds file not found: $creds_file"
            exit 1
        fi
        # Source the key=value pairs into the environment of this function only
        local line key value
        while IFS= read -r line || [[ -n "$line" ]]; do
            [[ -z "$line" || "$line" == \#* ]] && continue
            key="${line%%=*}"
            value="${line#*=}"
            # Allow only expected VAULT_* keys to prevent arbitrary code injection
            case "$key" in
                VAULT_INDEXER_PASSWORD|VAULT_API_PASSWORD|VAULT_ENROLLMENT_PASSWORD|\
                VAULT_ANSIBLE_USER|VAULT_CONNECTION_PASSWORD|VAULT_BECOME_PASSWORD|\
                VAULT_HOST_CREDENTIALS|VAULT_CLUSTER_KEY|VAULT_FILEBEAT_PASSWORD)
                    printf -v "$key" '%s' "$value"
                    ;;
                *)
                    print_error "Unexpected key in creds file: $key"
                    exit 1
                    ;;
            esac
        done < "$creds_file"
    fi
    print_header "Creating Encrypted Vault"

    if [ ! -f "$VAULT_PASSWORD_FILE" ]; then
        print_error "Vault password file not found. Run: $0 init"
        exit 1
    fi

    mkdir -p "$VAULT_DIR"

    # Use environment variables if set, otherwise generate new passwords
    local indexer_password="${VAULT_INDEXER_PASSWORD:-}"
    local api_password="${VAULT_API_PASSWORD:-}"
    local enrollment_password="${VAULT_ENROLLMENT_PASSWORD:-}"
    local connection_password="${VAULT_CONNECTION_PASSWORD:-}"
    local become_password="${VAULT_BECOME_PASSWORD:-}"
    local ansible_user="${VAULT_ANSIBLE_USER:-wazuh-deploy}"
    local cluster_key="${VAULT_CLUSTER_KEY:-}"
    local filebeat_password="${VAULT_FILEBEAT_PASSWORD:-}"

    # Generate passwords if not provided
    if [ -z "$indexer_password" ]; then
        indexer_password=$(generate_password 24)
        print_info "Generated new indexer admin password"
    fi

    if [ -z "$api_password" ]; then
        api_password=$(generate_password 24)
        print_info "Generated new API password"
    fi

    if [ -z "$enrollment_password" ]; then
        enrollment_password=$(generate_password 24)
        print_info "Generated new agent enrollment password"
    fi

    if [ -z "$cluster_key" ]; then
        cluster_key=$(generate_password 32)
    fi

    if [ -z "$filebeat_password" ]; then
        filebeat_password=$(generate_password 24)
        print_info "Generated new Filebeat writer password"
    fi

    # Build per-host SSH credentials content
    local host_creds_content=""
    if [ -n "${VAULT_HOST_CREDENTIALS:-}" ]; then
        print_info "Processing per-host SSH credentials"
        IFS=',' read -ra HOST_ENTRIES <<< "$VAULT_HOST_CREDENTIALS"
        for entry in "${HOST_ENTRIES[@]}"; do
            IFS=':' read -r host user pass <<< "$entry"
            if [ -n "$host" ]; then
                local safe_host="${host//./_}"
                # Store username for this host
                if [ -n "$user" ]; then
                    local escaped_user
                    escaped_user="$(yaml_escape "$user")" || exit 1
                    host_creds_content+="
# SSH user for host: ${host}
vault_ssh_user_${safe_host}: \"${escaped_user}\""
                fi
                # Store password for this host
                if [ -n "$pass" ]; then
                    local escaped_pass
                    escaped_pass="$(yaml_escape "$pass")" || exit 1
                    host_creds_content+="
# SSH password for host: ${host}
vault_ssh_pass_${safe_host}: \"${escaped_pass}\""
                fi
            fi
        done
    fi

    # Escape all operator-supplied values before YAML interpolation
    local e_ansible_user e_connection_password e_become_password
    local e_indexer_password e_api_password e_enrollment_password e_cluster_key e_filebeat_password
    e_ansible_user="$(yaml_escape "$ansible_user")"           || exit 1
    e_connection_password="$(yaml_escape "$connection_password")" || exit 1
    e_become_password="$(yaml_escape "$become_password")"     || exit 1
    e_indexer_password="$(yaml_escape "$indexer_password")"   || exit 1
    e_api_password="$(yaml_escape "$api_password")"           || exit 1
    e_enrollment_password="$(yaml_escape "$enrollment_password")" || exit 1
    e_cluster_key="$(yaml_escape "$cluster_key")"             || exit 1
    e_filebeat_password="$(yaml_escape "$filebeat_password")" || exit 1

    # Create vault content
    local vault_content="---
# Wazuh Deployment - Encrypted Credentials
# Generated: $(date -Iseconds)
# DO NOT COMMIT THIS FILE UNENCRYPTED!

# Ansible SSH user for deployment
vault_ansible_user: \"${e_ansible_user}\"

# Ansible connection password (SSH/WinRM) - default for all hosts
vault_ansible_connection_password: \"${e_connection_password}\"

# Ansible become (sudo) password
vault_ansible_become_password: \"${e_become_password}\"
${host_creds_content}

# Indexer/Dashboard admin credentials
vault_wazuh_indexer_admin_password: \"${e_indexer_password}\"

# Wazuh API credentials
vault_wazuh_api_password: \"${e_api_password}\"

# Agent enrollment password
vault_wazuh_agent_enrollment_password: \"${e_enrollment_password}\"

# Manager cluster key (for multi-node deployments)
vault_wazuh_manager_cluster_key: \"${e_cluster_key}\"

# Filebeat writer password (scoped indexer user for alert ingestion)
vault_wazuh_filebeat_password: \"${e_filebeat_password}\"
"

    # Write and encrypt
    echo "$vault_content" > "${VAULT_FILE}.tmp"
    ansible-vault encrypt "${VAULT_FILE}.tmp" --vault-password-file "$VAULT_PASSWORD_FILE" --encrypt-vault-id default --output "$VAULT_FILE"
    rm -f "${VAULT_FILE}.tmp"
    chmod 600 "$VAULT_FILE"

    print_success "Encrypted vault created: $VAULT_FILE"
}

# View vault contents (decrypted)
view_vault() {
    print_header "Vault Contents"

    if [ ! -f "$VAULT_FILE" ]; then
        print_error "Vault file not found: $VAULT_FILE"
        exit 1
    fi

    if [ ! -f "$VAULT_PASSWORD_FILE" ]; then
        print_error "Vault password file not found: $VAULT_PASSWORD_FILE"
        exit 1
    fi

    ansible-vault view "$VAULT_FILE" --vault-password-file "$VAULT_PASSWORD_FILE"
}

# Edit vault contents
edit_vault() {
    print_header "Editing Vault"

    if [ ! -f "$VAULT_FILE" ]; then
        print_error "Vault file not found. Run: $0 create"
        exit 1
    fi

    if [ ! -f "$VAULT_PASSWORD_FILE" ]; then
        print_error "Vault password file not found: $VAULT_PASSWORD_FILE"
        exit 1
    fi

    ansible-vault edit "$VAULT_FILE" --vault-password-file "$VAULT_PASSWORD_FILE"
    print_success "Vault updated"
}

# Rotate all credentials
rotate_credentials() {
    print_header "Rotating Credentials"

    if [ ! -f "$VAULT_PASSWORD_FILE" ]; then
        print_error "Vault password file not found. Run: $0 init"
        exit 1
    fi

    # Backup existing vault
    if [ -f "$VAULT_FILE" ]; then
        cp "$VAULT_FILE" "${VAULT_FILE}.backup.$(date +%Y%m%d%H%M%S)"
        print_info "Backed up existing vault"
    fi

    # Remove existing credentials to force regeneration
    rm -f "$CREDENTIALS_DIR/indexer_admin_password.txt"
    rm -f "$CREDENTIALS_DIR/api_password.txt"
    rm -f "$CREDENTIALS_DIR/agent_enrollment_password.txt"

    # Create new vault with new credentials
    create_vault

    print_success "Credentials rotated successfully"
    print_warning "Remember to redeploy to apply new credentials: ansible-playbook site.yml"
}

# Rekey vault (change vault password)
rekey_vault() {
    print_header "Rekeying Vault"

    if [ ! -f "$VAULT_FILE" ]; then
        print_error "Vault file not found: $VAULT_FILE"
        exit 1
    fi

    if [ ! -f "$VAULT_PASSWORD_FILE" ]; then
        print_error "Current vault password file not found: $VAULT_PASSWORD_FILE"
        exit 1
    fi

    # Generate new vault password
    local new_password=$(generate_password 32)
    local new_password_file="${VAULT_PASSWORD_FILE}.new"
    echo "$new_password" > "$new_password_file"

    # Rekey the vault
    ansible-vault rekey "$VAULT_FILE" \
        --vault-password-file "$VAULT_PASSWORD_FILE" \
        --new-vault-password-file "$new_password_file"

    # Replace old password file
    mv "$new_password_file" "$VAULT_PASSWORD_FILE"
    chmod 600 "$VAULT_PASSWORD_FILE"

    print_success "Vault rekeyed with new password"
    print_warning "IMPORTANT: Back up the new vault password file!"
}

# Show usage
usage() {
    echo "Wazuh Deployment - Ansible Vault Manager"
    echo ""
    echo "Usage: $0 <command>"
    echo ""
    echo "Commands:"
    echo "  init      Initialize vault with a new password"
    echo "  create    Create encrypted vault with credentials"
    echo "  view      View vault contents (decrypted)"
    echo "  edit      Edit vault contents"
    echo "  rotate    Rotate all credentials"
    echo "  rekey     Change vault password"
    echo ""
    echo "Examples:"
    echo "  $0 init      # First-time setup"
    echo "  $0 create    # Generate and encrypt credentials"
    echo "  $0 view      # Show current credentials"
    echo "  $0 rotate    # Generate new credentials"
    echo ""
    echo "Files:"
    echo "  Vault file:     $VAULT_FILE"
    echo "  Password file:  $VAULT_PASSWORD_FILE"
    echo "  Credentials:    $CREDENTIALS_DIR/"
}

# Main
case "${1:-}" in
    init)
        init_vault
        ;;
    create)
        shift
        create_vault "$@"
        ;;
    view)
        view_vault
        ;;
    edit)
        edit_vault
        ;;
    rotate)
        rotate_credentials
        ;;
    rekey)
        rekey_vault
        ;;
    *)
        usage
        exit 1
        ;;
esac
