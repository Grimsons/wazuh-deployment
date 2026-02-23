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
check_indexer_api() {
    local host="$1"
    print_section "Indexer Cluster Health"

    # Try to get cluster health
    local health
    health=$(ansible "$host" -m shell -a "curl -s -k -u admin:\$(cat /etc/wazuh-indexer/opensearch.yml 2>/dev/null | grep -A1 'admin:' | tail -1 | tr -d ' ') https://localhost:9200/_cluster/health 2>/dev/null || echo '{}')" \
        --one-line -i "$PROJECT_DIR/inventory/hosts.yml" 2>/dev/null | tail -1)

    if echo "$health" | grep -q '"status"'; then
        local status=$(echo "$health" | grep -o '"status":"[^"]*"' | cut -d'"' -f4)
        local nodes=$(echo "$health" | grep -o '"number_of_nodes":[0-9]*' | cut -d':' -f2)

        case "$status" in
            green)  echo -e "  ${STATUS_OK} Cluster: ${GREEN}green${NC} ($nodes nodes)" ;;
            yellow) echo -e "  ${STATUS_WARN} Cluster: ${YELLOW}yellow${NC} ($nodes nodes)" ;;
            red)    echo -e "  ${STATUS_FAIL} Cluster: ${RED}red${NC} ($nodes nodes)" ;;
            *)      echo -e "  ${STATUS_UNKNOWN} Cluster: unknown" ;;
        esac
    else
        echo -e "  ${STATUS_UNKNOWN} Could not query cluster health"
    fi
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
