# Wazuh Deployment

Production-ready automated deployment of Wazuh SIEM/XDR stack using Ansible with security hardening, automatic credential management, and comprehensive operational tooling.

## Overview

- **Secure by Default** - Ansible Vault encrypted credentials, API rate limiting, TLS 1.2+
- **Interactive Setup** - CLI wizard or TUI with deployment profiles (minimal/production/custom)
- **One-Command Bootstrap** - Automatic host preparation with SSH key deployment
- **Smart Index Management** - Automatic rollover, tiered retention, cold index closing
- **Certificate Management** - Self-signed or external CA with rotation/renewal playbooks
- **Post-Deployment Security** - Automatic lockdown of deployment user after completion
- **Operational Tooling** - Backup/restore, health checks, upgrades, and log rotation
- **Extensible** - Custom rules, decoders, agent groups, and integrations
- **Cross-Platform Agents** - Linux, Windows, and macOS support
- **Prometheus Monitoring** - Built-in exporters and Grafana dashboard (optional)

## Components

| Component | Description |
|-----------|-------------|
| **Wazuh Indexer** | Stores and indexes security alerts (OpenSearch-based) |
| **Wazuh Manager** | Central component that analyzes data from agents |
| **Wazuh Dashboard** | Web interface for visualization and management |
| **Wazuh Agent** | Collects security data from monitored endpoints |
| **Filebeat** | Forwards alerts from Manager to Indexer |

## Prerequisites

### Control Node
- Ansible 2.12+ (recommended 2.16+)
- Python 3.8+ (recommended 3.10+)
- Bash shell
- `gum` 0.10+ (optional, for TUI setup)

### Target Hosts
- Ubuntu 20.04+, Debian 10+, RHEL/CentOS 8+, Rocky Linux 8+, Arch Linux
- SSH access (root or sudo user)
- Minimum RAM: 4GB (indexer/manager), 2GB (dashboard), 512MB (agents)

### Required Ansible Collections

```bash
ansible-galaxy install -r requirements.yml
```

## Quick Start

### 1. Run Interactive Setup

```bash
# Option A: TUI setup (recommended, requires gum)
./setup-tui.sh

# Option B: Traditional CLI wizard
./setup.sh
```

Both generate:
- `inventory/hosts.yml` - Ansible inventory
- `inventory/bootstrap.yml` - Bootstrap inventory (first deployment)
- `group_vars/all/main.yml` - Configuration variables
- `group_vars/all/vault.yml` - Encrypted credentials (Ansible Vault)
- `.vault_password` - Vault encryption key (keep secure!)
- `ansible.cfg` - Ansible settings
- `keys/wazuh_ansible_key` - SSH keypair for deployment

### 2. First Deployment (Bootstrap + Deploy)

Bootstrap creates the `wazuh-deploy` user with SSH keys on target hosts, then deploys Wazuh:

```bash
# If using password authentication for initial root access:
ansible-playbook site.yml --tags bootstrap,all --ask-pass

# If root already has your SSH key:
ansible-playbook site.yml --tags bootstrap,all
```

### 3. Subsequent Deployments

After bootstrap, deployments use the `wazuh-deploy` user automatically:

```bash
# Unlock the deploy user (locked after previous deployment)
ansible-playbook unlock-deploy-user.yml

# Deploy
ansible-playbook site.yml
# User is automatically re-locked at completion
```

### 4. Access Dashboard

Credentials are stored encrypted in Ansible Vault. To view them:

```bash
./scripts/manage-vault.sh view
```

Access the dashboard at `https://<dashboard-ip>:443` using the `admin` user.

## Makefile Shortcuts

The project includes a Makefile for common operations. Run `make help` for all targets.

```bash
make setup              # Run interactive CLI setup
make deploy-bootstrap   # First-time deployment (bootstrap + all)
make deploy             # Regular deployment
make status             # Quick service status check
make health             # Comprehensive health check
make backup             # Create backup
make restore BACKUP_ID=20260110T120000  # Restore from backup
make upgrade            # Upgrade Wazuh version
make unlock             # Unlock deployment user
make vault-view         # View vault credentials
make vault-edit         # Edit vault credentials
make vault-rotate       # Rotate all passwords
make certs-check        # Check certificate expiration
make certs-rotate       # Rotate certificates
make monitoring         # Enable Prometheus exporters
make test               # Run syntax and lint checks
make check              # Validate prerequisites
```

