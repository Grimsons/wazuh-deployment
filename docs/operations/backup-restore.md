# Backup and Restore Guide

This document describes backup and restore procedures for Wazuh deployments.

## Overview

The backup system provides:
- Automated configuration backups
- Index snapshot support for alert data
- Point-in-time recovery capability
- Integrity validation

## Backup Playbook

### Full Backup

```bash
# Create a full backup of all components
ansible-playbook playbooks/backup.yml
```

### Component-Specific Backups

```bash
# Backup only indexer configuration
ansible-playbook playbooks/backup.yml -e "backup_indexer=true backup_manager=false backup_dashboard=false"

# Backup only manager configuration
ansible-playbook playbooks/backup.yml -e "backup_manager=true backup_indexer=false backup_dashboard=false"
```

### Include Index Snapshots

```bash
# Create backup with index snapshots (for alert data)
ansible-playbook playbooks/backup.yml -e "include_indices=true"
```

## What Gets Backed Up

### Indexer
- `/etc/wazuh-indexer/opensearch.yml` - Cluster configuration
- `/etc/wazuh-indexer/opensearch-security/` - Security settings
- `/etc/wazuh-indexer/jvm.options` - JVM configuration
- `/etc/wazuh-indexer/certs/` - SSL certificates

### Manager
- `/var/ossec/etc/ossec.conf` - Main configuration
- `/var/ossec/etc/rules/` - Custom detection rules
- `/var/ossec/etc/decoders/` - Custom log decoders
- `/var/ossec/etc/lists/` - CDB lists (threat intel)
- `/var/ossec/etc/shared/` - Agent group configurations
- `/var/ossec/etc/client.keys` - Agent registration keys
- `/var/ossec/api/configuration/` - API settings

### Dashboard
- `/etc/wazuh-dashboard/opensearch_dashboards.yml` - Dashboard config
- `/usr/share/wazuh-dashboard/data/wazuh/config/wazuh.yml` - Wazuh plugin config
- `/etc/wazuh-dashboard/certs/` - SSL certificates

### Credentials
- `./credentials/indexer_admin_password.txt`
- `./credentials/api_password.txt`
- `./credentials/manager_cluster_key.txt` (if clustered)

## Backup Storage

Backups are stored in timestamped directories:

```
./backups/
├── 20240115_020000/
│   ├── indexer/
│   ├── manager/
│   ├── dashboard/
│   └── credentials/
├── 20240116_020000/
└── checksums.sha256
```

## Backup Retention

Configure retention in `group_vars/all.yml`:

```yaml
backup_retention_days: 30
backup_location: "./backups"
backup_remote_enabled: false
backup_remote_location: "s3://bucket/wazuh-backups"
```

## Scheduled Backups

Use the provided script to set up automated backups with retention management:

```bash
# Daily backup at 2 AM, keep 7 days of backups (default)
./scripts/setup-backup-cron.sh --daily

# Daily backup at 3 AM, keep 14 days
./scripts/setup-backup-cron.sh --daily --hour 3 --keep 14

# Weekly backup on Sunday, keep 4 weeks
./scripts/setup-backup-cron.sh --weekly --keep 4

# Every 6 hours, keep 28 backups (7 days)
./scripts/setup-backup-cron.sh --hourly 6 --keep 28

# Skip specific components
./scripts/setup-backup-cron.sh --daily --no-indexer

# Remove the cron job
./scripts/setup-backup-cron.sh --remove
```

The backup script automatically:
- Creates timestamped backups in `./backups/`
- Removes backups older than the retention limit
- Logs to `./logs/backup-cron.log`

### Manual Crontab Entry

If you prefer manual cron setup:

```bash
# Daily backup at 2 AM
0 2 * * * cd /path/to/wazuh-deployment && ansible-playbook playbooks/backup.yml
```

## Restore Playbook

### Full Restore

```bash
# Restore from specific backup
ansible-playbook playbooks/restore.yml -e "backup_timestamp=20240115_020000"
```

### Component-Specific Restore

```bash
# Restore only indexer
ansible-playbook playbooks/restore.yml \
  -e "backup_timestamp=20240115_020000" \
  -e "restore_indexer=true" \
  --limit wazuh_indexers

# Restore only manager
ansible-playbook playbooks/restore.yml \
  -e "backup_timestamp=20240115_020000" \
  -e "restore_manager=true" \
  --limit wazuh_managers
```

### Restore to Different Host

```bash
# Restore to new infrastructure
ansible-playbook playbooks/restore.yml \
  -e "backup_timestamp=20240115_020000" \
  -i inventory/new-hosts.yml
```

## Restore Procedure

### 1. Stop Services

