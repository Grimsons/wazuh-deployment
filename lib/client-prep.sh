#!/bin/bash
# Wazuh Deployment - Client Preparation Package Generator
# Shared between setup.sh and setup-tui.sh
#
# Required variables:
#   SCRIPT_DIR       - Root directory of the deployment project
#   ANSIBLE_SSH_KEY  - Path to SSH private key (public key = ${ANSIBLE_SSH_KEY}.pub)
#   ANSIBLE_USER     - Name of the ansible deployment user
#
# Optional callback functions (define before calling):
#   _prep_info()     - Called with info messages
#   _prep_success()  - Called with success messages
#   _prep_warn()     - Called with warning messages

# Default log callbacks - override these in the calling script if needed
_prep_info()    { echo "[INFO] $*"; }
_prep_success() { echo "[OK]   $*"; }
_prep_warn()    { echo "[WARN] $*"; }

# Create the client preparation package
# Returns 0 on success, 1 on failure
create_client_prep_package() {
    local base_dir="${1:-$SCRIPT_DIR}"
    local ssh_key="${2:-$ANSIBLE_SSH_KEY}"
    local ansible_user="${3:-${ANSIBLE_USER:-wazuh-deploy}}"

    local prep_dir="${base_dir}/client-prep"
    local tarball="${base_dir}/wazuh-client-prep.tar.gz"

    mkdir -p "$prep_dir"

    # Copy preparation script
    if [[ -f "${base_dir}/scripts/prepare-client.sh" ]]; then
        cp "${base_dir}/scripts/prepare-client.sh" "$prep_dir/"
    else
        _prep_warn "Preparation script not found at scripts/prepare-client.sh, skipping..."
    fi

    # Copy SSH public key
    if [[ -f "${ssh_key}.pub" ]]; then
        cp "${ssh_key}.pub" "$prep_dir/ansible_key.pub"
    elif [[ -f "${base_dir}/keys/wazuh_ansible_key.pub" ]]; then
        cp "${base_dir}/keys/wazuh_ansible_key.pub" "$prep_dir/ansible_key.pub"
    else
        _prep_warn "No SSH public key found, client prep package will lack key"
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

SSH User: ${ansible_user}
README_EOF

    # Create tarball
    tar -czf "$tarball" -C "${base_dir}" "client-prep"

    # Create self-extracting script
    cat > "${base_dir}/wazuh-client-prep.sh" << 'SELFEXTRACT_EOF'
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
    cat "$tarball" >> "${base_dir}/wazuh-client-prep.sh"
    chmod +x "${base_dir}/wazuh-client-prep.sh"

    _prep_success "Client preparation package created:"
    _prep_info "  Folder: ${prep_dir}/"
    _prep_info "  Tarball: ${tarball}"
    _prep_info "  Self-extracting: ${base_dir}/wazuh-client-prep.sh"
}
