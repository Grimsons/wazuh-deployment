#!/bin/bash
# Wazuh Deployment - Password and Key Generation Functions

# Generate cryptographically secure random password
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
    # Use /dev/urandom for cryptographically secure symbol selection
    local symbol_idx
    symbol_idx=$(head -c 4 /dev/urandom | od -An -tu4 | tr -d ' ')
    local symbol="${symbols:$((symbol_idx % ${#symbols})):1}"

    # Fallback if any character generation failed
    [ -z "$upper" ] && upper="A"
    [ -z "$lower" ] && lower="z"
    [ -z "$number" ] && number="7"

    password="${password}${upper}${lower}${number}${symbol}"

    # Shuffle the password to distribute special chars
    password=$(echo "$password" | fold -w1 | shuf | tr -d '\n')

    echo "$password"
}

# Generate hex key (for cluster keys)
generate_hex_key() {
    local length="${1:-32}"
    local key=""

    if command -v openssl &>/dev/null; then
        key=$(openssl rand -hex $((length / 2)) 2>/dev/null)
    fi

    if [ -z "$key" ] || [ ${#key} -lt "$length" ]; then
        # Fallback to /dev/urandom
        key=$(head -c $((length / 2)) /dev/urandom 2>/dev/null | od -An -tx1 | tr -d ' \n' | head -c "$length")
    fi

    if [ -z "$key" ] || [ ${#key} -lt "$length" ]; then
        return 1
    fi

    echo "$key"
}

# Generate vault password
generate_vault_password() {
    generate_password 32
}

# Generate SSH key pair
generate_ssh_keypair() {
    local key_path="$1"
    local comment="${2:-wazuh-ansible-deploy}"

    if [ -f "$key_path" ]; then
        return 1  # Key already exists
    fi

    mkdir -p "$(dirname "$key_path")"
    ssh-keygen -t ed25519 -f "$key_path" -N "" -C "$comment" >/dev/null 2>&1
    chmod 600 "$key_path"
    chmod 644 "${key_path}.pub"

    return 0
}

# Generate unique deployment ID
generate_deployment_id() {
    local prefix="${1:-wazuh}"
    local timestamp=$(date +%Y%m%d%H%M%S)
    local random=$(head -c 4 /dev/urandom | od -An -tx1 | tr -d ' \n')
    echo "${prefix}-${timestamp}-${random}"
}
