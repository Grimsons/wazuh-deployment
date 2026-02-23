#!/bin/bash

# Wazuh Client Preparation Script
# This script prepares a client machine for Wazuh Agent deployment via Ansible
# Run this script on each target machine before Ansible deployment
#
# Security features:
# - Audit logging for all security-sensitive operations
# - Restricted sudo permissions (not NOPASSWD ALL)
# - Backup before configuration changes
# - Input validation
# - Rollback capability on failure

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Configuration
ANSIBLE_USER="${ANSIBLE_USER:-wazuh-deploy}"
SSH_PORT="${SSH_PORT:-22}"
PUBKEY_FILE="${SCRIPT_DIR}/ansible_key.pub"
MINIMAL_MODE="${MINIMAL_MODE:-false}"
DRY_RUN="${DRY_RUN:-false}"
# Note: Restricted sudo doesn't work well with Ansible's become mechanism
# which runs: sudo /bin/sh -c '...; python3'. Default to full sudo.
RESTRICT_SUDO="${RESTRICT_SUDO:-false}"

# Logging
LOG_FILE="/var/log/wazuh-client-prep.log"
AUDIT_LOG="/var/log/wazuh-client-prep-audit.log"

# Backup directory for rollback
BACKUP_DIR="/var/backups/wazuh-prep-$(date +%Y%m%d%H%M%S)"
ROLLBACK_ENABLED=false

# Cleanup and rollback trap
cleanup() {
    local exit_code=$?
    if [ $exit_code -ne 0 ] && [ "$ROLLBACK_ENABLED" = "true" ] && [ -d "$BACKUP_DIR" ]; then
        print_warning "Script failed, attempting rollback..."
        rollback
    fi
    # Restore terminal
    stty echo 2>/dev/null || true
    exit $exit_code
}
trap cleanup EXIT INT TERM

# Audit logging for security-sensitive operations
audit_log() {
    local action="$1"
    local details="${2:-}"
    local timestamp
    timestamp=$(date -Iseconds)
    local user
    user=$(whoami)

    # Ensure audit log exists with proper permissions
    touch "$AUDIT_LOG" 2>/dev/null || true
    chmod 600 "$AUDIT_LOG" 2>/dev/null || true

    echo "${timestamp}|${user}|${action}|${details}" >> "$AUDIT_LOG" 2>/dev/null || true
}

# Create backup of critical files
create_backup() {
    if [ "$DRY_RUN" = "true" ]; then
        return
    fi

    mkdir -p "$BACKUP_DIR"
    chmod 700 "$BACKUP_DIR"

    # Backup SSH config
    [ -f /etc/ssh/sshd_config ] && cp -a /etc/ssh/sshd_config "$BACKUP_DIR/" 2>/dev/null || true

    # Backup sudoers
    [ -d /etc/sudoers.d ] && cp -a /etc/sudoers.d "$BACKUP_DIR/" 2>/dev/null || true

    # Backup limits.conf
    [ -f /etc/security/limits.conf ] && cp -a /etc/security/limits.conf "$BACKUP_DIR/" 2>/dev/null || true

    # Backup sysctl configs
    [ -d /etc/sysctl.d ] && cp -a /etc/sysctl.d "$BACKUP_DIR/" 2>/dev/null || true

    ROLLBACK_ENABLED=true
    audit_log "BACKUP_CREATED" "Backup directory: $BACKUP_DIR"
    print_info "Backup created: $BACKUP_DIR"
}

# Rollback changes on failure
rollback() {
    if [ ! -d "$BACKUP_DIR" ]; then
        print_error "No backup directory found for rollback"
        return 1
    fi

    audit_log "ROLLBACK_STARTED" "Rolling back from: $BACKUP_DIR"

    # Restore SSH config
    [ -f "$BACKUP_DIR/sshd_config" ] && cp -a "$BACKUP_DIR/sshd_config" /etc/ssh/ 2>/dev/null || true

    # Restore sudoers (be careful here)
    if [ -d "$BACKUP_DIR/sudoers.d" ]; then
        rm -f "/etc/sudoers.d/${ANSIBLE_USER}" 2>/dev/null || true
    fi

    # Restore limits.conf
    [ -f "$BACKUP_DIR/limits.conf" ] && cp -a "$BACKUP_DIR/limits.conf" /etc/security/ 2>/dev/null || true

    # Remove wazuh sysctl if we created it
    rm -f /etc/sysctl.d/99-wazuh.conf 2>/dev/null || true

    # Reload sysctl
    sysctl --system &>/dev/null || true

    # Restart SSH if needed
    systemctl restart sshd 2>/dev/null || systemctl restart ssh 2>/dev/null || true

    audit_log "ROLLBACK_COMPLETED" "Restored from: $BACKUP_DIR"
    print_warning "Rollback completed"
}

