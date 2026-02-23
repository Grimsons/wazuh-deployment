#!/bin/bash

# Wazuh Deployment with Rollback Support
# Creates automatic pre-deployment snapshot for safe rollback
#
# Usage:
#   ./scripts/deploy-with-rollback.sh                    # Full deployment
#   ./scripts/deploy-with-rollback.sh --rollback         # Rollback to last deployment
#   ./scripts/deploy-with-rollback.sh --list             # List available rollback points
#   ./scripts/deploy-with-rollback.sh --playbook FILE    # Deploy specific playbook

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ROLLBACK_DIR="$PROJECT_DIR/rollback-points"
LATEST_ROLLBACK_FILE="$ROLLBACK_DIR/.latest"

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

# Create pre-deployment snapshot
create_snapshot() {
    local timestamp=$(date +%Y%m%dT%H%M%S)
    local snapshot_dir="$ROLLBACK_DIR/$timestamp"

    # Send status messages to stderr so stdout only contains the timestamp
    print_header "Creating Pre-Deployment Snapshot" >&2

    mkdir -p "$snapshot_dir"

    # Run backup playbook
    print_info "Running backup playbook..." >&2
    cd "$PROJECT_DIR"

    if ansible-playbook playbooks/backup.yml \
        -e "backup_dest=$ROLLBACK_DIR" \
        -e "backup_timestamp=$timestamp" \
        -e "backup_indexer=true" \
        -e "backup_manager=true" \
        -e "backup_dashboard=true" >&2; then
        print_success "Snapshot created: $timestamp" >&2
        echo "$timestamp" > "$LATEST_ROLLBACK_FILE"
        echo "$timestamp"
    else
        print_error "Failed to create snapshot"
        rm -rf "$snapshot_dir"
        return 1
    fi
}

# List available rollback points
list_rollback_points() {
    print_header "Available Rollback Points"

    if [ ! -d "$ROLLBACK_DIR" ]; then
        print_info "No rollback points found"
        return
    fi

    local latest=""
    if [ -f "$LATEST_ROLLBACK_FILE" ]; then
        latest=$(cat "$LATEST_ROLLBACK_FILE")
    fi

    local count=0
    for point in $(ls -1r "$ROLLBACK_DIR" 2>/dev/null | grep -E '^[0-9]{8}T[0-9]{6}$'); do
        count=$((count + 1))
        local date_formatted=$(echo "$point" | sed 's/T/ /' | sed 's/\([0-9]\{4\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)/\1-\2-\3/' | sed 's/\([0-9]\{2\}\)\([0-9]\{2\}\)\([0-9]\{2\}\)$/\1:\2:\3/')

        if [ "$point" = "$latest" ]; then
            echo -e "  ${GREEN}→ $point${NC} ($date_formatted) [LATEST]"
        else
            echo "    $point ($date_formatted)"
        fi
    done

    if [ $count -eq 0 ]; then
        print_info "No rollback points found"
    else
        echo
        print_info "To rollback: $0 --rollback"
        print_info "To rollback to specific point: $0 --rollback --point TIMESTAMP"
    fi
}

# Perform rollback
do_rollback() {
    local rollback_point="$1"

    # If no point specified, use latest
    if [ -z "$rollback_point" ] && [ -f "$LATEST_ROLLBACK_FILE" ]; then
        rollback_point=$(cat "$LATEST_ROLLBACK_FILE")
    fi

    if [ -z "$rollback_point" ]; then
        print_error "No rollback point specified and no latest point found"
        print_info "Use: $0 --list to see available points"
        exit 1
    fi

    local restore_path="$ROLLBACK_DIR/$rollback_point"
    if [ ! -d "$restore_path" ]; then
        print_error "Rollback point not found: $rollback_point"
        exit 1
    fi

    print_header "Rolling Back to: $rollback_point"

    print_warning "This will restore all Wazuh components to the state before deployment."
    print_warning "Services will be restarted."
    echo
    read -p "Continue with rollback? (yes/no): " confirm

    if [ "$confirm" != "yes" ]; then
        print_info "Rollback cancelled"
        exit 0
    fi

    # Run restore playbook
    print_info "Running restore playbook..."
    cd "$PROJECT_DIR"

    if ansible-playbook playbooks/restore.yml \
        -e "restore_from=$rollback_point" \
        -e "backup_dest=$ROLLBACK_DIR" \
        -e "restart_services=true"; then
        print_success "Rollback completed successfully"
    else
        print_error "Rollback failed!"
        print_info "Manual intervention may be required"
        exit 1
    fi
}

