#!/bin/bash

# Wazuh Deployment - Ansible Vault Management Script
# Manages encrypted credentials for secure deployment

set -e

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

# Generate a secure random password
generate_password() {
    local length="${1:-24}"
    local password=$(LC_ALL=C tr -dc 'A-Za-z0-9!@#$%^&*()_+-=' < /dev/urandom | head -c "$length")
    # Ensure complexity requirements
    local upper=$(LC_ALL=C tr -dc 'A-Z' < /dev/urandom | head -c 1)
    local lower=$(LC_ALL=C tr -dc 'a-z' < /dev/urandom | head -c 1)
    local number=$(LC_ALL=C tr -dc '0-9' < /dev/urandom | head -c 1)
    local symbol=$(echo '!@#$%^&*' | fold -w1 | shuf | head -1)
    password="${password}${upper}${lower}${number}${symbol}"
    echo "$password" | fold -w1 | shuf | tr -d '\n'
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

# Create or update vault file with credentials
create_vault() {
    print_header "Creating Encrypted Vault"

    if [ ! -f "$VAULT_PASSWORD_FILE" ]; then
        print_error "Vault password file not found. Run: $0 init"
        exit 1
    fi

    mkdir -p "$CREDENTIALS_DIR"
    mkdir -p "$VAULT_DIR"

    # Generate credentials if they don't exist
    local indexer_password=""
    local api_password=""
    local enrollment_password=""

    if [ -f "$CREDENTIALS_DIR/indexer_admin_password.txt" ]; then
        indexer_password=$(grep -oP 'Password:\s*\K.*' "$CREDENTIALS_DIR/indexer_admin_password.txt" 2>/dev/null || cat "$CREDENTIALS_DIR/indexer_admin_password.txt")
    fi
    if [ -z "$indexer_password" ]; then
        indexer_password=$(generate_password 24)
        print_info "Generated new indexer admin password"
    fi

    if [ -f "$CREDENTIALS_DIR/api_password.txt" ]; then
        api_password=$(grep -oP 'Password:\s*\K.*' "$CREDENTIALS_DIR/api_password.txt" 2>/dev/null || cat "$CREDENTIALS_DIR/api_password.txt")
    fi
    if [ -z "$api_password" ]; then
        api_password=$(generate_password 24)
        print_info "Generated new API password"
    fi

    if [ -f "$CREDENTIALS_DIR/agent_enrollment_password.txt" ]; then
        enrollment_password=$(grep -oP 'Password:\s*\K.*' "$CREDENTIALS_DIR/agent_enrollment_password.txt" 2>/dev/null || cat "$CREDENTIALS_DIR/agent_enrollment_password.txt")
    fi
    if [ -z "$enrollment_password" ]; then
        enrollment_password=$(generate_password 24)
        print_info "Generated new agent enrollment password"
    fi

    # Create vault content
    local vault_content="---
# Wazuh Deployment - Encrypted Credentials
# Generated: $(date -Iseconds)
# DO NOT COMMIT THIS FILE UNENCRYPTED!

# Indexer/Dashboard admin credentials
vault_wazuh_indexer_admin_password: \"${indexer_password}\"

# Wazuh API credentials
vault_wazuh_api_password: \"${api_password}\"

# Agent enrollment password
vault_wazuh_agent_enrollment_password: \"${enrollment_password}\"

# Manager cluster key (for multi-node deployments)
vault_wazuh_manager_cluster_key: \"$(generate_password 32)\"
"

    # Write and encrypt
    echo "$vault_content" > "${VAULT_FILE}.tmp"
    ansible-vault encrypt "${VAULT_FILE}.tmp" --vault-password-file "$VAULT_PASSWORD_FILE" --output "$VAULT_FILE"
    rm -f "${VAULT_FILE}.tmp"
    chmod 600 "$VAULT_FILE"

    print_success "Encrypted vault created: $VAULT_FILE"

    # Also save plain text credentials for reference (with warning)
    save_credential_files "$indexer_password" "$api_password" "$enrollment_password"
}

# Save credential files for reference
save_credential_files() {
    local indexer_password="$1"
    local api_password="$2"
    local enrollment_password="$3"

    mkdir -p "$CREDENTIALS_DIR"
    chmod 700 "$CREDENTIALS_DIR"

    cat > "$CREDENTIALS_DIR/indexer_admin_password.txt" << EOF
# Wazuh Indexer Admin Credentials
# Generated: $(date -Iseconds)
# WARNING: These credentials are also stored encrypted in group_vars/vault.yml

Username: admin
Password: ${indexer_password}

Dashboard URL: https://<dashboard-ip>:443

# SECURITY: Delete this file after noting the password!
# The encrypted vault.yml is the authoritative source.
EOF
    chmod 600 "$CREDENTIALS_DIR/indexer_admin_password.txt"

    cat > "$CREDENTIALS_DIR/api_password.txt" << EOF
# Wazuh API Credentials
# Generated: $(date -Iseconds)
# WARNING: These credentials are also stored encrypted in group_vars/vault.yml

Username: wazuh
Password: ${api_password}

API URL: https://<manager-ip>:55000

# SECURITY: Delete this file after noting the password!
# The encrypted vault.yml is the authoritative source.
EOF
    chmod 600 "$CREDENTIALS_DIR/api_password.txt"

    cat > "$CREDENTIALS_DIR/agent_enrollment_password.txt" << EOF
# Wazuh Agent Enrollment Credentials
# Generated: $(date -Iseconds)
# WARNING: These credentials are also stored encrypted in group_vars/vault.yml

Password: ${enrollment_password}

# SECURITY: Delete this file after noting the password!
# The encrypted vault.yml is the authoritative source.
EOF
    chmod 600 "$CREDENTIALS_DIR/agent_enrollment_password.txt"

    print_info "Credential reference files saved to: $CREDENTIALS_DIR/"
    print_warning "These files are for reference only. The encrypted vault.yml is authoritative."
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
        create_vault
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