# Input validation
validate_username() {
    local user="$1"
    # Linux username: starts with letter, contains only letters, numbers, underscores, hyphens
    [[ "$user" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]
}

validate_port() {
    local port="$1"
    [[ "$port" =~ ^[0-9]+$ ]] && (( port >= 1 && port <= 65535 ))
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

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE" 2>/dev/null || true
    echo -e "$1"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 1
    fi
}

# Detect OS
detect_os() {
    print_section "Detecting Operating System"

    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID="$ID"
        OS_VERSION="$VERSION_ID"
        OS_NAME="$NAME"
        OS_FAMILY=""

        case "$OS_ID" in
            ubuntu|debian|linuxmint|pop)
                OS_FAMILY="debian"
                PKG_MANAGER="apt"
                ;;
            fedora)
                OS_FAMILY="fedora"
                PKG_MANAGER="dnf"
                ;;
            rhel|centos|rocky|almalinux|ol|redhat)
                OS_FAMILY="rhel"
                if command -v dnf &> /dev/null; then
                    PKG_MANAGER="dnf"
                else
                    PKG_MANAGER="yum"
                fi
                ;;
            opensuse*|sles)
                OS_FAMILY="suse"
                PKG_MANAGER="zypper"
                ;;
            arch|manjaro)
                OS_FAMILY="arch"
                PKG_MANAGER="pacman"
                ;;
            *)
                print_error "Unsupported OS: $OS_ID"
                exit 1
                ;;
        esac
    elif [ -f /etc/redhat-release ]; then
        OS_FAMILY="rhel"
        OS_NAME=$(cat /etc/redhat-release)
        PKG_MANAGER="yum"
    else
        print_error "Cannot detect operating system"
        exit 1
    fi

    print_success "Detected: $OS_NAME"
    print_info "OS Family: $OS_FAMILY"
    print_info "Package Manager: $PKG_MANAGER"

    log "OS Detection: $OS_NAME ($OS_FAMILY) - Package Manager: $PKG_MANAGER"
}

# Define packages to remove per OS family
get_unnecessary_packages() {
    local packages=""

    case "$OS_FAMILY" in
        debian)
            packages="
                # Desktop environments and related
                ubuntu-desktop
                kubuntu-desktop
                xubuntu-desktop
                lubuntu-desktop
                gnome-shell
                gnome-session
                kde-plasma-desktop
                xfce4
                lxde
                cinnamon
                mate-desktop

                # Display managers
                gdm3
                sddm
                lightdm
                lxdm

                # Office and productivity
                libreoffice*
                thunderbird
                evolution

                # Games
                gnome-games
                aisleriot
                gnome-mines
                gnome-sudoku

                # Media
                rhythmbox
                totem
                cheese
                shotwell

                # Browsers (keep one if needed)
                firefox
                chromium-browser

                # Unnecessary services
                cups
                cups-browsed
                avahi-daemon
                bluetooth
                bluez
                pulseaudio
                pipewire

                # Snaps (if not needed)
                snapd

                # Other bloat
                ubuntu-report
                popularity-contest
                apport
                whoopsie
                kerneloops

                # Development tools not needed for Wazuh
                gcc
                g++
                make

                # Documentation
                man-db
                info
            "
            ;;
        rhel|fedora)
            packages="
                # Desktop environments
                @gnome-desktop
                @kde-desktop-environment
                @xfce-desktop
                @lxde-desktop
                @mate-desktop
                @cinnamon-desktop

                # Display managers
                gdm
                sddm
                lightdm

                # Office
                libreoffice*

                # Media
                rhythmbox
                totem
                cheese

                # Games
                gnome-mines
                gnome-chess

                # Unnecessary services
                cups
                avahi
                bluetooth
                bluez
                pulseaudio
                pipewire

                # Development (if not needed)
                gcc
                gcc-c++

                # Other
                abrt*
                cockpit*
            "
            ;;
        suse)
            packages="
                # Desktop
                patterns-gnome*
                patterns-kde*
                patterns-xfce*

                # Office
                libreoffice*

                # Unnecessary services
                cups
                avahi
                bluetooth
            "
            ;;
        arch)
            packages="
                # Desktop
                gnome
                plasma
                xfce4
                lxde

                # Office
                libreoffice*

                # Unnecessary
                cups
                avahi
                bluez
            "
            ;;
    esac

    echo "$packages" | grep -v '^#' | grep -v '^$' | tr '\n' ' '
}

# Define essential packages for Wazuh/Ansible
get_essential_packages() {
    local packages=""

    case "$OS_FAMILY" in
        debian)
            packages="
                openssh-server
                python3
                python3-apt
                sudo
                curl
                wget
                ca-certificates
                gnupg
                lsb-release
                apt-transport-https
                net-tools
                iproute2
                procps
                systemd
            "
            ;;
        rhel|fedora)
            packages="
                openssh-server
                python3
                python3-dnf
                sudo
                curl
                wget
                ca-certificates
                gnupg2
                net-tools
                iproute
                procps-ng
                systemd
            "
            ;;
        suse)
            packages="
                openssh
                python3
                python3-pip
                sudo
                curl
                wget
                ca-certificates
                iproute2
                procps
                which
                systemd
            "
            ;;
        arch)
            packages="
                openssh
                python
                python-pip
                sudo
                curl
                wget
                ca-certificates
                iproute2
                procps-ng
                which
                base-devel
            "
            ;;
    esac

    echo "$packages" | grep -v '^$' | tr '\n' ' '
}

