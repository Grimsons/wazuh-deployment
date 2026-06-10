#!/bin/bash
# Wazuh Deployment - Color Definitions and Print Functions

# Colors for output
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export CYAN='\033[0;36m'
export MAGENTA='\033[0;35m'
export BOLD='\033[1m'
export DIM='\033[2m'
export NC='\033[0m' # No Color

# Print functions
print_header() {
    echo -e "\n${BLUE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}\n"
}

print_section() {
    echo -e "\n${GREEN}▶ $1${NC}\n"
}

print_subsection() {
    echo -e "${CYAN}  ├─ $1${NC}"
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

print_debug() {
    if [[ "${DEBUG:-false}" == "true" ]]; then
        echo -e "${DIM}[DEBUG] $1${NC}"
    fi
}

# Progress indicator
print_step() {
    local current="$1"
    local total="$2"
    local message="$3"
    echo -e "${CYAN}[${current}/${total}]${NC} ${message}"
}

# Box drawing for summaries
print_box_start() {
    local title="$1"
    echo -e "${BLUE}┌─────────────────────────────────────────────────────────────┐${NC}"
    if [[ -n "$title" ]]; then
        echo -e "${BLUE}│${NC} ${BOLD}${title}${NC}"
        echo -e "${BLUE}├─────────────────────────────────────────────────────────────┤${NC}"
    fi
}

print_box_line() {
    local label="$1"
    local value="$2"
    printf "${BLUE}│${NC} %-20s ${YELLOW}%s${NC}\n" "$label:" "$value"
}

print_box_end() {
    echo -e "${BLUE}└─────────────────────────────────────────────────────────────┘${NC}"
}
