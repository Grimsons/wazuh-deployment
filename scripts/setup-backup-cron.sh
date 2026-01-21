#!/bin/bash

# Setup Wazuh Scheduled Backup Cron Job
# Configures automated backups with retention management
#
# Usage:
#   ./scripts/setup-backup-cron.sh                       # Interactive setup
#   ./scripts/setup-backup-cron.sh --daily              # Daily at 2 AM
#   ./scripts/setup-backup-cron.sh --weekly             # Weekly on Sunday at 2 AM
#   ./scripts/setup-backup-cron.sh --hourly 2 --keep 48 # Every 2 hours, keep 48 backups
#   ./scripts/setup-backup-cron.sh --remove             # Remove cron job

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
CRON_ID="wazuh-scheduled-backup"
LOG_DIR="$PROJECT_DIR/logs"
BACKUP_DIR="$PROJECT_DIR/backups"

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
SCHEDULE_TYPE="daily"
SCHEDULE_HOUR="2"
SCHEDULE_MINUTE="0"
SCHEDULE_DAY="0"  # Sunday
HOURLY_INTERVAL=0
KEEP_BACKUPS=7
BACKUP_INDEXER=true
BACKUP_MANAGER=true
BACKUP_DASHBOARD=true
REMOVE_CRON=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --daily)
            SCHEDULE_TYPE="daily"
            shift
            ;;
        --weekly)
            SCHEDULE_TYPE="weekly"
            shift
            ;;
        --hourly)
            SCHEDULE_TYPE="hourly"
            HOURLY_INTERVAL="$2"
            shift 2
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
        --keep)
            KEEP_BACKUPS="$2"
            shift 2
            ;;
        --no-indexer)
            BACKUP_INDEXER=false
            shift
            ;;
        --no-manager)
            BACKUP_MANAGER=false
            shift
            ;;
        --no-dashboard)
            BACKUP_DASHBOARD=false
            shift
            ;;
        --remove)
            REMOVE_CRON=true
            shift
            ;;
        --help|-h)
            echo "Setup Wazuh Scheduled Backup Cron Job"
            echo ""
            echo "Usage: $0 [options]"
            echo ""
            echo "Schedule Options:"
            echo "  --daily            Daily backup (default)"
            echo "  --weekly           Weekly backup (Sunday)"
            echo "  --hourly N         Backup every N hours"
            echo "  --hour H           Hour to run (0-23, default: 2)"
            echo "  --minute M         Minute to run (0-59, default: 0)"
            echo "  --day D            Day for weekly (0=Sun, 1=Mon..., default: 0)"
            echo ""
            echo "Retention Options:"
            echo "  --keep N           Keep N backups (default: 7)"
            echo ""
            echo "Component Options:"
            echo "  --no-indexer       Skip indexer backup"
            echo "  --no-manager       Skip manager backup"
            echo "  --no-dashboard     Skip dashboard backup"
            echo ""
            echo "Other Options:"
            echo "  --remove           Remove existing cron job"
            echo "  --help             Show this help"
            echo ""
            echo "Examples:"
            echo "  $0 --daily --hour 3 --keep 14    # Daily at 3 AM, keep 14 days"
            echo "  $0 --weekly --day 0 --keep 4    # Weekly on Sunday, keep 4 weeks"
            echo "  $0 --hourly 6 --keep 28         # Every 6 hours, keep 7 days"
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
    print_info "Removing existing backup cron job..."
    crontab -l 2>/dev/null | grep -v "$CRON_ID" | crontab - 2>/dev/null || true
    print_success "Backup cron job removed"
}

if [ "$REMOVE_CRON" = "true" ]; then
    remove_cron
    exit 0
fi

print_header "Wazuh Scheduled Backup Setup"

# Create directories
mkdir -p "$LOG_DIR"
mkdir -p "$BACKUP_DIR"

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
    hourly)
        if [ "$HOURLY_INTERVAL" -eq 1 ]; then
            CRON_SCHEDULE="$SCHEDULE_MINUTE * * * *"
            SCHEDULE_DESC="Every hour at :$(printf '%02d' $SCHEDULE_MINUTE)"
        else
            CRON_SCHEDULE="$SCHEDULE_MINUTE */$HOURLY_INTERVAL * * *"
            SCHEDULE_DESC="Every $HOURLY_INTERVAL hours at :$(printf '%02d' $SCHEDULE_MINUTE)"
        fi
        ;;