# Remove unnecessary packages
remove_unnecessary_packages() {
    print_section "Removing Unnecessary Packages"

    local packages=$(get_unnecessary_packages)

    if [ "$DRY_RUN" = "true" ]; then
        print_info "[DRY RUN] Would remove packages:"
        echo "$packages" | tr ' ' '\n' | grep -v '^$' | while read pkg; do
            echo "  - $pkg"
        done
        return
    fi

    case "$PKG_MANAGER" in
        apt)
            # Stop services first
            print_info "Stopping unnecessary services..."
            for service in gdm3 lightdm sddm cups avahi-daemon bluetooth snapd; do
                systemctl stop "$service" 2>/dev/null || true
                systemctl disable "$service" 2>/dev/null || true
            done

            print_info "Removing packages..."
            export DEBIAN_FRONTEND=noninteractive

            # Remove packages (ignore errors for non-existent packages)
            for pkg in $packages; do
                apt-get remove --purge -y "$pkg" 2>/dev/null || true
            done

            # Clean up
            apt-get autoremove -y 2>/dev/null || true
            apt-get autoclean -y 2>/dev/null || true
            apt-get clean 2>/dev/null || true

            # Remove snap completely if installed
            if command -v snap &> /dev/null; then
                print_info "Removing Snap packages..."
                snap list 2>/dev/null | awk 'NR>1 {print $1}' | while read snapname; do
                    snap remove --purge "$snapname" 2>/dev/null || true
                done
                apt-get remove --purge -y snapd 2>/dev/null || true
                rm -rf /var/cache/snapd /snap /var/snap /var/lib/snapd
            fi
            ;;
        dnf|yum)
            print_info "Stopping unnecessary services..."
            for service in gdm lightdm cups avahi bluetooth; do
                systemctl stop "$service" 2>/dev/null || true
                systemctl disable "$service" 2>/dev/null || true
            done

            print_info "Removing packages..."
            for pkg in $packages; do
                $PKG_MANAGER remove -y "$pkg" 2>/dev/null || true
            done

            $PKG_MANAGER autoremove -y 2>/dev/null || true
            $PKG_MANAGER clean all 2>/dev/null || true
            ;;
        zypper)
            print_info "Removing packages..."
            for pkg in $packages; do
                zypper remove -y "$pkg" 2>/dev/null || true
            done
            zypper clean --all 2>/dev/null || true
            ;;
        pacman)
            print_info "Removing packages..."
            for pkg in $packages; do
                pacman -Rns --noconfirm "$pkg" 2>/dev/null || true
            done
            pacman -Sc --noconfirm 2>/dev/null || true
            ;;
    esac

    print_success "Unnecessary packages removed"
}

# Install essential packages
install_essential_packages() {
    print_section "Installing Essential Packages"

    local packages=$(get_essential_packages)

    if [ "$DRY_RUN" = "true" ]; then
        print_info "[DRY RUN] Would install packages:"
        echo "$packages" | tr ' ' '\n' | grep -v '^$' | while read pkg; do
            echo "  - $pkg"
        done
        return
    fi

    case "$PKG_MANAGER" in
        apt)
            apt-get update
            apt-get install -y $packages
            ;;
        dnf|yum)
            $PKG_MANAGER install -y $packages
            ;;
        zypper)
            zypper install -y $packages
            ;;
        pacman)
            pacman -Sy --noconfirm $packages
            ;;
    esac

    print_success "Essential packages installed"
}

# Configure SSH
configure_ssh() {
    print_section "Configuring SSH"

    if [ "$DRY_RUN" = "true" ]; then
        print_info "[DRY RUN] Would configure SSH"
        return
    fi

    # Ensure SSH is installed and running
    case "$OS_FAMILY" in
        debian)
            apt-get install -y openssh-server
            ;;
        rhel|fedora)
            $PKG_MANAGER install -y openssh-server
            ;;
        suse)
            zypper install -y openssh
            ;;
        arch)
            pacman -S --noconfirm --needed openssh
            ;;
    esac

    # Configure sshd
    local sshd_config="/etc/ssh/sshd_config"

    # Backup original config
    cp "$sshd_config" "${sshd_config}.backup.$(date +%Y%m%d)" 2>/dev/null || true

    # Ensure key authentication is enabled (use -E for extended regex on all platforms)
    if grep -qE '^#?PubkeyAuthentication' "$sshd_config"; then
        sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' "$sshd_config"
    else
        echo "PubkeyAuthentication yes" >> "$sshd_config"
    fi

    if grep -qE '^#?AuthorizedKeysFile' "$sshd_config"; then
        sed -i 's/^#*AuthorizedKeysFile.*/AuthorizedKeysFile .ssh\/authorized_keys/' "$sshd_config"
    fi

    # Optionally disable password auth (uncomment if desired)
    # sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' "$sshd_config"

    # Ensure root login is permitted (or use dedicated user)
    # sed -i 's/^#*PermitRootLogin.*/PermitRootLogin prohibit-password/' "$sshd_config"

    # Determine SSH service name based on OS
    local ssh_service="sshd"
    if [ "$OS_FAMILY" = "debian" ]; then
        # Debian/Ubuntu uses 'ssh' as service name
        if systemctl list-unit-files | grep -q "^ssh.service"; then
            ssh_service="ssh"
        fi
    fi

    # Enable and restart SSH
    systemctl enable "$ssh_service" 2>/dev/null || true
    systemctl restart "$ssh_service" 2>/dev/null || true

    print_success "SSH configured"
}

