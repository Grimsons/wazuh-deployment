#!/bin/bash
# Wazuh Deployment - User Interaction / Prompt Functions

# Source colors if not already loaded
[[ -z "$NC" ]] && source "$(dirname "${BASH_SOURCE[0]}")/colors.sh"

# Secure variable assignment without eval
set_var() {
    local var_name="$1"
    local value="$2"
    printf -v "$var_name" '%s' "$value"
}

# Prompt for input with default value
prompt_with_default() {
    local prompt="$1"
    local default="$2"
    local var_name="$3"
    local is_password="${4:-false}"
    local validator="${5:-}"
    local value=""

    while true; do
        if [ "$is_password" = "true" ]; then
            read -rsp "$(echo -e "${CYAN}$prompt ${NC}[${YELLOW}hidden${NC}]: ")" value
            echo
        else
            read -erp "$(echo -e "${CYAN}$prompt ${NC}[${YELLOW}$default${NC}]: ")" value
        fi

        if [ -z "$value" ]; then
            value="$default"
        fi

        # Validate if validator function provided
        if [[ -n "$validator" ]] && type -t "$validator" &>/dev/null; then
            if ! "$validator" "$value"; then
                print_error "Invalid input. Please try again."
                continue
            fi
        fi

        set_var "$var_name" "$value"
        return 0
    done
}

# Prompt for yes/no
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

# Prompt for selection from a list
prompt_select() {
    local prompt="$1"
    local var_name="$2"
    local default="$3"
    shift 3
    local options=("$@")

    echo -e "${CYAN}$prompt${NC}"
    local i=1
    for opt in "${options[@]}"; do
        if [[ "$i" == "$default" ]]; then
            echo -e "  ${YELLOW}$i)${NC} $opt ${GREEN}[default]${NC}"
        else
            echo -e "  ${YELLOW}$i)${NC} $opt"
        fi
        ((i++))
    done

    local selection=""
    while true; do
        read -erp "$(echo -e "${CYAN}Select option ${NC}[${YELLOW}$default${NC}]: ")" selection

        if [[ -z "$selection" ]]; then
            selection="$default"
        fi

        if [[ "$selection" =~ ^[0-9]+$ ]] && (( selection >= 1 && selection <= ${#options[@]} )); then
            set_var "$var_name" "${options[$((selection-1))]}"
            return 0
        else
            print_error "Invalid selection. Please enter a number between 1 and ${#options[@]}"
        fi
    done
}

# Prompt for multiple hosts (one per line)
prompt_hosts() {
    local prompt="$1"
    local var_name="$2"
    local min_hosts="${3:-1}"
    local hosts=()

    echo -e "${CYAN}$prompt${NC}"
    echo -e "${YELLOW}Enter hostnames/IPs one per line. Enter empty line when done.${NC}"
    if (( min_hosts > 0 )); then
        echo -e "${DIM}(Minimum $min_hosts host(s) required)${NC}"
    fi

    local count=1
    while true; do
        read -erp "  Host $count: " host
        if [ -z "$host" ]; then
            if (( ${#hosts[@]} < min_hosts )); then
                print_error "At least $min_hosts host(s) required!"
                continue
            fi
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

    # Return space-separated list
    printf -v "$var_name" '%s' "${hosts[*]}"
}

# Prompt for confirmation before proceeding
prompt_confirm() {
    local message="$1"
    local default="${2:-no}"
    local response=""

    if [[ "$default" == "yes" ]]; then
        read -erp "$(echo -e "${YELLOW}$message ${NC}[${GREEN}Y${NC}/n]: ")" response
        [[ -z "$response" || "${response,,}" =~ ^(y|yes)$ ]]
    else
        read -erp "$(echo -e "${YELLOW}$message ${NC}[y/${GREEN}N${NC}]: ")" response
        [[ "${response,,}" =~ ^(y|yes)$ ]]
    fi
}

# Prompt with auto-complete suggestions (basic)
prompt_with_suggestions() {
    local prompt="$1"
    local var_name="$2"
    local default="$3"
    shift 3
    local suggestions=("$@")

    echo -e "${DIM}Suggestions: ${suggestions[*]}${NC}"
    prompt_with_default "$prompt" "$default" "$var_name"
}

# Press any key to continue
press_any_key() {
    local message="${1:-Press any key to continue...}"
    read -rsn1 -p "$(echo -e "${DIM}$message${NC}")"
    echo
}