# Main deployment with snapshot
do_deployment() {
    local playbook="${1:-site.yml}"
    shift || true
    local extra_args=("$@")

    print_header "Wazuh Deployment with Rollback Support"

    # Check if there are existing Wazuh installations
    print_info "Checking for existing installations..."

    cd "$PROJECT_DIR"
    local has_existing=false

    # Quick check for existing services
    if ansible all -m shell -a "systemctl is-active wazuh-manager wazuh-indexer wazuh-dashboard 2>/dev/null || true" 2>/dev/null | grep -q "active"; then
        has_existing=true
    fi

    if [ "$has_existing" = "true" ]; then
        print_info "Existing Wazuh installation detected"
        print_info "Creating pre-deployment snapshot for rollback..."
        echo

        local snapshot_timestamp
        snapshot_timestamp=$(create_snapshot)

        if [ $? -ne 0 ]; then
            print_error "Failed to create snapshot"
            read -p "Continue deployment without rollback point? (yes/no): " continue_anyway
            if [ "$continue_anyway" != "yes" ]; then
                exit 1
            fi
        else
            print_success "Rollback point created: $snapshot_timestamp"
            print_info "To rollback: $0 --rollback"
            echo
        fi
    else
        print_info "No existing installation detected, skipping snapshot"
    fi

    # Run pre-flight checks
    print_info "Running pre-flight checks..."
    if ! ansible-playbook playbooks/pre-flight-checks.yml --tags quick 2>&1; then
        print_error "Pre-flight checks failed"
        read -p "Continue anyway? (yes/no): " continue_anyway
        if [ "$continue_anyway" != "yes" ]; then
            exit 1
        fi
    fi

    # Run deployment
    print_header "Running Deployment"
    print_info "Playbook: $playbook"
    echo

    if ansible-playbook "$playbook" "${extra_args[@]}"; then
        print_success "Deployment completed successfully"
        echo
        print_info "If issues occur, rollback with: $0 --rollback"
    else
        print_error "Deployment failed!"
        echo
        if [ -f "$LATEST_ROLLBACK_FILE" ]; then
            print_warning "A rollback point is available"
            read -p "Do you want to rollback? (yes/no): " do_rollback_prompt
            if [ "$do_rollback_prompt" = "yes" ]; then
                do_rollback
            fi
        fi
        exit 1
    fi
}

# Clean old rollback points
cleanup_rollback_points() {
    local keep_count="${1:-5}"

    print_header "Cleaning Old Rollback Points"

    if [ ! -d "$ROLLBACK_DIR" ]; then
        print_info "No rollback points to clean"
        return
    fi

    local count=0
    for point in $(ls -1r "$ROLLBACK_DIR" 2>/dev/null | grep -E '^[0-9]{8}T[0-9]{6}$'); do
        count=$((count + 1))
        if [ $count -gt $keep_count ]; then
            print_info "Removing old rollback point: $point"
            rm -rf "$ROLLBACK_DIR/$point"
        fi
    done

    print_success "Kept $keep_count most recent rollback points"
}

# Show usage
usage() {
    echo "Wazuh Deployment with Rollback Support"
    echo ""
    echo "Usage: $0 [options]"
    echo ""
    echo "Options:"
    echo "  --rollback          Rollback to the last deployment state"
    echo "  --point TIMESTAMP   Rollback to a specific point"
    echo "  --list              List available rollback points"
    echo "  --playbook FILE     Use specific playbook (default: site.yml)"
    echo "  --cleanup [N]       Remove old rollback points, keep N most recent (default: 5)"
    echo "  --help              Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                           # Deploy with automatic snapshot"
    echo "  $0 --rollback                # Rollback to last state"
    echo "  $0 --rollback --point 20260120T143000"
    echo "  $0 --playbook playbooks/wazuh-manager.yml"
    echo "  $0 --list                    # Show rollback points"
    echo "  $0 --cleanup 3               # Keep only 3 most recent points"
}

# Parse arguments
ROLLBACK_MODE=false
ROLLBACK_POINT=""
PLAYBOOK="site.yml"
LIST_MODE=false
CLEANUP_MODE=false
CLEANUP_KEEP=5

while [[ $# -gt 0 ]]; do
    case $1 in
        --rollback)
            ROLLBACK_MODE=true
            shift
            ;;
        --point)
            ROLLBACK_POINT="$2"
            shift 2
            ;;
        --list)
            LIST_MODE=true
            shift
            ;;
        --playbook)
            PLAYBOOK="$2"
            shift 2
            ;;
        --cleanup)
            CLEANUP_MODE=true
            if [[ "$2" =~ ^[0-9]+$ ]]; then
                CLEANUP_KEEP="$2"
                shift
            fi
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            # Pass through to ansible
            break
            ;;
    esac
done

# Main
mkdir -p "$ROLLBACK_DIR"

if [ "$LIST_MODE" = "true" ]; then
    list_rollback_points
elif [ "$ROLLBACK_MODE" = "true" ]; then
    do_rollback "$ROLLBACK_POINT"
elif [ "$CLEANUP_MODE" = "true" ]; then
    cleanup_rollback_points "$CLEANUP_KEEP"
else
    do_deployment "$PLAYBOOK" "$@"
fi