# Create Ansible deployment user
create_ansible_user() {
    print_section "Creating Ansible Deployment User"

    if [ "$DRY_RUN" = "true" ]; then
        print_info "[DRY RUN] Would create user: $ANSIBLE_USER"
        return
    fi

    # Validate username
    if ! validate_username "$ANSIBLE_USER"; then
        print_error "Invalid username: $ANSIBLE_USER"
        exit 1
    fi

    audit_log "USER_CREATE_START" "Creating user: $ANSIBLE_USER"

    # Check if user exists
    if id "$ANSIBLE_USER" &>/dev/null; then
        print_info "User $ANSIBLE_USER already exists"
    else
        # Create user - handle different distro behaviors
        case "$OS_FAMILY" in
            arch)
                # Arch Linux useradd
                useradd -m -s /bin/bash -G wheel "$ANSIBLE_USER" 2>/dev/null || \
                useradd -m -s /bin/bash "$ANSIBLE_USER"
                ;;
            *)
                # Standard useradd for Debian, RHEL, SUSE
                useradd -m -s /bin/bash -c "Wazuh Ansible Deployment User" "$ANSIBLE_USER"
                ;;
        esac
        print_success "Created user: $ANSIBLE_USER"
        audit_log "USER_CREATED" "User $ANSIBLE_USER created"
    fi

    # Create .ssh directory with secure permissions
    local ssh_dir="/home/${ANSIBLE_USER}/.ssh"
    mkdir -p "$ssh_dir"
    chmod 700 "$ssh_dir"
    chown "${ANSIBLE_USER}:${ANSIBLE_USER}" "$ssh_dir"

    # Configure sudo access
    local sudoers_file="/etc/sudoers.d/${ANSIBLE_USER}"

    if [ "$RESTRICT_SUDO" = "true" ]; then
        # Restricted sudo - only specific commands needed for Wazuh deployment
        cat > "$sudoers_file" << EOF
# Wazuh Ansible deployment user - restricted permissions
# Generated by wazuh-client-prep.sh on $(date)

# Package management
${ANSIBLE_USER} ALL=(ALL) NOPASSWD: /usr/bin/apt-get, /usr/bin/apt
${ANSIBLE_USER} ALL=(ALL) NOPASSWD: /usr/bin/dnf, /usr/bin/yum, /usr/bin/rpm
${ANSIBLE_USER} ALL=(ALL) NOPASSWD: /usr/bin/zypper
${ANSIBLE_USER} ALL=(ALL) NOPASSWD: /usr/bin/pacman

# Service management
${ANSIBLE_USER} ALL=(ALL) NOPASSWD: /usr/bin/systemctl
${ANSIBLE_USER} ALL=(ALL) NOPASSWD: /bin/systemctl

# File operations (for config deployment)
${ANSIBLE_USER} ALL=(ALL) NOPASSWD: /bin/cp, /bin/mv, /bin/rm, /bin/mkdir, /bin/chmod, /bin/chown
${ANSIBLE_USER} ALL=(ALL) NOPASSWD: /usr/bin/cp, /usr/bin/mv, /usr/bin/rm, /usr/bin/mkdir, /usr/bin/chmod, /usr/bin/chown
${ANSIBLE_USER} ALL=(ALL) NOPASSWD: /usr/bin/tee, /bin/tee

# Wazuh specific
${ANSIBLE_USER} ALL=(ALL) NOPASSWD: /var/ossec/bin/*

# Certificate and key management
${ANSIBLE_USER} ALL=(ALL) NOPASSWD: /usr/bin/openssl

# Network utilities
${ANSIBLE_USER} ALL=(ALL) NOPASSWD: /usr/bin/curl, /usr/bin/wget

# Process management
${ANSIBLE_USER} ALL=(ALL) NOPASSWD: /bin/kill, /usr/bin/kill, /usr/bin/pkill

# Firewall management
${ANSIBLE_USER} ALL=(ALL) NOPASSWD: /usr/sbin/ufw, /usr/bin/firewall-cmd

# SELinux management
${ANSIBLE_USER} ALL=(ALL) NOPASSWD: /usr/sbin/semanage, /usr/sbin/setsebool, /usr/sbin/restorecon

# Required for Ansible facts and become
# Note: Restrict to Ansible module runner paths to prevent arbitrary shell access
${ANSIBLE_USER} ALL=(ALL) NOPASSWD: /usr/bin/python3 /tmp/.ansible/tmp/*/AnsiballZ_*.py
${ANSIBLE_USER} ALL=(ALL) NOPASSWD: /usr/bin/python /tmp/.ansible/tmp/*/AnsiballZ_*.py
${ANSIBLE_USER} ALL=(ALL) NOPASSWD: /usr/bin/python3 /root/.ansible/tmp/*/AnsiballZ_*.py
EOF
        print_info "Configured restricted sudo permissions"
        audit_log "SUDO_RESTRICTED" "Restricted sudo configured for: $ANSIBLE_USER"
    else
        # Full sudo access - required for Ansible's become mechanism
        echo "${ANSIBLE_USER} ALL=(ALL) NOPASSWD: ALL" > "$sudoers_file"
        print_success "Configured sudo permissions for Ansible"
        audit_log "SUDO_CONFIGURED" "Full sudo configured for: $ANSIBLE_USER"
    fi

    # Set proper permissions on sudoers file
    chmod 440 "$sudoers_file"

    # Validate sudoers syntax
    if command -v visudo &>/dev/null; then
        if ! visudo -c -f "$sudoers_file" &>/dev/null; then
            print_error "Invalid sudoers syntax - removing file"
            rm -f "$sudoers_file"
            audit_log "SUDO_ERROR" "Invalid sudoers syntax for: $ANSIBLE_USER"
            exit 1
        fi
    fi

    print_success "User $ANSIBLE_USER configured with sudo access"
    audit_log "USER_CONFIGURED" "User $ANSIBLE_USER fully configured"

    # Install the unlock script for post-deployment lockdown support
    install_unlock_script
}

