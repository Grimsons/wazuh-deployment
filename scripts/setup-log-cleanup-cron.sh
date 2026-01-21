#!/bin/bash

# Setup Wazuh Log Cleanup Cron Job
# Configures automated log cleanup on Wazuh Manager to prevent disk space issues
#
# Usage:
#   ./scripts/setup-log-cleanup-cron.sh                    # Daily at 3 AM, keep 30 days
#   ./scripts/setup-log-cleanup-cron.sh --days 14          # Keep only 14 days of logs
#   ./scripts/setup-log-cleanup-cron.sh --weekly           # Run weekly instead of daily
#   ./scripts/setup-log-cleanup-cron.sh --remove           # Remove cron job

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CRON_ID="wazuh-log-cleanup"
LOG_DIR="$PROJECT_DIR/logs"

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

# Default settings
RETENTION_DAYS=30
SCHEDULE_TYPE="daily"
SCHEDULE_HOUR="3"
SCHEDULE_MINUTE="30"
SCHEDULE_DAY="0"  # Sunday
CLEANUP_ARCHIVES=true
CLEANUP_ALERTS=true
CLEANUP_OSSEC_LOGS=true
CLEANUP_FIREWALL_LOGS=true
REMOVE_CRON=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --days)
            RETENTION_DAYS="$2"
            shift 2
            ;;
        --daily)
            SCHEDULE_TYPE="daily"
            shift
            ;;
        --weekly)
            SCHEDULE_TYPE="weekly"
            shift
            ;;
        --hour)
            SCHEDULE_HOUR="$2"
            shift 2
            ;;
        --minute)
            SCHEDULE_MINUTE="$2"
            shift 2
            ;;
        --day)
            SCHEDULE_DAY="$2"
            shift 2
            ;;
        --no-archives)
            CLEANUP_ARCHIVES=false
            shift
            ;;
        --no-alerts)
            CLEANUP_ALERTS=false
            shift
            ;;
        --no-ossec-logs)
            CLEANUP_OSSEC_LOGS=false
            shift
            ;;
        --no-firewall)
            CLEANUP_FIREWALL_LOGS=false
            shift
            ;;
        --remove)
            REMOVE_CRON=true
            shift
            ;;
        --help|-h)
            echo "Setup Wazuh Log Cleanup Cron Job"
            echo ""
            echo "Usage: $0 [options]"
            echo ""
            echo "Retention Options:"
            echo "  --days N           Keep logs for N days (default: 30)"
            echo ""
            echo "Schedule Options:"
            echo "  --daily            Run daily (default)"
            echo "  --weekly           Run weekly (Sunday)"
            echo "  --hour H           Hour to run (0-23, default: 3)"
            echo "  --minute M         Minute to run (0-59, default: 30)"
            echo "  --day D            Day for weekly (0=Sun, 1=Mon..., default: 0)"
            echo ""
            echo "Cleanup Options:"
            echo "  --no-archives      Skip archive log cleanup"
            echo "  --no-alerts        Skip alert log cleanup"
            echo "  --no-ossec-logs    Skip ossec.log cleanup"
            echo "  --no-firewall      Skip firewall log cleanup"
            echo ""
            echo "Other Options:"
            echo "  --remove           Remove existing cron job"
            echo "  --help             Show this help"
            echo ""
            echo "Examples:"
            echo "  $0 --days 14                    # Daily cleanup, keep 14 days"
            echo "  $0 --weekly --days 7            # Weekly cleanup, keep 7 days"
            echo "  $0 --days 30 --no-archives      # Daily, keep 30 days, skip archives"
            echo ""
            echo "Log directories cleaned:"
            echo "  /var/ossec/logs/archives/       Archive logs (raw events)"
            echo "  /var/ossec/logs/alerts/         Alert logs"
            echo "  /var/ossec/logs/                Rotated ossec.log files"
            echo "  /var/ossec/logs/firewall/       Firewall logs"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Remove existing cron job
remove_cron() {
    print_info "Removing existing log cleanup cron job..."
    crontab -l 2>/dev/null | grep -v "$CRON_ID" | crontab - 2>/dev/null || true
    print_success "Log cleanup cron job removed"
}

if [ "$REMOVE_CRON" = "true" ]; then
    remove_cron
    exit 0
fi

print_header "Wazuh Log Cleanup Cron Setup"

# Create log directory
mkdir -p "$LOG_DIR"

# Build cron schedule
case $SCHEDULE_TYPE in
    daily)
        CRON_SCHEDULE="$SCHEDULE_MINUTE $SCHEDULE_HOUR * * *"
        SCHEDULE_DESC="Daily at $SCHEDULE_HOUR:$(printf '%02d' $SCHEDULE_MINUTE)"
        ;;
    weekly)
        CRON_SCHEDULE="$SCHEDULE_MINUTE $SCHEDULE_HOUR * * $SCHEDULE_DAY"
        DAYS=("Sunday" "Monday" "Tuesday" "Wednesday" "Thursday" "Friday" "Saturday")
        SCHEDULE_DESC="Weekly on ${DAYS[$SCHEDULE_DAY]} at $SCHEDULE_HOUR:$(printf '%02d' $SCHEDULE_MINUTE)"
        ;;
esac

# Build ansible-playbook command arguments
CLEANUP_ARGS="-e log_retention_days=$RETENTION_DAYS"
[ "$CLEANUP_ARCHIVES" = "false" ] && CLEANUP_ARGS="$CLEANUP_ARGS -e cleanup_archives=false"
[ "$CLEANUP_ALERTS" = "false" ] && CLEANUP_ARGS="$CLEANUP_ARGS -e cleanup_alerts=false"
[ "$CLEANUP_OSSEC_LOGS" = "false" ] && CLEANUP_ARGS="$CLEANUP_ARGS -e cleanup_ossec_logs=false"
[ "$CLEANUP_FIREWALL_LOGS" = "false" ] && CLEANUP_ARGS="$CLEANUP_ARGS -e cleanup_firewall_logs=false"

# Build cron command
CRON_CMD="cd $PROJECT_DIR && ansible-playbook playbooks/log-cleanup.yml $CLEANUP_ARGS >> $LOG_DIR/log-cleanup-cron.log 2>&1 # $CRON_ID"

print_info "Configuration:"
echo "  Schedule: $SCHEDULE_DESC"
echo "  Retention: $RETENTION_DAYS days"
echo "  Cleanup archives: $CLEANUP_ARCHIVES"
echo "  Cleanup alerts: $CLEANUP_ALERTS"
echo "  Cleanup ossec logs: $CLEANUP_OSSEC_LOGS"
echo "  Cleanup firewall logs: $CLEANUP_FIREWALL_LOGS"
echo "  Log file: $LOG_DIR/log-cleanup-cron.log"
echo

# Remove existing and add new cron job
remove_cron

print_info "Adding cron job..."
(crontab -l 2>/dev/null || true; echo "$CRON_SCHEDULE $CRON_CMD") | crontab -

print_success "Log cleanup cron job installed!"
echo

print_info "Cron entry:"
crontab -l | grep "$CRON_ID"
echo

print_info "To run cleanup now (dry run first):"
echo "  ansible-playbook playbooks/log-cleanup.yml -e dry_run=true $CLEANUP_ARGS"
echo

print_info "To run actual cleanup:"
echo "  ansible-playbook playbooks/log-cleanup.yml $CLEANUP_ARGS"
echo

print_info "To view cleanup logs:"
echo "  tail -f $LOG_DIR/log-cleanup-cron.log"
echo

print_info "To remove the cron job:"
echo "  $0 --remove"