## Project Structure

```
wazuh-deployment/
|-- setup.sh                     # Interactive CLI setup wizard
|-- setup-tui.sh                 # TUI setup (requires gum)
|-- generate-certs.sh            # Certificate generation
|-- Makefile                     # Shortcuts for common operations
|-- site.yml                     # Main deployment playbook
|-- unlock-deploy-user.yml       # Unlock deployment user for redeployment
|-- wazuh-aio.yml               # All-in-One deployment (testing only)
|-- wazuh-distributed.yml       # Multi-node deployment (testing only)
|-- wazuh-agent.yml             # Agent-only deployment (testing only)
|
|-- inventory/
|   |-- hosts.yml               # Generated inventory (wazuh-deploy user)
|   +-- bootstrap.yml           # Bootstrap inventory (root/initial user)
|
|-- group_vars/
|   +-- all/
|       |-- main.yml            # Configuration variables
|       +-- vault.yml           # Encrypted credentials (Ansible Vault)
|
|-- scripts/
|   |-- manage-vault.sh         # Vault credential management
|   |-- migrate-from-main.sh    # Migrate from old main branch format
|   |-- deploy-with-rollback.sh # Deploy with automatic rollback support
|   |-- deploy-prep.sh          # Multi-host preparation
|   |-- prepare-client.sh       # Client host preparation
|   |-- lockdown-ansible-user.sh # Manual deploy user lockdown
|   |-- run-scheduled-backup.sh # Scheduled backup runner
|   +-- status.sh               # Quick service status check
|
|-- playbooks/
|   |-- wazuh-indexer.yml       # Indexer deployment
|   |-- wazuh-manager.yml       # Manager deployment
|   |-- wazuh-dashboard.yml     # Dashboard deployment
|   |-- wazuh-agents.yml        # Agent deployment
|   |-- pre-flight-checks.yml   # Pre-deployment validation
|   |-- certificate-management.yml  # Certificate rotation/renewal
|   |-- backup.yml              # Backup all components
|   |-- restore.yml             # Restore from backup
|   |-- health-check.yml        # Health monitoring
|   |-- health-check-alerts.yml # Health monitoring with alerting
|   |-- upgrade.yml             # In-place version upgrades
|   |-- rotate-credentials.yml  # Rotate deployed credentials
|   |-- canary-deploy.yml       # Staged canary deployment
|   |-- compliance-report.yml   # Compliance reporting
|   |-- secrets-integration.yml # External secrets integration
|   |-- setup-maintenance-cron.yml # Automated maintenance cron
|   |-- system-update.yml       # OS security updates
|   |-- log-cleanup.yml         # Log cleanup
|   +-- dr-validate.yml         # Disaster recovery validation
|
|-- roles/
|   |-- wazuh-indexer/          # Indexer role (includes index management)
|   |-- wazuh-manager/          # Manager role
|   |-- wazuh-dashboard/        # Dashboard role
|   |-- wazuh-agent/            # Agent role
|   +-- wazuh-monitoring/       # Prometheus exporters + Grafana dashboard
|
|-- files/
|   |-- certs/                  # Generated certificates
|   |-- custom_rules/           # Detection rules (project + SOCFortress community)
|   |-- custom_decoders/        # Log decoders
|   |-- cdb_lists/              # Threat intelligence lists
|   +-- agent_groups/           # Agent group config files
|
|-- lib/                        # Shared bash libraries for setup scripts
|-- backups/                    # Backup storage (created by backup.yml)
|-- keys/                       # Generated SSH keys
+-- client-prep/                # Client preparation package
```

## Security Features

### Credential Management

All credentials are stored in Ansible Vault (`group_vars/all/vault.yml`), encrypted with a randomly generated key (`.vault_password`). No plaintext passwords are stored anywhere.