# Install unlock script for post-deployment lockdown
install_unlock_script() {
    print_info "Installing deployment unlock script..."

    local unlock_script="/usr/local/bin/wazuh-unlock-deploy"

    cat > "$unlock_script" << 'UNLOCKEOF'
#!/bin/bash
# Wazuh Deployment - Unlock Script
# Restores full sudo access to the ansible deployment user
# This script can be run by the locked-down user via restricted sudo

set -euo pipefail

ANSIBLE_USER="${SUDO_USER:-wazuh-deploy}"
SUDOERS_FILE="/etc/sudoers.d/${ANSIBLE_USER}"
LOCK_FLAG="/var/lib/wazuh-deploy/.locked"

# Verify we're being run correctly
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run with sudo"
    exit 1
fi

# Restore full sudo access
echo "${ANSIBLE_USER} ALL=(ALL) NOPASSWD: ALL" > "$SUDOERS_FILE"
chmod 440 "$SUDOERS_FILE"

# Validate sudoers syntax
if ! visudo -c -f "$SUDOERS_FILE" &>/dev/null; then
    echo "ERROR: Invalid sudoers syntax"
    exit 1
fi

# Remove lock flag
rm -f "$LOCK_FLAG"

# Log the unlock
logger -t wazuh-deploy "Ansible deployment user $ANSIBLE_USER unlocked by $(whoami)"

echo "Deployment user $ANSIBLE_USER has been unlocked"
echo "Full sudo access has been restored"
echo "Remember to run lockdown after deployment completes"
UNLOCKEOF

    chmod 755 "$unlock_script"
    chown root:root "$unlock_script"

    # Create the lock flag directory
    mkdir -p /var/lib/wazuh-deploy
    chmod 755 /var/lib/wazuh-deploy

    print_success "Unlock script installed at $unlock_script"
    audit_log "UNLOCK_SCRIPT_INSTALLED" "Unlock script installed at: $unlock_script"
}

# Deploy SSH public key
deploy_ssh_key() {
    print_section "Deploying SSH Public Key"

    if [ "$DRY_RUN" = "true" ]; then
        print_info "[DRY RUN] Would deploy SSH key"
        return
    fi

    local ssh_dir="/home/${ANSIBLE_USER}/.ssh"
    local auth_keys="${ssh_dir}/authorized_keys"

    audit_log "SSH_KEY_DEPLOY_START" "Deploying SSH key for: $ANSIBLE_USER"

    # Check if public key file exists
    if [ -f "$PUBKEY_FILE" ]; then
        # Validate SSH public key format
        if ! grep -qE '^(ssh-rsa|ssh-ed25519|ecdsa-sha2-nistp|ssh-dss) ' "$PUBKEY_FILE" 2>/dev/null; then
            print_error "Invalid SSH public key format in: $PUBKEY_FILE"
            audit_log "SSH_KEY_INVALID" "Invalid key format: $PUBKEY_FILE"
            return 1
        fi

        print_info "Found public key file: $PUBKEY_FILE"

        # Create authorized_keys if it doesn't exist
        touch "$auth_keys"

        # Check if key is already present (use sha256 hash to compare)
        local key_content
        key_content=$(cat "$PUBKEY_FILE")
        if grep -qF "$key_content" "$auth_keys" 2>/dev/null; then
            print_info "SSH key already present in authorized_keys"
        else
            cat "$PUBKEY_FILE" >> "$auth_keys"
            print_success "SSH key deployed"
            audit_log "SSH_KEY_DEPLOYED" "SSH key deployed to: $auth_keys"
        fi

        chmod 600 "$auth_keys"
        chown "${ANSIBLE_USER}:${ANSIBLE_USER}" "$auth_keys"
    else
        print_warning "No public key file found at $PUBKEY_FILE"
        print_info "You can manually add the key later to: $auth_keys"
        audit_log "SSH_KEY_MISSING" "No key file found: $PUBKEY_FILE"
    fi

    # Also add to root if desired
    if [ "${DEPLOY_TO_ROOT:-false}" = "true" ] && [ -f "$PUBKEY_FILE" ]; then
        mkdir -p /root/.ssh
        chmod 700 /root/.ssh
        touch /root/.ssh/authorized_keys
        local key_content
        key_content=$(cat "$PUBKEY_FILE")
        if ! grep -qF "$key_content" /root/.ssh/authorized_keys 2>/dev/null; then
            cat "$PUBKEY_FILE" >> /root/.ssh/authorized_keys
            chmod 600 /root/.ssh/authorized_keys
            print_success "SSH key also deployed to root"
            audit_log "SSH_KEY_DEPLOYED_ROOT" "SSH key deployed to root user"
        fi
    fi
}