```bash
ansible all -m systemd -a "name=wazuh-indexer state=stopped" --limit wazuh_indexers
ansible all -m systemd -a "name=wazuh-manager state=stopped" --limit wazuh_managers
ansible all -m systemd -a "name=wazuh-dashboard state=stopped" --limit wazuh_dashboards
```

### 2. Execute Restore

```bash
ansible-playbook playbooks/restore.yml -e "backup_timestamp=20240115_020000"
```

### 3. Start Services

```bash
ansible all -m systemd -a "name=wazuh-indexer state=started" --limit wazuh_indexers
ansible all -m systemd -a "name=wazuh-manager state=started" --limit wazuh_managers
ansible all -m systemd -a "name=wazuh-dashboard state=started" --limit wazuh_dashboards
```

### 4. Verify Recovery

```bash
ansible-playbook playbooks/health-check.yml
```

## Index Snapshots

For recovering historical alert data, use OpenSearch snapshots:

### Configure Snapshot Repository

```bash
curl -X PUT "https://indexer:9200/_snapshot/backup_repo" \
  -H "Content-Type: application/json" \
  -u admin:password \
  -d '{
    "type": "fs",
    "settings": {
      "location": "/mnt/snapshots"
    }
  }'
```

### Create Snapshot

```bash
curl -X PUT "https://indexer:9200/_snapshot/backup_repo/snapshot_$(date +%Y%m%d)" \
  -H "Content-Type: application/json" \
  -u admin:password \
  -d '{
    "indices": "wazuh-alerts-*",
    "ignore_unavailable": true,
    "include_global_state": false
  }'
```

### List Snapshots

```bash
curl -X GET "https://indexer:9200/_snapshot/backup_repo/_all" -u admin:password
```

### Restore Snapshot

```bash
curl -X POST "https://indexer:9200/_snapshot/backup_repo/snapshot_20240115/_restore" \
  -H "Content-Type: application/json" \
  -u admin:password \
  -d '{
    "indices": "wazuh-alerts-*",
    "ignore_unavailable": true,
    "include_global_state": false
  }'
```

## Validation

### Validate Backup Integrity

```bash
ansible-playbook playbooks/dr-validate.yml -e "backup_timestamp=20240115_020000"
```

### Test Restore (Non-Destructive)

```bash
ansible-playbook playbooks/dr-validate.yml -e "dr_test_mode=true"
```

## Troubleshooting

### Backup Fails

1. Check disk space: `df -h ./backups`
2. Verify SSH connectivity: `ansible all -m ping`
3. Check permissions on remote hosts

### Restore Fails

1. Verify backup integrity: `ansible-playbook playbooks/dr-validate.yml`
2. Check file permissions
3. Ensure services are stopped before restore

### Corrupted Backup

1. Check checksums: `sha256sum -c backups/TIMESTAMP/checksums.sha256`
2. Try previous backup
3. If all backups corrupted, redeploy and reconfigure

## Log Cleanup

The Wazuh Manager accumulates logs over time in `/var/ossec/logs/`. To prevent disk space exhaustion, use the log cleanup playbook:

### Manual Cleanup

```bash
# Preview what would be deleted (dry run)
ansible-playbook playbooks/log-cleanup.yml -e dry_run=true

# Clean logs older than 30 days (default)
ansible-playbook playbooks/log-cleanup.yml

# Keep only 14 days of logs
ansible-playbook playbooks/log-cleanup.yml -e log_retention_days=14

# Skip specific log types
ansible-playbook playbooks/log-cleanup.yml -e cleanup_archives=false
```

### Log Directories Cleaned

| Directory | Description |
|-----------|-------------|
| `/var/ossec/logs/archives/` | Archived raw events |
| `/var/ossec/logs/alerts/` | Alert log files |
| `/var/ossec/logs/*.log-*` | Rotated ossec.log files |
| `/var/ossec/logs/firewall/` | Firewall logs |

### Automated Log Cleanup

Use the provided script to schedule automatic cleanup:

```bash
# Daily cleanup at 3:30 AM, keep 30 days (default)
./scripts/setup-log-cleanup-cron.sh

# Keep only 14 days of logs
./scripts/setup-log-cleanup-cron.sh --days 14

# Weekly cleanup on Sunday
./scripts/setup-log-cleanup-cron.sh --weekly --days 7

# Remove the cron job
./scripts/setup-log-cleanup-cron.sh --remove
```

### Log Retention Configuration

Set the default retention in `group_vars/all.yml`:

```yaml
wazuh_log_retention_days: 30
```

## Best Practices

1. **Test restores regularly** - Monthly DR tests recommended
2. **Offsite backups** - Copy to remote location for disaster recovery
3. **Monitor backup jobs** - Alert on failed backups
4. **Document custom configurations** - Keep runbooks updated
5. **Version control** - Store playbooks and configs in git
6. **Schedule log cleanup** - Prevent disk space issues on managers