esac

# Build ansible-playbook command arguments
BACKUP_ARGS="-e backup_type=scheduled"
[ "$BACKUP_INDEXER" = "false" ] && BACKUP_ARGS="$BACKUP_ARGS -e backup_indexer=false"
[ "$BACKUP_MANAGER" = "false" ] && BACKUP_ARGS="$BACKUP_ARGS -e backup_manager=false"
[ "$BACKUP_DASHBOARD" = "false" ] && BACKUP_ARGS="$BACKUP_ARGS -e backup_dashboard=false"

# Create the backup wrapper script
WRAPPER_SCRIPT="$SCRIPT_DIR/run-scheduled-backup.sh"
cat > "$WRAPPER_SCRIPT" << 'WRAPPER_EOF'
#!/bin/bash
# Wazuh Scheduled Backup Wrapper
# Auto-generated by setup-backup-cron.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="$PROJECT_DIR/backups"
LOG_FILE="$PROJECT_DIR/logs/backup-cron.log"
WRAPPER_EOF

cat >> "$WRAPPER_SCRIPT" << WRAPPER_EOF
KEEP_BACKUPS=$KEEP_BACKUPS
BACKUP_ARGS="$BACKUP_ARGS"
WRAPPER_EOF

cat >> "$WRAPPER_SCRIPT" << 'WRAPPER_EOF'

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

log "Starting scheduled backup..."

# Run the backup
cd "$PROJECT_DIR"
if ansible-playbook playbooks/backup.yml $BACKUP_ARGS >> "$LOG_FILE" 2>&1; then
    log "Backup completed successfully"
else
    log "ERROR: Backup failed with exit code $?"
    exit 1
fi

# Cleanup old backups
log "Cleaning up old backups (keeping $KEEP_BACKUPS most recent)..."

# Count existing backups
BACKUP_COUNT=$(find "$BACKUP_DIR" -maxdepth 1 -type d -name "20*" | wc -l)

if [ "$BACKUP_COUNT" -gt "$KEEP_BACKUPS" ]; then
    # Calculate how many to remove
    REMOVE_COUNT=$((BACKUP_COUNT - KEEP_BACKUPS))
    log "Found $BACKUP_COUNT backups, removing $REMOVE_COUNT old backups..."

    # Get list of oldest backups to remove
    find "$BACKUP_DIR" -maxdepth 1 -type d -name "20*" -printf '%T+ %p\n' | \
        sort | head -n "$REMOVE_COUNT" | cut -d' ' -f2- | \
        while read -r backup_path; do
            log "Removing old backup: $backup_path"
            rm -rf "$backup_path"
        done

    log "Cleanup complete"
else
    log "No cleanup needed ($BACKUP_COUNT backups, keeping $KEEP_BACKUPS)"
fi

log "Scheduled backup finished"
WRAPPER_EOF

chmod +x "$WRAPPER_SCRIPT"

# Build cron command
CRON_CMD="$WRAPPER_SCRIPT # $CRON_ID"

print_info "Configuration:"
echo "  Schedule: $SCHEDULE_DESC"
echo "  Keep backups: $KEEP_BACKUPS"
echo "  Backup indexer: $BACKUP_INDEXER"
echo "  Backup manager: $BACKUP_MANAGER"
echo "  Backup dashboard: $BACKUP_DASHBOARD"
echo "  Backup directory: $BACKUP_DIR"
echo "  Log file: $LOG_DIR/backup-cron.log"
echo

# Remove existing and add new cron job
remove_cron

print_info "Adding cron job..."
(crontab -l 2>/dev/null || true; echo "$CRON_SCHEDULE $CRON_CMD") | crontab -

print_success "Backup cron job installed!"
echo

print_info "Cron entry:"
crontab -l | grep "$CRON_ID"
echo

print_info "To run a backup now:"
echo "  ansible-playbook playbooks/backup.yml"
echo "  # or use the wrapper:"
echo "  $WRAPPER_SCRIPT"
echo

print_info "To view backup logs:"
echo "  tail -f $LOG_DIR/backup-cron.log"
echo

print_info "To list existing backups:"
echo "  ls -la $BACKUP_DIR"
echo

print_info "To restore from a backup:"
echo "  ansible-playbook playbooks/restore.yml -e \"restore_from=BACKUP_TIMESTAMP\""
echo

print_info "To remove the cron job:"
echo "  $0 --remove"