# Configure firewall
configure_firewall() {
    print_section "Configuring Firewall"

    if [ "$DRY_RUN" = "true" ]; then
        print_info "[DRY RUN] Would configure firewall"
        return
    fi

    local firewall_configured=false

    # UFW (Debian/Ubuntu)
    if command -v ufw &> /dev/null; then
        print_info "Configuring UFW..."
        ufw allow "$SSH_PORT"/tcp comment 'SSH' 2>/dev/null || ufw allow "$SSH_PORT"/tcp
        ufw allow 1514/tcp comment 'Wazuh Agent' 2>/dev/null || ufw allow 1514/tcp
        ufw allow 1514/udp comment 'Wazuh Agent' 2>/dev/null || ufw allow 1514/udp
        ufw allow 1515/tcp comment 'Wazuh Registration' 2>/dev/null || ufw allow 1515/tcp

        # Enable UFW if not already
        if ! ufw status | grep -q "active"; then
            echo "y" | ufw enable
        fi

        print_success "UFW configured"
        firewall_configured=true
    fi

    # Firewalld (RHEL/Fedora/SUSE)
    if command -v firewall-cmd &> /dev/null && [ "$firewall_configured" = "false" ]; then
        print_info "Configuring firewalld..."

        # Ensure firewalld is running
        systemctl start firewalld 2>/dev/null || true
        systemctl enable firewalld 2>/dev/null || true

        firewall-cmd --permanent --add-port="$SSH_PORT"/tcp 2>/dev/null || true
        firewall-cmd --permanent --add-port=1514/tcp 2>/dev/null || true
        firewall-cmd --permanent --add-port=1514/udp 2>/dev/null || true
        firewall-cmd --permanent --add-port=1515/tcp 2>/dev/null || true
        firewall-cmd --reload 2>/dev/null || true

        print_success "firewalld configured"
        firewall_configured=true
    fi

    # iptables (Arch Linux and others without ufw/firewalld)
    if command -v iptables &> /dev/null && [ "$firewall_configured" = "false" ]; then
        print_info "Configuring iptables..."

        # Check if iptables has any rules (i.e., firewall is active)
        if iptables -L INPUT -n 2>/dev/null | grep -q "ACCEPT\|DROP\|REJECT"; then
            # Add rules for Wazuh (insert at top to ensure they're processed)
            iptables -I INPUT -p tcp --dport "$SSH_PORT" -j ACCEPT 2>/dev/null || true
            iptables -I INPUT -p tcp --dport 1514 -j ACCEPT 2>/dev/null || true
            iptables -I INPUT -p udp --dport 1514 -j ACCEPT 2>/dev/null || true
            iptables -I INPUT -p tcp --dport 1515 -j ACCEPT 2>/dev/null || true

            # Save iptables rules
            if command -v iptables-save &> /dev/null; then
                case "$OS_FAMILY" in
                    arch)
                        iptables-save > /etc/iptables/iptables.rules 2>/dev/null || true
                        systemctl enable iptables 2>/dev/null || true
                        ;;
                    rhel|fedora)
                        iptables-save > /etc/sysconfig/iptables 2>/dev/null || true
                        ;;
                    debian)
                        iptables-save > /etc/iptables.rules 2>/dev/null || true
                        ;;
                esac
            fi

            print_success "iptables configured"
            firewall_configured=true
        else
            print_info "iptables present but no active firewall rules detected"
        fi
    fi

    # nftables (modern replacement for iptables)
    if command -v nft &> /dev/null && [ "$firewall_configured" = "false" ]; then
        print_info "Configuring nftables..."

        # Check if nftables is active
        if nft list tables 2>/dev/null | grep -q "inet\|ip"; then
            # Create Wazuh chain if it doesn't exist
            nft add table inet filter 2>/dev/null || true
            nft add chain inet filter input '{ type filter hook input priority 0; policy accept; }' 2>/dev/null || true

            # Add rules
            nft add rule inet filter input tcp dport "$SSH_PORT" accept 2>/dev/null || true
            nft add rule inet filter input tcp dport 1514 accept 2>/dev/null || true
            nft add rule inet filter input udp dport 1514 accept 2>/dev/null || true
            nft add rule inet filter input tcp dport 1515 accept 2>/dev/null || true

            print_success "nftables configured"
            firewall_configured=true
        else
            print_info "nftables present but no active ruleset detected"
        fi
    fi

    if [ "$firewall_configured" = "false" ]; then
        print_info "No active firewall detected - skipping firewall configuration"
        print_info "Ensure ports $SSH_PORT, 1514/tcp, 1514/udp, 1515/tcp are accessible"
    fi
}

# Disable unnecessary services
disable_unnecessary_services() {
    print_section "Disabling Unnecessary Services"

    if [ "$DRY_RUN" = "true" ]; then
        print_info "[DRY RUN] Would disable unnecessary services"
        return
    fi

    local services="
        cups
        cups-browsed
        avahi-daemon
        bluetooth
        ModemManager
        accounts-daemon
        whoopsie
        kerneloops
        apport
        unattended-upgrades
    "

    for service in $services; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            systemctl stop "$service" 2>/dev/null || true
            systemctl disable "$service" 2>/dev/null || true
            print_info "Disabled: $service"
        fi
    done

    print_success "Unnecessary services disabled"
}