```bash
./scripts/manage-vault.sh view      # View current credentials
./scripts/manage-vault.sh edit      # Edit credentials
./scripts/manage-vault.sh rotate    # Rotate all credentials
./scripts/manage-vault.sh rekey     # Change vault password
```

### Certificate Management

```bash
# Check certificate expiration
ansible-playbook playbooks/certificate-management.yml --tags check-expiry

# Rotate certificates (self-signed)
ansible-playbook playbooks/certificate-management.yml --tags rotate

# Renew expiring certificates (within 30 days)
ansible-playbook playbooks/certificate-management.yml --tags renew
```

### Post-Deployment Lockdown

After deployment, the `wazuh-deploy` user is automatically locked down on all hosts. Sudo access is restricted to only the unlock script and Wazuh status checks. SSH key access is retained for future deployments.

```bash
# Unlock before next deployment
ansible-playbook unlock-deploy-user.yml

# Disable automatic lockdown (in group_vars/all/main.yml)
wazuh_lockdown_deploy_user: false
```

### Index Management (ISM)

Automatic rollover prevents hitting OpenSearch's 1000 open index limit:

| Phase | Default Age | State |
|-------|-------------|-------|
| **Hot** | 0-7 days | Active writes |
| **Warm** | 7-30 days | Read-only, merged |
| **Cold** | 30-365 days | Closed (saves open index slots) |
| **Delete** | 365+ days | Removed |

Configure in `group_vars/all/main.yml`:
```yaml
wazuh_rollover_enabled: true
wazuh_rollover_max_size: "30gb"
wazuh_rollover_max_age: "1d"
wazuh_retention_days: 365
wazuh_close_cold_indices: true
```

## Operational Playbooks

### Pre-Flight Checks

```bash
ansible-playbook playbooks/pre-flight-checks.yml
ansible-playbook playbooks/pre-flight-checks.yml --tags quick
```

### Backup and Restore

```bash
# Create backup
ansible-playbook playbooks/backup.yml

# Include indexer data snapshots
ansible-playbook playbooks/backup.yml -e "include_indices=true"

# Restore from backup
ansible-playbook playbooks/restore.yml -e "restore_from=20260110T120000"
```

### Health Checks

```bash
ansible-playbook playbooks/health-check.yml
ansible-playbook playbooks/health-check.yml -e "check_agents=true"
ansible-playbook playbooks/health-check.yml -e "check_indices=true"
```

### Deployment with Rollback

```bash
./scripts/deploy-with-rollback.sh
./scripts/deploy-with-rollback.sh --list       # List rollback points
./scripts/deploy-with-rollback.sh --rollback   # Rollback to previous state
```

### Upgrade

```bash
ansible-playbook playbooks/upgrade.yml --tags check   # Check available upgrades
ansible-playbook playbooks/upgrade.yml                # Upgrade to version in config
ansible-playbook playbooks/upgrade.yml -e "target_version=4.15.0"  # Specific version
```

### System Updates

```bash
ansible-playbook playbooks/system-update.yml --tags check         # Check available updates
ansible-playbook playbooks/system-update.yml -e "security_only=true"  # Security patches only
```

## Configuration

All configuration is in `group_vars/all/main.yml`. Credentials are in the encrypted `group_vars/all/vault.yml`.

### Key Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `wazuh_version` | Wazuh version | 4.14.2 |
| `wazuh_indexer_heap_size` | Indexer JVM heap ("auto" = 50% RAM) | auto |
| `wazuh_rollover_enabled` | Enable automatic index rollover | true |
| `wazuh_close_cold_indices` | Close cold indices | true |
| `wazuh_retention_days` | Total data retention period | 365 |
| `wazuh_lockdown_deploy_user` | Lock down deploy user after deployment | true |
| `wazuh_configure_firewall` | Auto-configure firewall rules | true |

### Feature Toggles

| Variable | Default |
|----------|---------|
| `wazuh_vulnerability_detection_enabled` | true |
| `wazuh_fim_enabled` | true |
| `wazuh_rootkit_detection_enabled` | true |
| `wazuh_active_response_enabled` | true |
| `wazuh_sca_enabled` | true |
| `wazuh_syscollector_enabled` | true |
| `wazuh_log_collection_enabled` | true |

