#!/bin/bash

# Wazuh Deployment - Quick Status Check Script
# Displays status of all Wazuh services across the infrastructure
#
# Usage:
#   ./scripts/status.sh              # Check all hosts
#   ./scripts/status.sh indexer      # Check only indexers
#   ./scripts/status.sh manager      # Check only managers
#   ./scripts/status.sh dashboard    # Check only dashboards
#   ./scripts/status.sh agent        # Check only agents
#   ./scripts/status.sh --local      # Check local services only

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
BOLD='\033[1m'
NC='\033[0m'

# Service status symbols
STATUS_OK="${GREEN}●${NC}"
STATUS_FAIL="${RED}●${NC}"
STATUS_WARN="${YELLOW}●${NC}"
STATUS_UNKNOWN="${GRAY}○${NC}"

print_header() {
    echo -e "\n${CYAN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${NC}\n"
}

print_section() {
    echo -e "\n${BOLD}$1${NC}"
    echo -e "${GRAY}───────────────────────────────────────────────────────────────${NC}"
}

# Check if we have ansible and inventory
check_prerequisites() {
    if ! command -v ansible &>/dev/null; then
        echo -e "${RED}Error: ansible not found${NC}"
        exit 1
    fi

    if [[ ! -f "$PROJECT_DIR/inventory/hosts.yml" ]]; then
        echo -e "${YELLOW}Warning: inventory/hosts.yml not found${NC}"
        echo -e "Run setup.sh or setup-tui.sh first to generate inventory"
        exit 1
    fi
}

# Get service status from a host
get_service_status() {
    local host="$1"
    local service="$2"

    local result
    result=$(ansible "$host" -m shell -a "systemctl is-active $service 2>/dev/null || echo 'inactive'" \
        --one-line -i "$PROJECT_DIR/inventory/hosts.yml" 2>/dev/null | tail -1)

    if echo "$result" | grep -q "UNREACHABLE"; then
        echo "unreachable"
    elif echo "$result" | grep -qw "inactive"; then
        echo "inactive"
    elif echo "$result" | grep -qw "active"; then
        echo "active"
    else
        echo "unknown"
    fi
}

# Format status for display
format_status() {
    local status="$1"
    case "$status" in
        active)      echo -e "${STATUS_OK} active" ;;
        inactive)    echo -e "${STATUS_FAIL} inactive" ;;
        unreachable) echo -e "${STATUS_WARN} unreachable" ;;
        *)           echo -e "${STATUS_UNKNOWN} unknown" ;;
    esac
}

# Check local services
check_local() {
    print_section "Local Services"

    for service in wazuh-indexer wazuh-manager wazuh-dashboard wazuh-agent; do
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            echo -e "  ${STATUS_OK} $service"
        elif systemctl list-unit-files "$service.service" &>/dev/null; then
            echo -e "  ${STATUS_FAIL} $service"
        fi
    done
}

# Check indexer health via API
# NOTE: Credentials are not available in this script (no vault access).
# The health check uses OS-level service state only. For full API health
# including cluster status, use: ansible-playbook playbooks/health-check.yml
check_indexer_api() {
    local host="$1"
    print_section "Indexer Cluster Health"

    # Check service state via systemd — does not require credentials
    local svc_state
    svc_state=$(ansible "$host" -m shell \
        -a "systemctl is-active wazuh-indexer 2>/dev/null || echo inactive" \
        --one-line -i "$PROJECT_DIR/inventory/hosts.yml" 2>/dev/null | tail -1 | awk '{print $NF}')

    # Check that port 9200 is listening (connectivity, no auth required)
    local port_open
    port_open=$(ansible "$host" -m shell \
        -a "ss -tlnp 2>/dev/null | grep -q ':9200' && echo open || echo closed" \
        --one-line -i "$PROJECT_DIR/inventory/hosts.yml" 2>/dev/null | tail -1 | awk '{print $NF}')

    case "$svc_state" in
        active)  echo -e "  ${STATUS_OK} Service: ${GREEN}active${NC}" ;;
        *)       echo -e "  ${STATUS_FAIL} Service: ${RED}${svc_state:-unknown}${NC}" ;;
    esac

    case "$port_open" in
        open)   echo -e "  ${STATUS_OK} Port 9200: ${GREEN}listening${NC}" ;;
        *)      echo -e "  ${STATUS_FAIL} Port 9200: ${RED}not listening${NC}" ;;
    esac

    echo -e "  ${STATUS_UNKNOWN} Cluster health: run 'ansible-playbook playbooks/health-check.yml' for full API check"
}