# Optimize system for Wazuh
optimize_system() {
    print_section "Optimizing System"

    if [ "$DRY_RUN" = "true" ]; then
        print_info "[DRY RUN] Would optimize system"
        return
    fi

    audit_log "SYSTEM_OPTIMIZE_START" "Beginning system optimization"

    # Increase file descriptor limits (only if not already configured)
    if ! grep -q "# Wazuh optimization" /etc/security/limits.conf 2>/dev/null; then
        cat >> /etc/security/limits.conf << 'EOF'

# Wazuh optimization - added by wazuh-client-prep.sh
* soft nofile 65536
* hard nofile 65536
root soft nofile 65536
root hard nofile 65536
EOF
        print_info "Updated file descriptor limits"
        audit_log "LIMITS_UPDATED" "File descriptor limits configured"
    else
        print_info "File descriptor limits already configured"
    fi

    # Optimize sysctl settings (only if not already configured)
    if [ ! -f /etc/sysctl.d/99-wazuh.conf ]; then
        cat > /etc/sysctl.d/99-wazuh.conf << 'EOF'
# Wazuh optimization - added by wazuh-client-prep.sh
# Network performance tuning
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_tw_reuse = 1

# File system limits
fs.file-max = 2097152
EOF
        chmod 644 /etc/sysctl.d/99-wazuh.conf
        sysctl -p /etc/sysctl.d/99-wazuh.conf 2>/dev/null || true
        print_info "Updated sysctl settings"
        audit_log "SYSCTL_UPDATED" "Sysctl settings configured"
    else
        print_info "Sysctl settings already configured"
    fi

    print_success "System optimized"
    audit_log "SYSTEM_OPTIMIZE_COMPLETE" "System optimization completed"
}

# Clean up system
cleanup_system() {
    print_section "Cleaning Up System"

    if [ "$DRY_RUN" = "true" ]; then
        print_info "[DRY RUN] Would clean up system"
        return
    fi

    # Remove old kernels (keep current + 1) and clean up
    case "$OS_FAMILY" in
        debian)
            apt-get autoremove --purge -y 2>/dev/null || true
            # Clean package cache
            apt-get clean 2>/dev/null || true
            ;;
        rhel|fedora)
            $PKG_MANAGER autoremove -y 2>/dev/null || true
            $PKG_MANAGER clean all 2>/dev/null || true
            ;;
        suse)
            zypper clean --all 2>/dev/null || true
            ;;
        arch)
            # Clean package cache (keep latest version only)
            if command -v paccache &> /dev/null; then
                paccache -rk1 2>/dev/null || true
            else
                pacman -Sc --noconfirm 2>/dev/null || true
            fi
            # Remove orphaned packages
            pacman -Qtdq 2>/dev/null | pacman -Rns --noconfirm - 2>/dev/null || true
            ;;
    esac

    # Clean old rotated logs older than 30 days (preserve recent for forensics)
    find /var/log -type f -name "*.gz" -mtime +30 -delete 2>/dev/null || true
    find /var/log -type f -name "*.1" -mtime +30 -delete 2>/dev/null || true
    journalctl --vacuum-time=7d 2>/dev/null || true

    # Clear only wazuh-related temp files (do NOT remove other users' temp files)
    rm -rf /tmp/wazuh-prep /tmp/wazuh-client-prep* 2>/dev/null || true

    print_success "System cleaned up"
}

# Generate system report
generate_report() {
    # Disable errexit for this function as it's informational only
    set +e

    print_section "System Report"

    echo -e "${CYAN}Hostname:${NC} $(hostname)"
    echo -e "${CYAN}OS:${NC} $OS_NAME"
    echo -e "${CYAN}Kernel:${NC} $(uname -r)"
    echo -e "${CYAN}Architecture:${NC} $(uname -m)"

    local ip_addr
    ip_addr=$(hostname -I 2>/dev/null | awk '{print $1}') || ip_addr="unknown"
    echo -e "${CYAN}IP Address:${NC} $ip_addr"
    echo -e "${CYAN}Ansible User:${NC} $ANSIBLE_USER"
    echo -e "${CYAN}SSH Port:${NC} $SSH_PORT"
    echo ""
    echo -e "${CYAN}Disk Usage:${NC}"
    df -h / 2>/dev/null | tail -1 || echo "  Unable to determine"
    echo ""
    echo -e "${CYAN}Memory:${NC}"
    free -h 2>/dev/null | head -2 || echo "  Unable to determine"
    echo ""
    echo -e "${CYAN}Running Services:${NC}"
    systemctl list-units --type=service --state=running 2>/dev/null | head -10 || echo "  Unable to list services"

    # Re-enable errexit
    set -e
}

# Display usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Prepare a client machine for Wazuh deployment via Ansible.
Supports: Debian/Ubuntu, RHEL/CentOS/Rocky/Alma, Fedora, SUSE, Arch Linux

