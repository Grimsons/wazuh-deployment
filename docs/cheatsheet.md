# Wazuh Deployment Cheatsheet

Quick reference for common operations. For detailed docs, see [README.md](../README.md).

## Initial Setup

```bash
# Interactive setup (choose one)
./setup-tui.sh              # Beautiful TUI (requires gum)
./setup.sh                  # Traditional CLI

# First-time deployment (bootstrap + deploy)
ansible-playbook site.yml --tags bootstrap,all --ask-pass

# Subsequent deployments
ansible-playbook site.yml
```

## Daily Operations

| Task | Command |
|------|---------|
| **Deploy all** | `ansible-playbook site.yml` |
| **Health check** | `ansible-playbook playbooks/health-check.yml` |
| **View credentials** | `./scripts/manage-vault.sh view` |
| **Backup** | `ansible-playbook playbooks/backup.yml` |
| **Check services** | `ansible all -m shell -a "systemctl status wazuh-*"` |

## Before Redeployment

```bash
# Unlock deployment user (locked after each deploy)
ansible-playbook unlock-deploy-user.yml

# Then deploy
ansible-playbook site.yml
```

## Component-Specific Deployment

```bash
ansible-playbook site.yml --tags indexer
ansible-playbook site.yml --tags manager
ansible-playbook site.yml --tags dashboard
ansible-playbook site.yml --tags agent
```

## Credentials

```bash
./scripts/manage-vault.sh view      # View all credentials
./scripts/manage-vault.sh edit      # Edit vault
./scripts/manage-vault.sh rotate    # Generate new passwords
./scripts/manage-vault.sh rekey     # Change vault password
```

## Backup & Restore

```bash
# Backup
ansible-playbook playbooks/backup.yml
ansible-playbook playbooks/backup.yml -e "backup_dest=/mnt/backups"

# Restore
ansible-playbook playbooks/restore.yml -e "restore_from=20260101T120000"
```

## Health & Monitoring

```bash
# Basic health check
ansible-playbook playbooks/health-check.yml

# With alerting
ansible-playbook playbooks/health-check-alerts.yml -e "alert_slack=true"

# Enable Prometheus exporters
ansible-playbook site.yml --tags monitoring -e wazuh_monitoring_enabled=true
```

## Upgrades

```bash
# Check versions (no changes)
ansible-playbook playbooks/upgrade.yml --tags check

# Upgrade to version in group_vars
ansible-playbook playbooks/upgrade.yml

# Upgrade to specific version
ansible-playbook playbooks/upgrade.yml -e "target_version=4.15.0"
```

## Certificates

```bash
# Check expiration
ansible-playbook playbooks/certificate-management.yml --tags check-expiry

# Rotate certificates
ansible-playbook playbooks/certificate-management.yml --tags rotate

# Renew expiring certs
ansible-playbook playbooks/certificate-management.yml --tags renew
```

## Troubleshooting

```bash
# Service status
systemctl status wazuh-indexer
systemctl status wazuh-manager
systemctl status wazuh-dashboard

# Logs
tail -f /var/log/wazuh-indexer/wazuh-indexer.log
tail -f /var/ossec/logs/ossec.log
tail -f /var/log/wazuh-dashboard/opensearch-dashboards.log

# Cluster health
curl -k -u admin:PASSWORD https://localhost:9200/_cluster/health?pretty

# Agent list
/var/ossec/bin/agent_control -l
```

## Quick API Checks

```bash
# Indexer cluster health
curl -k -u admin:PASS https://INDEXER:9200/_cluster/health?pretty

# Manager API
curl -k -u wazuh:PASS https://MANAGER:55000/

# List agents
curl -k -u wazuh:PASS https://MANAGER:55000/agents?pretty
```

## Ports Reference

| Port | Service |
|------|---------|
| 1514 | Agent communication |
| 1515 | Agent enrollment |
| 1516 | Manager cluster |
| 9200 | Indexer API |
| 9300 | Indexer cluster |
| 443 | Dashboard HTTPS |
| 55000 | Manager API |
| 9114 | Prometheus (indexer) |
| 9115 | Prometheus (manager) |

## File Locations

| File | Purpose |
|------|---------|
| `.vault_password` | Vault encryption key (BACKUP THIS!) |
| `inventory/hosts.yml` | Main inventory |
| `group_vars/all/main.yml` | Configuration |
| `group_vars/all/vault.yml` | Encrypted credentials |
| `keys/wazuh_ansible_key` | SSH private key |
| `backups/` | Vault backups from credential rotation |

## Environment Variables

```bash
# Skip vault password prompt
export ANSIBLE_VAULT_PASSWORD_FILE=.vault_password

# Increase verbosity
ansible-playbook site.yml -vvv

# Dry run (check mode)
ansible-playbook site.yml --check
```
