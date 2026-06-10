# Wazuh Deployment Cheatsheet

Quick reference for common operations. For detailed docs, see the [Deployment Guide](getting-started/deployment.md).

## Make Commands

The Makefile provides shortcuts for all common operations. Run `make help` to see all targets.

| Command | Description |
|---------|-------------|
| `make setup` | Run interactive CLI setup wizard |
| `make setup-tui` | Run TUI setup (requires gum) |
| `make check` | Validate prerequisites and configuration |
| `make deploy` | Deploy all Wazuh components |
| `make deploy-bootstrap` | First-time deployment (bootstrap + all) |
| `make deploy-check` | Dry-run deployment (no changes) |
| `make deploy-indexer` | Deploy only indexer nodes |
| `make deploy-manager` | Deploy only manager nodes |
| `make deploy-dashboard` | Deploy only dashboard nodes |
| `make deploy-agent` | Deploy agents |
| `make health` | Run comprehensive health check |
| `make status` | Quick status check of all services |
| `make backup` | Create backup of Wazuh data |
| `make restore BACKUP_ID=<id>` | Restore from backup |
| `make upgrade` | Upgrade Wazuh to version in group_vars |
| `make unlock` | Unlock deployment user for new deployment |
| `make vault-view` | View vault credentials |
| `make vault-edit` | Edit vault credentials |
| `make vault-rotate` | Rotate all passwords |
| `make vault-rekey` | Change vault encryption password |
| `make certs-check` | Check certificate expiration |
| `make certs-rotate` | Rotate all certificates |
| `make certs-renew` | Renew expiring certificates |
| `make monitoring` | Enable Prometheus monitoring exporters |
| `make test` | Run syntax and lint checks |
| `make clean` | Remove generated files (keeps vault and keys) |

## Initial Setup

```bash
# Interactive setup (choose one)
./setup-tui.sh              # TUI (requires gum)
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
| **Quick status** | `./scripts/status.sh` |
| **View credentials** | `./scripts/manage-vault.sh view` |
| **Backup** | `ansible-playbook playbooks/backup.yml` |

## Before Redeployment

```bash
# Unlock deployment user (locked after each deploy)
ansible-playbook unlock-deploy-user.yml

# Then deploy
ansible-playbook site.yml
```

## Scripts

| Script | Description |
|--------|-------------|
| `./scripts/status.sh` | Quick health check of all Wazuh services across hosts |
| `./scripts/manage-vault.sh` | View, edit, rotate, or rekey vault credentials |
| `./scripts/deploy-prep.sh` | Deploy client preparation package to multiple hosts |
| `./scripts/deploy-with-rollback.sh` | Deploy with automatic rollback on failure |
| `./scripts/lockdown-ansible-user.sh` | Restrict deployment user sudo access |
| `./scripts/migrate-from-main.sh` | Migrate deployment from main branch to versioned branches |
| `./scripts/run-scheduled-backup.sh` | Run backup on a schedule (for cron) |
| `./scripts/prepare-client.sh` | Prepare a single client host |

## Playbooks

| Playbook | Description |
|----------|-------------|
| `site.yml` | Full deployment (all components) |
| `unlock-deploy-user.yml` | Unlock deployment user for redeployment |
| `playbooks/health-check.yml` | Comprehensive health check |
| `playbooks/health-check-alerts.yml` | Health check with alerting |
| `playbooks/backup.yml` | Backup Wazuh data |
| `playbooks/restore.yml` | Restore from backup |
| `playbooks/upgrade.yml` | Upgrade Wazuh components |
| `playbooks/certificate-management.yml` | Certificate validation, rotation, renewal |
| `playbooks/pre-flight-checks.yml` | Pre-deployment validation |
| `playbooks/canary-deploy.yml` | Staged/rolling deployment |
| `playbooks/rotate-credentials.yml` | Rotate all credentials |
| `playbooks/setup-maintenance-cron.yml` | Set up automated maintenance scheduling |
| `playbooks/system-update.yml` | OS-level package updates across hosts |
| `playbooks/log-cleanup.yml` | Log rotation and cleanup |
| `playbooks/compliance-report.yml` | Generate compliance report |
| `playbooks/dr-validate.yml` | Disaster recovery validation |
| `playbooks/bootstrap-hosts.yml` | Bootstrap deployment user on hosts |

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

# Quick status across all hosts
./scripts/status.sh

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
curl -k -u admin:PASSWORD https://INDEXER:9200/_cluster/health?pretty

# Manager API
curl -k -u wazuh:PASSWORD https://MANAGER:55000/

# List agents
curl -k -u wazuh:PASSWORD https://MANAGER:55000/agents?pretty
```

## Ports Reference

| Port | Protocol | Service |
|------|----------|---------|
| 1514 | TCP | Agent communication |
| 1515 | TCP | Agent enrollment |
| 1516 | TCP | Manager cluster |
| 9200 | TCP | Indexer API |
| 9300 | TCP | Indexer cluster |
| 443 | TCP | Dashboard HTTPS |
| 55000 | TCP | Manager API |
| 9114 | TCP | Prometheus (indexer) |
| 9115 | TCP | Prometheus (manager) |

## File Locations

| File | Purpose |
|------|---------|
| `.vault_password` | Vault encryption key (BACKUP THIS!) |
| `inventory/hosts.yml` | Main inventory |
| `group_vars/all/main.yml` | Configuration variables |
| `group_vars/all/vault.yml` | Encrypted credentials |
| `keys/wazuh_ansible_key` | SSH private key |
| `backups/` | Vault backups from credential rotation |

## Environment Variables

```bash
# Increase verbosity
ansible-playbook site.yml -vvv

# Dry run (check mode)
ansible-playbook site.yml --check
```