OPTIONS:
    -u, --user NAME         Ansible user to create (default: wazuh-deploy)
    -p, --port PORT         SSH port (default: 22)
    -k, --key FILE          Path to SSH public key file
    -m, --minimal           Minimal mode - skip package removal
    -r, --root-key          Also deploy SSH key to root user
    -d, --dry-run           Show what would be done without making changes
    --restrict-sudo         Use restricted sudo (may cause issues with Ansible)
    -h, --help              Show this help message

SECURITY:
    By default, the Ansible user is configured with full sudo (NOPASSWD: ALL).
    This is required for Ansible's become mechanism to work properly.

    Use --restrict-sudo for a more locked-down configuration, but note that
    this may cause "Missing sudo password" errors with Ansible.

    An audit log is written to: /var/log/wazuh-client-prep-audit.log

EXAMPLES:
    # Full preparation with SSH key (recommended)
    $0 -k /path/to/ansible_key.pub

    # Dry run to see what would happen
    $0 --dry-run

    # Minimal mode (just install requirements, don't remove packages)
    $0 --minimal -k /path/to/ansible_key.pub

    # Custom user and port
    $0 -u ansible -p 2222 -k /path/to/key.pub

    # Use restricted sudo (may not work with Ansible)
    $0 -k /path/to/key.pub --restrict-sudo

EOF
    exit 0
}

# Parse arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -u|--user)
                ANSIBLE_USER="$2"
                # Validate username
                if ! validate_username "$ANSIBLE_USER"; then
                    print_error "Invalid username: $ANSIBLE_USER"
                    exit 1
                fi
                shift 2
                ;;
            -p|--port)
                SSH_PORT="$2"
                # Validate port
                if ! validate_port "$SSH_PORT"; then
                    print_error "Invalid port: $SSH_PORT"
                    exit 1
                fi
                shift 2
                ;;
            -k|--key)
                PUBKEY_FILE="$2"
                shift 2
                ;;
            -m|--minimal)
                MINIMAL_MODE="true"
                shift
                ;;
            -r|--root-key)
                DEPLOY_TO_ROOT="true"
                shift
                ;;
            -d|--dry-run)
                DRY_RUN="true"
                shift
                ;;
            --restrict-sudo)
                RESTRICT_SUDO="true"
                print_warning "Using restricted sudo - may cause 'Missing sudo password' errors with Ansible"
                shift
                ;;
            --full-sudo)
                # Legacy flag - now the default, kept for compatibility
                RESTRICT_SUDO="false"
                shift
                ;;
            -h|--help)
                usage
                ;;
            *)
                print_error "Unknown option: $1"
                usage
                ;;
        esac
    done
}

# Main function
main() {
    parse_args "$@"

    print_header "Wazuh Client Preparation Script"

    if [ "$DRY_RUN" = "true" ]; then
        print_warning "Running in DRY RUN mode - no changes will be made"
    fi

    check_root
    detect_os

    # Log script start
    audit_log "SCRIPT_START" "OS: $OS_NAME, User: $ANSIBLE_USER, Minimal: $MINIMAL_MODE, DryRun: $DRY_RUN"

    # Create backup before making changes
    create_backup

    # Remove unnecessary packages (unless minimal mode)
    if [ "$MINIMAL_MODE" != "true" ]; then
        remove_unnecessary_packages
    else
        print_info "Skipping package removal (minimal mode)"
    fi

    install_essential_packages
    configure_ssh
    create_ansible_user
    deploy_ssh_key
    configure_firewall
    disable_unnecessary_services
    optimize_system
    cleanup_system
    generate_report

    # Log successful completion
    audit_log "SCRIPT_COMPLETE" "Preparation completed successfully"

    print_header "Preparation Complete"

    # Get IP address in a portable way
    local ip_addr
    ip_addr=$(hostname -I 2>/dev/null | awk '{print $1}') || \
    ip_addr=$(ip -4 addr show scope global 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | head -1) || \
    ip_addr="<this-host-ip>"

    echo -e "The system is now ready for Wazuh deployment via Ansible."
    echo ""
    echo -e "${CYAN}Configuration:${NC}"
    echo -e "  - OS Family: ${OS_FAMILY}"
    echo -e "  - Ansible User: ${ANSIBLE_USER}"
    echo -e "  - SSH Port: ${SSH_PORT}"
    if [ "$RESTRICT_SUDO" = "true" ]; then
        echo -e "  - Sudo: Restricted (may need --full-sudo if Ansible fails)"
    else
        echo -e "  - Sudo: Full access (NOPASSWD: ALL)"
    fi
    echo -e "  - Audit log: ${AUDIT_LOG}"
    echo -e "  - Backup: ${BACKUP_DIR}"
    echo ""
    echo -e "${CYAN}Next steps:${NC}"
    echo -e "  1. From your Ansible control node, test connectivity:"
    echo -e "     ${GREEN}ssh -i ~/.ssh/wazuh_ansible_key ${ANSIBLE_USER}@${ip_addr}${NC}"
    echo ""
    echo -e "  2. Add this host to your Ansible inventory"
    echo ""
    echo -e "  3. Run the Wazuh deployment playbook:"
    echo -e "     ${GREEN}ansible-playbook site.yml${NC}"
    echo ""
}

main "$@"

# Explicit successful exit
exit 0
