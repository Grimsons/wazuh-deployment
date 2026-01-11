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

Add to crontab for automated daily backups:

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

## Best Practices

1. **Test restores regularly** - Monthly DR tests recommended
2. **Offsite backups** - Copy to remote location for disaster recovery
3. **Monitor backup jobs** - Alert on failed backups
4. **Document custom configurations** - Keep runbooks updated
5. **Version control** - Store playbooks and configs in git