# Check hosts in a group
check_group() {
    local group="$1"
    local service="$2"
    local display_name="$3"

    print_section "$display_name"

    # Get hosts in group
    local hosts
    hosts=$(ansible "$group" --list-hosts -i "$PROJECT_DIR/inventory/hosts.yml" 2>/dev/null | tail -n +2 | tr -d ' ')

    if [[ -z "$hosts" ]]; then
        echo -e "  ${GRAY}No hosts in group${NC}"
        return
    fi

    for host in $hosts; do
        local status
        status=$(get_service_status "$host" "$service")
        printf "  %-30s %s\n" "$host:" "$(format_status "$status")"
    done
}

# Main status check
check_all() {
    print_header "Wazuh Infrastructure Status"
    echo -e "${GRAY}Timestamp: $(date '+%Y-%m-%d %H:%M:%S')${NC}"

    check_group "wazuh_indexers" "wazuh-indexer" "Indexers"
    check_group "wazuh_managers" "wazuh-manager" "Managers"
    check_group "wazuh_dashboards" "wazuh-dashboard" "Dashboards"

    # Check agents if group exists
    if ansible wazuh_agents --list-hosts -i "$PROJECT_DIR/inventory/hosts.yml" &>/dev/null; then
        check_group "wazuh_agents" "wazuh-agent" "Agents"
    fi

    echo ""
}

# Quick summary
show_summary() {
    echo ""
    echo -e "${BOLD}Legend:${NC} ${STATUS_OK} Running  ${STATUS_FAIL} Stopped  ${STATUS_WARN} Unreachable  ${STATUS_UNKNOWN} Unknown"
    echo ""
    echo -e "${GRAY}For detailed health check: ansible-playbook playbooks/health-check.yml${NC}"
}

# Parse arguments
main() {
    local target="${1:-all}"

    case "$target" in
        --local|-l)
            check_local
            ;;
        indexer|indexers)
            check_prerequisites
            check_group "wazuh_indexers" "wazuh-indexer" "Indexers"
            show_summary
            ;;
        manager|managers)
            check_prerequisites
            check_group "wazuh_managers" "wazuh-manager" "Managers"
            show_summary
            ;;
        dashboard|dashboards)
            check_prerequisites
            check_group "wazuh_dashboards" "wazuh-dashboard" "Dashboards"
            show_summary
            ;;
        agent|agents)
            check_prerequisites
            check_group "wazuh_agents" "wazuh-agent" "Agents"
            show_summary
            ;;
        all|"")
            check_prerequisites
            check_all
            show_summary
            ;;
        --help|-h)
            echo "Usage: $0 [COMPONENT] [OPTIONS]"
            echo ""
            echo "Components:"
            echo "  indexer     Check only indexer nodes"
            echo "  manager     Check only manager nodes"
            echo "  dashboard   Check only dashboard nodes"
            echo "  agent       Check only agent hosts"
            echo "  all         Check all components (default)"
            echo ""
            echo "Options:"
            echo "  --local, -l   Check local services only (no SSH)"
            echo "  --help, -h    Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                # Check all services"
            echo "  $0 manager        # Check only managers"
            echo "  $0 --local        # Check local services"
            ;;
        *)
            echo -e "${RED}Unknown option: $target${NC}"
            echo "Run '$0 --help' for usage"
            exit 1
            ;;
    esac
}

main "$@"
