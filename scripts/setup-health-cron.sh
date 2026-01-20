#!/bin/bash

# Setup Wazuh Health Check Cron Job
# Configures automated health monitoring with alerting
#
# Usage:
#   ./scripts/setup-health-cron.sh                    # Interactive setup
#   ./scripts/setup-health-cron.sh --interval 5      # Check every 5 minutes
#   ./scripts/setup-health-cron.sh --slack           # Enable Slack alerts
#   ./scripts/setup-health-cron.sh --remove          # Remove cron job

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CRON_ID="wazuh-health-check"
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
INTERVAL=5
ALERT_SLACK=false
ALERT_EMAIL=false
ALERT_WEBHOOK=false
ALERT_FILE=true
ALERT_ON_WARNING=false
REMOVE_CRON=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --interval)
            INTERVAL="$2"
            shift 2
            ;;
        --slack)
            ALERT_SLACK=true
            shift
            ;;
        --email)
            ALERT_EMAIL=true
            shift
            ;;
        --webhook)
            ALERT_WEBHOOK=true
            shift
            ;;
        --file)
            ALERT_FILE=true
            shift
            ;;
        --warn)
            ALERT_ON_WARNING=true
            shift
            ;;
        --remove)
            REMOVE_CRON=true
            shift
            ;;
        --help|-h)
            echo "Setup Wazuh Health Check Cron Job"
            echo ""
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --interval N    Check interval in minutes (default: 5)"
            echo "  --slack         Enable Slack alerts"
            echo "  --email         Enable email alerts"
            echo "  --webhook       Enable webhook alerts"
            echo "  --file          Enable file-based alerts (default: on)"
            echo "  --warn          Also alert on warnings, not just critical"
            echo "  --remove        Remove existing cron job"
            echo "  --help          Show this help"
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
    print_info "Removing existing cron job..."
    crontab -l 2>/dev/null | grep -v "$CRON_ID" | crontab - 2>/dev/null || true
    print_success "Cron job removed"
}

if [ "$REMOVE_CRON" = "true" ]; then
    remove_cron
    exit 0
fi

print_header "Wazuh Health Check Cron Setup"

# Create log directory
mkdir -p "$LOG_DIR"

# Build ansible-playbook command
ALERT_ARGS=""
[ "$ALERT_SLACK" = "true" ] && ALERT_ARGS="$ALERT_ARGS -e alert_slack=true"
[ "$ALERT_EMAIL" = "true" ] && ALERT_ARGS="$ALERT_ARGS -e alert_email=true"
[ "$ALERT_WEBHOOK" = "true" ] && ALERT_ARGS="$ALERT_ARGS -e alert_webhook=true"
[ "$ALERT_FILE" = "true" ] && ALERT_ARGS="$ALERT_ARGS -e alert_file=true"
[ "$ALERT_ON_WARNING" = "true" ] && ALERT_ARGS="$ALERT_ARGS -e alert_on_warning=true"

# Build cron command
CRON_CMD="cd $PROJECT_DIR && ansible-playbook playbooks/health-check-alerts.yml $ALERT_ARGS >> $LOG_DIR/health-check-cron.log 2>&1 # $CRON_ID"

print_info "Configuration:"
echo "  Interval: Every $INTERVAL minutes"
echo "  Slack alerts: $ALERT_SLACK"
echo "  Email alerts: $ALERT_EMAIL"
echo "  Webhook alerts: $ALERT_WEBHOOK"
echo "  File alerts: $ALERT_FILE"
echo "  Alert on warning: $ALERT_ON_WARNING"
echo "  Log file: $LOG_DIR/health-check-cron.log"
echo

# Remove existing and add new cron job
remove_cron

print_info "Adding cron job..."
(crontab -l 2>/dev/null || true; echo "*/$INTERVAL * * * * $CRON_CMD") | crontab -

print_success "Cron job installed!"
echo

print_info "Cron entry:"
crontab -l | grep "$CRON_ID"
echo

print_info "To test the health check now:"
echo "  ansible-playbook playbooks/health-check-alerts.yml $ALERT_ARGS"
echo

print_info "To view logs:"
echo "  tail -f $LOG_DIR/health-check-cron.log"
echo

print_info "To remove the cron job:"
echo "  $0 --remove"