## Prometheus Monitoring (Optional)

```bash
ansible-playbook site.yml --tags monitoring -e wazuh_monitoring_enabled=true
```

| Exporter | Port | Metrics |
|----------|------|---------|
| **Indexer** | 9114 | Cluster health, JVM heap, disk, shards, document counts |
| **Manager** | 9115 | Active/disconnected agents, alerts by severity |

See [Monitoring Guide](docs/operations/monitoring.md) for Prometheus scrape config and Grafana dashboard setup.

## Custom Rules and Decoders

Detection rules are automatically deployed from `files/custom_rules/` and `files/custom_decoders/`.

### Included Rules

**Project-specific** (ID range `800100-800299`):
- `0800-attack-detection.xml` - Linux attack detection (reverse shells, credential dumping, container escape)
- `800200-win_powershell_rules.xml` - Windows PowerShell malicious command detection

**Community rules** from [SOCFortress Wazuh-Rules](https://github.com/socfortress/Wazuh-Rules):
- Windows Sysmon events 1-22 (process creation, network, DLL, registry, DNS, etc.)
- Linux auditd syscall monitoring
- Sysmon for Linux
- Suricata IDS/IPS enrichment
- YARA malware scan detection
- Manager health monitoring

### Agent Groups

Groups are pre-created during deployment. Default groups: `linux-servers`, `linux-web-servers`, `linux-db-servers`, `linux-docker-hosts`, `windows-servers`, `windows-dc`, `windows-workstations`, `macos-endpoints`.

Assign agents after enrollment:
```bash
/var/ossec/bin/agent_groups -a -i <agent_id> -g linux-web-servers
```

## Testing-Only Playbooks

These playbooks use role defaults and skip most security features. **Do not use for production.**

| Playbook | Description |
|----------|-------------|
| `wazuh-aio.yml` | All-in-One single-server deployment |
| `wazuh-distributed.yml` | Multi-node cluster deployment |
| `wazuh-agent.yml` | Agent-only deployment |

They do NOT include: vault encryption, SSH key generation, bootstrap, index management, certificate generation, client-prep, or post-deployment lockdown. For production, always use `setup.sh` + `site.yml`.

## Migrating from Older Versions

If upgrading from the old `main` branch format (plaintext `group_vars/all.yml`):

```bash
./scripts/migrate-from-main.sh
```

This converts plaintext credentials to the new vault-encrypted format, preserving your existing passwords.

## Troubleshooting

| Issue | Solution |
|-------|----------|
| Connection refused | Check firewall rules, verify service status |
| Certificate errors | Regenerate with `./generate-certs.sh` |
| Agent not connecting | Verify manager IP and port 1514 accessibility |
| Dashboard 401 errors | Run `./scripts/manage-vault.sh view` to verify credentials |
| Vault permission denied | Run with `sudo` or fix `.vault_password` permissions |
| Deploy user locked | Run `ansible-playbook unlock-deploy-user.yml` |
| Aggregation errors | Re-run `site.yml` to update index mappings |

### Log Locations

```bash
# Indexer
/var/log/wazuh-indexer/wazuh-indexer.log

# Manager
/var/ossec/logs/ossec.log

# Dashboard
/var/log/wazuh-dashboard/opensearch-dashboards.log

# Filebeat
/var/log/filebeat/filebeat
```

## Security Recommendations

- Back up `.vault_password` securely offline - required to decrypt credentials
- Use external CA certificates for production environments
- Restrict network access to management ports
- Regularly rotate credentials with `./scripts/manage-vault.sh rotate`
- Monitor certificate expiration
- Keep deployment user locked down between deployments
- Maintain regular backups

## License

Based on [wazuh/wazuh-ansible](https://github.com/wazuh/wazuh-ansible).

WAZUH - Copyright (C) 2016, Wazuh Inc. (License GPLv2)

## Links

- [Wazuh Documentation](https://documentation.wazuh.com)
- [SOCFortress Wazuh-Rules](https://github.com/socfortress/Wazuh-Rules) - Community detection rules
