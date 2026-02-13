# Wazuh Deployment Administrator's Guide

This guide provides best practices and operational procedures for managing your Wazuh deployment.

## Table of Contents

1. [Initial Setup Checklist](#initial-setup-checklist)
2. [Credential Management](#credential-management)
3. [Daily Operations](#daily-operations)
4. [Security Best Practices](#security-best-practices)
5. [Maintenance Schedule](#maintenance-schedule)
6. [Backup and Recovery](#backup-and-recovery)
7. [Monitoring and Alerting](#monitoring-and-alerting)
8. [Upgrading](#upgrading)
9. [Scaling](#scaling)
10. [Troubleshooting Quick Reference](#troubleshooting-quick-reference)

---

## Initial Setup Checklist

### Before Deployment

- [ ] Verify target hosts meet minimum requirements:
  - Indexer/Manager: 4GB RAM, 2 CPU cores, 50GB disk
  - Dashboard: 2GB RAM, 1 CPU core, 20GB disk
  - Agents: 512MB RAM, 1 CPU core
- [ ] Ensure SSH access to all target hosts
- [ ] Ensure Python 3 is installed on all target hosts
- [ ] Plan your network topology and firewall rules

### During Setup

- [ ] Run `./setup.sh` (or `./setup-tui.sh` for the TUI version) and complete the interactive wizard
- [ ] Note the admin credentials displayed at the end
- [ ] Verify `.vault_password` file was created

### Bootstrap & Deployment

```bash
# 1. First-time deployment (bootstrap + deploy in one step)
ansible-playbook site.yml --tags bootstrap,all --ask-pass

# Or use the make shortcut:
make deploy-bootstrap

# 2. Subsequent deployments (uses SSH key auth from bootstrap)
ansible-playbook site.yml

# Or use the make shortcut:
make deploy
```

The bootstrap step creates the `wazuh-deploy` user on all hosts with:
- SSH key authentication (no passwords needed)
- Passwordless sudo access

After bootstrap, all operations use the main inventory (`hosts.yml`) with SSH key auth.

### After Deployment

- [ ] **CRITICAL**: Back up `.vault_password` to secure offline storage
- [ ] Back up `group_vars/all/vault.yml` (encrypted credentials)
- [ ] Test dashboard login at `https://<dashboard-ip>:443`
- [ ] Verify all services running: `ansible-playbook playbooks/health-check.yml`
- [ ] Quick status check: `./scripts/status.sh` (or `make status`)
- [ ] Test credential retrieval: `./scripts/manage-vault.sh view`
- [ ] Configure automated backups (see [Maintenance Schedule](#maintenance-schedule))

---

## Credential Management

### Viewing Credentials

```bash
# View all credentials
./scripts/manage-vault.sh view

# Or use the make shortcut:
make vault-view

# View specific credential
./scripts/manage-vault.sh view | grep indexer
./scripts/manage-vault.sh view | grep api
./scripts/manage-vault.sh view | grep enrollment
```

### Rotating Credentials

Rotate all credentials periodically (recommended: every 90 days):

```bash
# Generate new credentials and update vault
./scripts/manage-vault.sh rotate

# Or use the make shortcut:
make vault-rotate

# Redeploy to apply new credentials
ansible-playbook site.yml
```

### Changing Vault Password

Change the vault encryption password periodically:

```bash
./scripts/manage-vault.sh rekey
```

### Best Practices

| Practice | Recommendation |
|----------|----------------|
| Vault password backup | Store in password manager AND offline (USB/printed) |
| Credential rotation | Every 90 days or after personnel changes |
| Vault rekey | Every 6 months |
| Access control | Limit who can access the deployment host |
| Audit | Log all access to the deployment directory |

---

## Daily Operations

### Health Checks

Run daily health checks (or automate via cron):

```bash
# Quick status check
./scripts/status.sh
make status

# Full health check
ansible-playbook playbooks/health-check.yml
make health

# Detailed check with agent status
ansible-playbook playbooks/health-check.yml -e "check_agents=true"

# Check with index statistics
ansible-playbook playbooks/health-check.yml -e "check_indices=true"
```

### Service Management

```bash
# Check service status on all hosts
ansible all -m shell -a "systemctl status wazuh-* --no-pager" --become

# Restart a specific service
ansible wazuh_managers -m systemd -a "name=wazuh-manager state=restarted" --become

# View logs
ansible wazuh_managers -m shell -a "tail -50 /var/ossec/logs/ossec.log" --become
```

### Agent Management

```bash
# List connected agents (on manager)
ssh <manager-ip> 'sudo /var/ossec/bin/agent_control -l'

# Check agent status
ssh <manager-ip> 'sudo /var/ossec/bin/agent_control -i <agent-id>'

# Restart agent remotely
ansible wazuh_agents -m systemd -a "name=wazuh-agent state=restarted" --become
```

---

## Security Best Practices

### Network Security

| Port | Service | Recommendation |
|------|---------|----------------|
| 443 | Dashboard | Restrict to admin networks only |
| 9200 | Indexer API | Internal only, never expose to internet |
| 55000 | Manager API | Restrict to admin networks |
| 1514 | Agent communication | Allow from agent networks |
| 1515 | Agent enrollment | Allow from agent networks |

### Firewall Configuration

The deployment can auto-configure firewalls:

```yaml
# In group_vars/all/main.yml
wazuh_configure_firewall: true
```

### TLS Configuration

Ensure strong TLS settings:

```yaml
# In group_vars/all/main.yml
wazuh_indexer_ssl_http_enabled: true
wazuh_dashboard_ssl_enabled: true
wazuh_manager_api_ssl: true
```

### API Security

Default hardening settings (already configured):

| Setting | Value | Purpose |
|---------|-------|---------|
| `max_login_attempts` | 5 | Brute-force protection |
| `block_time` | 900s | Lockout duration |
| `max_request_per_minute` | 100 | Rate limiting |

### Access Control Checklist

- [ ] Dashboard accessible only from admin networks
- [ ] API ports not exposed to internet
- [ ] Deployment host secured with disk encryption
- [ ] SSH key-based authentication (no passwords in production)
- [ ] Vault password stored securely offline
- [ ] Regular credential rotation scheduled

---

## Maintenance Schedule

### Automated Maintenance Setup

```bash
# Set up automated backups and log cleanup via cron
ansible-playbook playbooks/setup-maintenance-cron.yml
```

The scheduled backup script is `scripts/run-scheduled-backup.sh`, which is configured by the maintenance cron playbook.

### Recommended Schedule

| Task | Frequency | Command |
|------|-----------|---------|
| Health check | Daily | `make health` |
| Backup | Daily | `make backup` |
| Log cleanup | Weekly | `ansible-playbook playbooks/log-cleanup.yml` |
| OS security updates | Weekly/Monthly | `ansible-playbook playbooks/system-update.yml -e security_only=true` |
| Certificate check | Monthly | `make certs-check` |
| Credential rotation | Quarterly | `make vault-rotate` |
| Vault rekey | Bi-annually | `./scripts/manage-vault.sh rekey` |
| Wazuh upgrade | As needed | `make upgrade` |
| Full OS update | Quarterly | `ansible-playbook playbooks/system-update.yml` |

### Log Retention

Configure in `group_vars/all/main.yml`:

```yaml
wazuh_log_retention_days: 30          # Local logs on manager
wazuh_retention_days: 1095            # Index data (3 years)
wazuh_retention_warm_after_days: 30   # Move to warm tier
wazuh_retention_cold_after_days: 90   # Move to cold tier
```

---

## Backup and Recovery

### Creating Backups

```bash
# Full backup
ansible-playbook playbooks/backup.yml
make backup

# Backup with index snapshots (larger, includes alert data)
ansible-playbook playbooks/backup.yml -e "include_indices=true"
```

### What Gets Backed Up

- Configuration files (ossec.conf, opensearch.yml, etc.)
- Certificates
- Custom rules and decoders
- Agent keys
- Vault credentials

### Backup Storage

Backups are stored in `./backups/TIMESTAMP/`. Best practices:

1. **Local**: Keep 7 days of backups
2. **Offsite**: Copy to remote storage (S3, NFS, etc.)
3. **Test**: Restore quarterly to verify backup integrity

### Restoring from Backup

```bash
# List available backups
ls -la backups/

# Restore from specific backup
ansible-playbook playbooks/restore.yml -e "restore_from=20260121_020000"

# Or use the make shortcut:
make restore BACKUP_ID=20260121_020000
```

### Disaster Recovery

For complete recovery on new infrastructure:

1. Install Ansible on new control node
2. Restore `.vault_password` from secure backup
3. Restore `group_vars/all/vault.yml`
4. Update `inventory/hosts.yml` with new host IPs
5. Run: `ansible-playbook site.yml`
6. Restore configuration backup if available

---

## Monitoring and Alerting

### Health Check Alerts

Set up automated alerting for failures:

```bash
# With Slack alerts
ansible-playbook playbooks/health-check-alerts.yml -e "alert_slack=true"

# With email alerts
ansible-playbook playbooks/health-check-alerts.yml -e "alert_email=true"
```

Configure alert destinations in `group_vars/all/main.yml`:

```yaml
# Slack
wazuh_health_slack_webhook: "https://hooks.slack.com/services/<your-webhook>"

# Email
wazuh_health_email_to: "admin@example.com"
wazuh_health_smtp_server: "smtp.example.com"
```

### Key Metrics to Monitor

| Metric | Warning Threshold | Critical Threshold |
|--------|-------------------|-------------------|
| Indexer disk usage | 70% | 85% |
| Indexer heap usage | 75% | 90% |
| Manager queue size | 10,000 | 50,000 |
| Agent disconnections | >5% | >20% |
| Certificate expiry | 30 days | 7 days |

### Certificate Monitoring

```bash
# Check certificate expiration
ansible-playbook playbooks/certificate-management.yml --tags check-expiry
make certs-check
```

---

## Upgrading

### OS System Updates

Apply operating system security patches and updates:

```bash
# Check for available updates (no changes)
ansible-playbook playbooks/system-update.yml --tags check

# Apply security updates only (recommended for production)
ansible-playbook playbooks/system-update.yml -e "security_only=true"

# Full system update (all packages)
ansible-playbook playbooks/system-update.yml

# Auto-reboot if kernel updates require it
ansible-playbook playbooks/system-update.yml -e "auto_reboot=true"
```

**Best Practices for OS Updates:**
- Apply security updates weekly or monthly
- Schedule full updates during maintenance windows
- The playbook updates in safe order: Agents -> Dashboard -> Managers -> Indexers
- Rolling updates ensure one node stays running during cluster updates
- Backup is created automatically before updates

### Wazuh Version Upgrades

### Pre-Upgrade Checklist

- [ ] Review release notes for breaking changes
- [ ] Create full backup
- [ ] Test upgrade in staging environment
- [ ] Schedule maintenance window
- [ ] Notify stakeholders

### Upgrade Process

```bash
# Check current vs target versions (dry run)
ansible-playbook playbooks/upgrade.yml --tags check
make upgrade-check

# Perform upgrade
ansible-playbook playbooks/upgrade.yml
make upgrade

# Upgrade to specific version
ansible-playbook playbooks/upgrade.yml -e "target_version=4.12.0"
```

### Post-Upgrade Verification

```bash
# Verify all services running
ansible-playbook playbooks/health-check.yml

# Check versions
ansible all -m shell -a "wazuh-manager --version 2>/dev/null || wazuh-indexer --version 2>/dev/null || wazuh-agent --version 2>/dev/null" --become
```

### Rollback

If upgrade fails:

```bash
# Restore from pre-upgrade backup
ansible-playbook playbooks/restore.yml -e "restore_from=pre-upgrade-TIMESTAMP"
```

---

## Scaling

### Adding Indexer Nodes

1. Add new host to `inventory/hosts.yml`:
   ```yaml
   wazuh_indexers:
     hosts:
       existing-indexer:
         ...
       new-indexer-ip:
         indexer_node_name: indexer-2
   ```

2. Add credentials to vault:
   ```bash
   ./scripts/manage-vault.sh edit
   ```

3. Deploy:
   ```bash
   ansible-playbook site.yml --tags indexer
   make deploy-indexer
   ```

### Adding Manager Nodes (Cluster)

1. Enable clustering in `group_vars/all/main.yml`:
   ```yaml
   wazuh_manager_cluster_enabled: true
   ```

2. Add worker nodes to inventory with `manager_node_type: worker`

3. Deploy manager cluster

### Adding Agents

```bash
# Add to inventory, then run agent deployment
ansible-playbook site.yml --tags agent
make deploy-agent
```

---

## Troubleshooting Quick Reference

### Common Issues

| Issue | Quick Fix |
|-------|-----------|
| Dashboard login fails | `./scripts/manage-vault.sh view` to verify password |
| Agent not connecting | Check port 1514 connectivity, verify enrollment password |
| Indexer cluster red | Check disk space, restart indexer service |
| High memory usage | Adjust heap size in jvm.options |
| Certificate errors | `make certs-rotate` to regenerate certificates |

### Log Locations

| Component | Log Path |
|-----------|----------|
| Indexer | `/var/log/wazuh-indexer/wazuh-indexer.log` |
| Manager | `/var/ossec/logs/ossec.log` |
| Dashboard | `/var/log/wazuh-dashboard/opensearch-dashboards.log` |
| Agent | `/var/ossec/logs/ossec.log` |
| Filebeat | `/var/log/filebeat/filebeat` |

### Diagnostic Commands

```bash
# Quick status
./scripts/status.sh

# Full system diagnostics
ansible-playbook playbooks/health-check.yml -e "check_agents=true check_indices=true"

# Check cluster health
curl -k -u admin:<your-password> https://<indexer-ip>:9200/_cluster/health?pretty

# Check manager cluster
ssh <manager-ip> 'sudo /var/ossec/bin/cluster_control -l'

# View recent alerts
ssh <manager-ip> 'sudo tail -100 /var/ossec/logs/alerts/alerts.json | jq .'
```

### Getting Help

1. Check [Troubleshooting Guide](troubleshooting.md)
2. Review [Wazuh Documentation](https://documentation.wazuh.com)
3. [Wazuh Slack Community](https://wazuh.com/community/join-us-on-slack/)
4. [GitHub Issues](https://github.com/wazuh/wazuh/issues)

---

## Quick Command Reference

```bash
# View credentials
./scripts/manage-vault.sh view          # or: make vault-view

# Quick status
./scripts/status.sh                     # or: make status

# Health check
ansible-playbook playbooks/health-check.yml  # or: make health

# Backup
ansible-playbook playbooks/backup.yml   # or: make backup

# Rotate credentials
./scripts/manage-vault.sh rotate        # or: make vault-rotate

# Check certificates
make certs-check

# OS security updates
ansible-playbook playbooks/system-update.yml -e "security_only=true"

# Wazuh upgrade (dry run)
make upgrade-check

# Full deployment
ansible-playbook site.yml               # or: make deploy
```
