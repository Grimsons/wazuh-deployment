#!/bin/bash
# Wazuh Deployment - Input Validation Functions

# Validate IPv4 address
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

# Validate hostname (RFC 1123)
validate_hostname() {
    local host="$1"
    # Valid hostname or IP
    if validate_ip "$host"; then
        return 0
    fi
    # RFC 1123 hostname validation
    [[ "$host" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]{0,253}[a-zA-Z0-9])?$ ]]
}

# Validate port number
validate_port() {
    local port="$1"
    [[ "$port" =~ ^[0-9]+$ ]] && (( port >= 1 && port <= 65535 ))
}

# Validate heap size format (e.g., "auto", "1g", "512m")
validate_heap_size() {
    local size="$1"
    [[ "$size" == "auto" ]] && return 0
    [[ "$size" =~ ^[0-9]+[gGmM]$ ]] && return 0
    return 1
}

# Validate email address
validate_email() {
    local email="$1"
    [[ "$email" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]
}

# Validate URL
validate_url() {
    local url="$1"
    [[ "$url" =~ ^https?://[A-Za-z0-9.-]+(/.*)?$ ]]
}

# Validate version format (e.g., 4.14.1)
validate_version() {
    local version="$1"
    [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

# Sanitize alphanumeric input (allow dots, hyphens, underscores)
sanitize_alphanum() {
    echo "$1" | tr -cd 'a-zA-Z0-9._-'
}

# Sanitize path (prevent traversal)
sanitize_path() {
    local path="$1"
    # Remove ../ sequences iteratively until none remain
    # Single-pass removal can leave traversal in crafted inputs like "..../"
    while [[ "$path" == *".."* ]]; do
        path="${path//\.\.\//}"
        path="${path//\.\./}"
    done
    echo "$path" | tr -cd 'a-zA-Z0-9._/-'
}

# Validate that a value is in a list of allowed values
validate_in_list() {
    local value="$1"
    shift
    local allowed=("$@")
    for item in "${allowed[@]}"; do
        [[ "$value" == "$item" ]] && return 0
    done
    return 1
}

# Validate integer in range
validate_int_range() {
    local value="$1"
    local min="$2"
    local max="$3"
    [[ "$value" =~ ^[0-9]+$ ]] || return 1
    (( value >= min && value <= max ))
}

# Check if command exists
command_exists() {
    command -v "$1" &>/dev/null
}

# Check if file exists and is readable
file_readable() {
    [[ -f "$1" && -r "$1" ]]
}

# Check if directory exists and is writable
dir_writable() {
    [[ -d "$1" && -w "$1" ]]
}
