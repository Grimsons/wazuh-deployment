#!/bin/bash

# Wazuh Certificate Generation Script
# Generates TLS certificates for Wazuh components.
#
# Key algorithm choices:
#   CA:   RSA-4096, 10-year validity  (long-lived trust anchor)
#   Leaf: ECDSA P-256, 2-year validity (short-lived, modern algorithm)
#
# Distinguished Name fields are read from group_vars/all/main.yml so each
# deployment has a unique DN and certificates are identifiable in logs.

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CERTS_DIR="${SCRIPT_DIR}/files/certs"
CONFIG_FILE="${SCRIPT_DIR}/group_vars/all/main.yml"

# Cleanup temp files on exit/interrupt
cleanup() {
    rm -f "${CERTS_DIR}"/*.csr "${CERTS_DIR}"/*.ext
}
trap cleanup EXIT INT TERM

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

# Check for required tools
check_requirements() {
    if ! command -v openssl &> /dev/null; then
        print_error "OpenSSL is required but not installed."
        exit 1
    fi
    if ! command -v yq &> /dev/null; then
        print_error "yq is required for reliable YAML parsing. Install it:"
        print_info "  sudo wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 && sudo chmod +x /usr/local/bin/yq"
        exit 1
    fi
}

# Parse nodes from config
parse_nodes() {
    if [ ! -f "$CONFIG_FILE" ]; then
        print_error "Configuration file not found: $CONFIG_FILE"
        print_info "Please run ./setup.sh first to generate the configuration."
        exit 1
    fi
}

# Read DN fields from group_vars so every deployment has unique, identifiable certs
load_dn_fields() {
    _dn_read() { yq e ".${1} // \"\"" "$CONFIG_FILE" 2>/dev/null | tr -d '"'; }
    CERT_COUNTRY="${CERT_COUNTRY:-$(_dn_read wazuh_cert_country)}"
    CERT_STATE="${CERT_STATE:-$(_dn_read wazuh_cert_state)}"
    CERT_LOCATION="${CERT_LOCATION:-$(_dn_read wazuh_cert_location)}"
    CERT_ORG="${CERT_ORG:-$(_dn_read wazuh_cert_org)}"
    CERT_OU="${CERT_OU:-$(_dn_read wazuh_cert_ou)}"
    # Fall back to defaults if not set in config
    CERT_COUNTRY="${CERT_COUNTRY:-US}"
    CERT_STATE="${CERT_STATE:-California}"
    CERT_LOCATION="${CERT_LOCATION:-San Jose}"
    CERT_ORG="${CERT_ORG:-Wazuh Deployment}"
    CERT_OU="${CERT_OU:-Security Operations}"
    CERT_DN_BASE="/C=${CERT_COUNTRY}/ST=${CERT_STATE}/L=${CERT_LOCATION}/O=${CERT_ORG}/OU=${CERT_OU}"
}

# Create certificates directory
create_dirs() {
    mkdir -p "$CERTS_DIR"
    print_success "Created certificates directory: $CERTS_DIR"
}

# Generate Root CA — RSA-4096, 10-year validity (long-lived trust anchor)
generate_root_ca() {
    print_info "Generating Root CA (RSA-4096, ${CA_DAYS}-day validity)..."

    openssl genrsa -out "${CERTS_DIR}/root-ca-key.pem" 4096 2>/dev/null
    chmod 400 "${CERTS_DIR}/root-ca-key.pem"

    openssl req -new -x509 -sha256 -days "${CA_DAYS}" \
        -key "${CERTS_DIR}/root-ca-key.pem" \
        -out "${CERTS_DIR}/root-ca.pem" \
        -subj "${CERT_DN_BASE}/CN=Wazuh Root CA" \
        2>/dev/null

    print_success "Generated Root CA: ${CERT_DN_BASE}/CN=Wazuh Root CA"
}

# Generate Admin certificate — ECDSA P-256, 2-year validity
generate_admin_cert() {
    print_info "Generating Admin certificate (ECDSA P-256, ${LEAF_DAYS}-day validity)..."

    openssl ecparam -genkey -name prime256v1 -noout \
        -out "${CERTS_DIR}/admin-key.pem" 2>/dev/null
    chmod 400 "${CERTS_DIR}/admin-key.pem"

    openssl req -new -sha256 \
        -key "${CERTS_DIR}/admin-key.pem" \
        -out "${CERTS_DIR}/admin.csr" \
        -subj "${CERT_DN_BASE}/CN=admin" \
        2>/dev/null

    cat > "${CERTS_DIR}/admin.ext" << 'ADMIN_EXT'
basicConstraints=CA:FALSE
keyUsage=critical,digitalSignature,keyEncipherment
extendedKeyUsage=clientAuth
subjectAltName=DNS:admin
ADMIN_EXT

    openssl x509 -req -sha256 -days "${LEAF_DAYS}" \
        -in "${CERTS_DIR}/admin.csr" \
        -CA "${CERTS_DIR}/root-ca.pem" \
        -CAkey "${CERTS_DIR}/root-ca-key.pem" \
        -set_serial "0x$(openssl rand -hex 16)" \
        -out "${CERTS_DIR}/admin.pem" \
        -extfile "${CERTS_DIR}/admin.ext" \
        2>/dev/null

    print_success "Generated Admin certificate"
}

# Generate certificate for a node — ECDSA P-256, 2-year validity, with SANs
generate_node_cert() {
    local node_name="$1"
    local node_ip="$2"
    local san_entries="$3"

    print_info "Generating certificate for: $node_name ($node_ip) [ECDSA P-256, ${LEAF_DAYS} days]"

    cat > "${CERTS_DIR}/${node_name}.ext" << EOF
authorityKeyIdentifier=keyid,issuer
basicConstraints=CA:FALSE
keyUsage = digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = ${node_name}
DNS.2 = localhost
IP.1 = ${node_ip}
IP.2 = 127.0.0.1
${san_entries}
EOF

    openssl ecparam -genkey -name prime256v1 -noout \
        -out "${CERTS_DIR}/${node_name}-key.pem" 2>/dev/null
    chmod 400 "${CERTS_DIR}/${node_name}-key.pem"

    openssl req -new -sha256 \
        -key "${CERTS_DIR}/${node_name}-key.pem" \
        -out "${CERTS_DIR}/${node_name}.csr" \
        -subj "${CERT_DN_BASE}/CN=${node_name}" \
        2>/dev/null

    openssl x509 -req -sha256 -days "${LEAF_DAYS}" \
        -in "${CERTS_DIR}/${node_name}.csr" \
        -CA "${CERTS_DIR}/root-ca.pem" \
        -CAkey "${CERTS_DIR}/root-ca-key.pem" \
        -set_serial "0x$(openssl rand -hex 16)" \
        -out "${CERTS_DIR}/${node_name}.pem" \
        -extfile "${CERTS_DIR}/${node_name}.ext" \
        2>/dev/null

    print_success "Generated certificate for: $node_name"
}

# Generate Dashboard certificate
generate_dashboard_cert() {
    print_info "Generating Dashboard certificate..."
    # Use localhost as default SAN - override with actual dashboard IP from inventory
    local dashboard_ip="${DASHBOARD_IP:-127.0.0.1}"
    generate_node_cert "dashboard" "$dashboard_ip" ""
}

# Main function
main() {
    print_header "Wazuh Certificate Generator"

    check_requirements
    create_dirs
    parse_nodes
    load_dn_fields

    # Generate Root CA
    generate_root_ca

    # Generate Admin certificate
    generate_admin_cert

    # Generate Dashboard certificate
    generate_dashboard_cert

    echo
    print_info "Parsing node configuration..."
    echo

    # Read indexer nodes from config and generate certs
    if grep -q "wazuh_indexer_nodes:" "$CONFIG_FILE"; then
        print_info "Generating Indexer certificates..."
        local i=1
        while IFS= read -r line; do
            if [[ "$line" =~ ip:\ *(.+) ]]; then
                local ip="${BASH_REMATCH[1]}"
                ip=$(echo "$ip" | tr -d '"' | tr -d "'")
                generate_node_cert "indexer-${i}" "$ip" ""
                ((i++))
            fi
        done < <(sed -n '/wazuh_indexer_nodes:/,/^[a-z]/p' "$CONFIG_FILE" | sed '$d')
    fi

    # Read manager nodes from config and generate certs
    if grep -q "wazuh_manager_nodes:" "$CONFIG_FILE"; then
        print_info "Generating Manager certificates..."
        local i=1
        while IFS= read -r line; do
            if [[ "$line" =~ ip:\ *(.+) ]]; then
                local ip="${BASH_REMATCH[1]}"
                ip=$(echo "$ip" | tr -d '"' | tr -d "'")
                generate_node_cert "manager-${i}" "$ip" ""
                ((i++))
            fi
        done < <(sed -n '/wazuh_manager_nodes:/,/^[a-z]/p' "$CONFIG_FILE" | sed '$d')
    fi

    print_header "Certificate Generation Complete"

    echo -e "Certificates have been generated in: ${CYAN}${CERTS_DIR}${NC}"
    echo
    echo "Generated files:"
    ls -la "$CERTS_DIR"
    echo
    print_info "Remember to copy these certificates to the appropriate locations"
    print_info "or update the certificate paths in your configuration."
    echo
    print_warning "SECURITY: Private key files (*-key.pem) are unencrypted!"
    print_warning "Protect them with appropriate filesystem permissions (chmod 600)."
    print_warning "These files are gitignored but ensure they are never committed or"
    print_warning "transmitted over insecure channels."
}

main "$@"
