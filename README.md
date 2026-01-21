# Wazuh Deployment

Production-ready automated deployment of Wazuh SIEM/XDR stack using Ansible with security hardening, automatic credential management, and comprehensive operational tooling.

## Overview

This project provides an enterprise-grade deployment solution for Wazuh with:

- **Secure by Default** - Ansible Vault encrypted credentials, API rate limiting, TLS 1.2+
- **Interactive Setup** - Configure your deployment through a guided CLI wizard
- **Client Preparation** - Cross-platform target host preparation (Ubuntu, Debian, RHEL, Arch Linux)
- **Multiple Deployment Modes** - All-in-One or Distributed multi-node cluster
- **Certificate Management** - Self-signed or external CA with rotation/renewal playbooks
- **Encrypted Secrets** - Ansible Vault for credential encryption (enabled by default)
- **Post-Deployment Security** - Automatic lockdown of deployment user after completion
- **Operational Tooling** - Backup/restore, health checks, and log rotation
- **Extensible** - Custom rules, decoders, agent groups, and integrations
- **Cross-Platform Agents** - Linux, Windows, and macOS support
- **Cloud Integrations** - AWS, Azure, GCP, Office 365, GitHub audit logs

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
- Ansible 2.12+
- Python 3.8+
- Bash shell

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
./setup.sh
```

The wizard configures:
- Wazuh version selection (default: 4.14.2)
- Node IP addresses (indexer, manager, dashboard)
- Agent hosts (optional)
- Feature toggles (vulnerability detection, FIM, SCA, etc.)
- Email alerts, syslog output, and integrations (Slack, VirusTotal)
- **Automatic certificate generation** (no separate step needed)

Generated files:
- `inventory/hosts.yml` - Ansible inventory
- `group_vars/all/main.yml` - Configuration variables
- `group_vars/all/vault.yml` - Encrypted credentials (Ansible Vault)
- `.vault_password` - Vault encryption key (keep secure!)
- `ansible.cfg` - Ansible settings
- `keys/` - SSH keypair for deployment
- `client-prep/` - Host preparation package
- `files/certs/` - SSL/TLS certificates

### 2. Prepare Target Hosts

```bash
# Option A: Copy and run
scp -r client-prep/ root@TARGET:/tmp/
ssh root@TARGET 'bash /tmp/client-prep/install.sh'

# Option B: Multi-host deployment
./scripts/deploy-prep.sh 192.168.1.10 192.168.1.11 192.168.1.12
```

Supports: Ubuntu, Debian, RHEL/CentOS, Rocky Linux, Fedora, SUSE, and **Arch Linux**.

### 3. Test Connectivity

```bash
ansible all -m ping
```

### 4. Deploy

```bash
# Full stack deployment
ansible-playbook site.yml

# Or individual components
ansible-playbook playbooks/wazuh-indexer.yml
ansible-playbook playbooks/wazuh-manager.yml
ansible-playbook playbooks/wazuh-dashboard.yml
ansible-playbook playbooks/wazuh-agents.yml
```

### 5. Access Dashboard

After setup completes, credentials are displayed on screen and stored encrypted in Ansible Vault. To view them later:

```bash
./scripts/manage-vault.sh view
```

Access the dashboard at `https://<dashboard-ip>:443` using the `admin` user.

### 6. Redeployment (Future Updates)

The deployment user is **automatically locked down** after deployment for security. Before running another deployment:

```bash
# Unlock deployment user on all hosts
ansible-playbook unlock-deploy-user.yml

# Run your deployment
ansible-playbook site.yml

# User is automatically re-locked at the end
```

## Project Structure

```
wazuh-deployment/
├── setup.sh                     # Interactive setup wizard
├── generate-certs.sh            # Certificate generation
├── site.yml                     # Main deployment playbook
├── wazuh-aio.yml               # All-in-One deployment
├── wazuh-distributed.yml       # Multi-node cluster deployment
├── wazuh-agent.yml             # Agent-only deployment
├── .vault_password              # Ansible Vault encryption key (keep secure!)
│
├── inventory/
│   └── hosts.yml               # Generated inventory
│
├── group_vars/
│   └── all/
│       ├── main.yml            # Configuration variables
│       └── vault.yml           # Encrypted credentials (Ansible Vault)
│
├── scripts/
│   ├── manage-vault.sh         # Vault credential management
│   ├── deploy-with-rollback.sh # Deploy with automatic rollback support
│   ├── setup-health-cron.sh    # Setup automated health monitoring
│   ├── prepare-client.sh       # Client host preparation
│   └── deploy-prep.sh          # Multi-host preparation
│
├── unlock-deploy-user.yml       # Unlock deployment user for redeployment
│
├── playbooks/
│   ├── wazuh-indexer.yml       # Indexer deployment
│   ├── wazuh-manager.yml       # Manager deployment
│   ├── wazuh-dashboard.yml     # Dashboard deployment
│   ├── wazuh-agents.yml        # Agent deployment
│   ├── pre-flight-checks.yml   # Pre-deployment validation
│   ├── certificate-management.yml  # Certificate validation/rotation/renewal
│   ├── backup.yml              # Backup all components
│   ├── restore.yml             # Restore from backup
│   ├── health-check.yml        # Health monitoring
│   ├── health-check-alerts.yml # Health monitoring with alerting
│   └── upgrade.yml             # In-place version upgrades
│
├── roles/
│   ├── wazuh-indexer/          # Indexer role
│   ├── wazuh-manager/          # Manager role
│   ├── wazuh-dashboard/        # Dashboard role
│   ├── wazuh-agent/            # Agent role
│   └── ...
│
├── files/
│   ├── certs/                  # Generated certificates
│   ├── custom_rules/           # Custom detection rules (*.xml)
│   ├── custom_decoders/        # Custom log decoders (*.xml)
│   ├── cdb_lists/              # Threat intelligence lists
│   └── agent_groups/           # Agent group config files
│
├── backups/                    # Backup storage (created by backup.yml)
├── keys/                       # Generated SSH keys
└── client-prep/                # Client preparation package
```

## Security Features

### Ansible Vault Credential Management
- **Encrypted by default** - All credentials stored in Ansible Vault
- Secure random password generation (24+ characters)
- No hardcoded default passwords
- Vault password file with restricted permissions (0600)
- Automatic propagation to all components

### Credential Management Commands
```bash
./scripts/manage-vault.sh view      # View current credentials
./scripts/manage-vault.sh edit      # Edit credentials
./scripts/manage-vault.sh rotate    # Rotate all credentials
./scripts/manage-vault.sh rekey     # Change vault password
```

### API Security Hardening
| Setting | Value | Description |
|---------|-------|-------------|
| `max_login_attempts` | 5 | Failed attempts before lockout |
| `block_time` | 900s (15min) | Lockout duration |
| `max_request_per_minute` | 100 | Rate limiting |
| `remote_commands` | disabled | Prevents remote code execution |
| `ssl_protocol` | TLSv1.2 | Minimum TLS version |

### Certificate Management
- **Self-signed** (default) - Automatically generated during setup
- **External CA** - Optional support for enterprise CA certificates
- Certificate rotation and renewal playbooks
- Certificate expiration monitoring

```bash
# Check certificate expiration
ansible-playbook playbooks/certificate-management.yml --tags check-expiry

# Rotate certificates (self-signed)
ansible-playbook playbooks/certificate-management.yml --tags rotate

# Rotate certificates (external CA - place new certs in files/certs/ first)
ansible-playbook playbooks/certificate-management.yml --tags rotate -e "external_ca=true"

# Renew expiring certificates (within 30 days)
ansible-playbook playbooks/certificate-management.yml --tags renew
```

### Dashboard Security
- TLS 1.2/1.3 only
- Secure cookies (HttpOnly, Secure, SameSite=Strict)
- HTTP security headers (CSP, X-Frame-Options, X-XSS-Protection)
- Session timeout configuration

### Index Data Retention (ISM Policy)
Default 3-year retention with tiered storage:
- **Hot**: 0-30 days (fast storage)
- **Warm**: 30-90 days (standard storage)
- **Cold**: 90-1095 days (archive storage)
- **Delete**: After 1095 days (3 years)

## Operational Playbooks

### Pre-Flight Checks

```bash
# Full validation before deployment
ansible-playbook playbooks/pre-flight-checks.yml

# Quick validation (skip slow network tests)
ansible-playbook playbooks/pre-flight-checks.yml --tags quick

# Check specific components
ansible-playbook playbooks/pre-flight-checks.yml --tags indexer
ansible-playbook playbooks/pre-flight-checks.yml --tags manager
```

### Deployment with Rollback

```bash
# Deploy with automatic rollback point (recommended)
./scripts/deploy-with-rollback.sh

# List available rollback points
./scripts/deploy-with-rollback.sh --list

# Rollback to previous state
./scripts/deploy-with-rollback.sh --rollback

# Rollback to specific point
./scripts/deploy-with-rollback.sh --rollback --point 20260120T143000

# Clean old rollback points (keep 3 most recent)
./scripts/deploy-with-rollback.sh --cleanup 3
```

### Backup

```bash
# Full backup
ansible-playbook playbooks/backup.yml

# Custom backup location
ansible-playbook playbooks/backup.yml -e "backup_dest=/mnt/backups"

# Include indexer data snapshots
ansible-playbook playbooks/backup.yml -e "backup_indexer_data=true"
```

Backups include:
- Configuration files
- Certificates
- Agent keys
- Custom rules and decoders
- RBAC database

### Restore

```bash
# Restore from specific backup
ansible-playbook playbooks/restore.yml -e "restore_from=20260110T120000"

# Selective restore
ansible-playbook playbooks/restore.yml -e "restore_from=20260110T120000" -e "restore_indexer=false"
```

### Health Check

```bash
# Basic health check
ansible-playbook playbooks/health-check.yml

# Detailed with agent status
ansible-playbook playbooks/health-check.yml -e "check_agents=true"

# Include index statistics
ansible-playbook playbooks/health-check.yml -e "check_indices=true"
```

### Health Check with Alerting

```bash
# Health check with Slack alerts
ansible-playbook playbooks/health-check-alerts.yml -e "alert_slack=true"

# Health check with email alerts
ansible-playbook playbooks/health-check-alerts.yml -e "alert_email=true"

# Health check writing to file (for monitoring integration)
ansible-playbook playbooks/health-check-alerts.yml -e "alert_file=true"

# Also alert on warnings (not just critical)
ansible-playbook playbooks/health-check-alerts.yml -e "alert_slack=true" -e "alert_on_warning=true"

# Setup automated health monitoring (cron)
./scripts/setup-health-cron.sh --interval 5 --slack
./scripts/setup-health-cron.sh --remove  # Remove cron job
```

## Configuration

### Key Variables (group_vars/all/main.yml)

| Variable | Description | Default |
|----------|-------------|---------|
| `wazuh_version` | Wazuh version | 4.14.2 |
| `wazuh_indexer_http_port` | Indexer HTTP port | 9200 |
| `wazuh_manager_api_port` | Manager API port | 55000 |
| `wazuh_dashboard_port` | Dashboard HTTPS port | 443 |
| `wazuh_indexer_heap_size` | Indexer JVM heap | 4g |

### Feature Toggles

| Variable | Description | Default |
|----------|-------------|---------|
| `wazuh_vulnerability_detection_enabled` | Vulnerability detection | true |
| `wazuh_fim_enabled` | File integrity monitoring | true |
| `wazuh_rootkit_detection_enabled` | Rootkit detection | true |
| `wazuh_active_response_enabled` | Active response | true |
| `wazuh_configure_firewall` | Auto-configure firewall | true |

### Log Rotation

| Variable | Description | Default |
|----------|-------------|---------|
| `wazuh_log_rotation_enabled` | Enable log rotation | true |
| `wazuh_log_rotation_max_size` | Max log file size | 100M |
| `wazuh_log_rotation_keep_days` | Days to retain logs | 30 |
| `wazuh_log_rotation_compress` | Compress rotated logs | true |

### Data Retention

| Variable | Description | Default |
|----------|-------------|---------|
| `wazuh_retention_enabled` | Enable ISM policy | true |
| `wazuh_retention_days` | Total retention period | 1095 (3 years) |
| `wazuh_retention_warm_after_days` | Move to warm tier | 30 |
| `wazuh_retention_cold_after_days` | Move to cold tier | 90 |

## Integrations

All integrations are configurable via `setup.sh` or `group_vars/all.yml`:

### Cloud Security
- **AWS**: CloudTrail, GuardDuty, VPC Flow Logs, WAF, ALB/NLB, S3, Config
- **Azure**: Activity Logs, Sign-in Logs, Log Analytics, Graph API
- **GCP**: Pub/Sub, Cloud Storage buckets

### Alerting
- **Slack**: Webhook notifications (configurable in setup.sh)
- **PagerDuty**: Incident management
- **Email**: SMTP alerts (configurable in setup.sh)
- **Syslog**: SIEM forwarding (default/JSON/CEF formats)

### Threat Intelligence
- **VirusTotal**: File hash lookups (configurable in setup.sh)
- **CDB Lists**: Custom IP/domain blocklists

### Container Security
- **Docker**: Container event monitoring via docker-listener wodle

### Microsoft & GitHub
- **Office 365**: Azure AD, Exchange, SharePoint, DLP audit logs
- **GitHub**: Enterprise audit logs for organizations

## Custom Rules and Decoders

### File-based Deployment
Place custom content in the `files/` directory:
```
files/
├── custom_rules/
│   └── my_rules.xml
├── custom_decoders/
│   └── my_decoders.xml
└── cdb_lists/
    └── malicious-ips
```

### Inline Rules (group_vars/all.yml)
```yaml
wazuh_custom_rules:
  - id: 100001
    level: 10
    description: "SSH brute force from external IP"
    if_sid: 5710
    srcip: "!192.168.0.0/16"
    frequency: 5
    timeframe: 120
    same_source_ip: true
    mitre:
      techniques:
        - "T1110"
```

## Agent Groups

Define agent groups with custom configurations:

```yaml
wazuh_agent_groups:
  - name: "linux-servers"
    description: "Linux production servers"
    config:
      syscheck:
        enabled: true
        directories:
          - path: "/etc"
            realtime: true
          - path: "/var/www"
            report_changes: true
      localfile:
        - location: "/var/log/syslog"
          format: "syslog"
      labels:
        - key: "environment"
          value: "production"
```

## Deployment Modes

### All-in-One (Single Server)

```bash
ansible-playbook wazuh-aio.yml -e "target_host=192.168.1.10"
```

### Distributed Cluster

```bash
ansible-playbook wazuh-distributed.yml
```

### Selective Deployment (Tags)

```bash
ansible-playbook site.yml --tags indexer
ansible-playbook site.yml --tags manager
ansible-playbook site.yml --tags dashboard
```

## Post-Deployment Verification

### Check Services

```bash
# On Indexer
systemctl status wazuh-indexer

# On Manager
systemctl status wazuh-manager
systemctl status filebeat
/var/ossec/bin/agent_control -l

# On Dashboard
systemctl status wazuh-dashboard
```

### Verify Cluster Health

```bash
# Run health check playbook
ansible-playbook playbooks/health-check.yml

# Or manually check indexer
curl -k -u admin:<password> https://localhost:9200/_cluster/health?pretty
```

## Troubleshooting

### Common Issues

| Issue | Solution |
|-------|----------|
| Connection refused | Check firewall rules, verify service status |
| Certificate errors | Regenerate with `./generate-certs.sh` |
| Agent not connecting | Verify manager IP and port 1514 accessibility |
| Dashboard 401 errors | Run `./scripts/manage-vault.sh view` to verify credentials |
| No alerts in dashboard | Verify Filebeat is running on manager |

### View Logs

```bash
# Indexer
tail -f /var/log/wazuh-indexer/wazuh-indexer.log

# Manager
tail -f /var/ossec/logs/ossec.log

# Dashboard
tail -f /var/log/wazuh-dashboard/opensearch-dashboards.log

# Filebeat
tail -f /var/log/filebeat/filebeat
```

### Reset/Rotate Credentials

```bash
# Rotate all credentials (generates new passwords)
./scripts/manage-vault.sh rotate
ansible-playbook site.yml  # Redeploy with new credentials

# View current credentials
./scripts/manage-vault.sh view

# Change vault encryption password
./scripts/manage-vault.sh rekey
```

## Upgrading

The upgrade playbook provides safe in-place version upgrades with automatic backup, version validation, and rollback support.

### Basic Upgrade

```bash
# Upgrade to the version specified in group_vars/all.yml
ansible-playbook playbooks/upgrade.yml
```

### Check Current Versions (No Changes)

```bash
# View current vs target versions without making changes
ansible-playbook playbooks/upgrade.yml --tags check
```

### Upgrade to Specific Version

```bash
# Upgrade to a specific version
ansible-playbook playbooks/upgrade.yml -e "target_version=4.15.0"
```

### Selective Component Upgrades

```bash
# Upgrade only specific components
ansible-playbook playbooks/upgrade.yml --tags indexer
ansible-playbook playbooks/upgrade.yml --tags manager
ansible-playbook playbooks/upgrade.yml --tags dashboard
ansible-playbook playbooks/upgrade.yml --tags agent -e "upgrade_agents=true"
```

### Include Agent Upgrades

Agents are skipped by default for safety. Enable with:

```bash
ansible-playbook playbooks/upgrade.yml -e "upgrade_agents=true"

# Upgrade in smaller batches (default: 10)
ansible-playbook playbooks/upgrade.yml -e "upgrade_agents=true" -e "agent_batch_size=5"
```

### Skip Confirmation Prompt

```bash
ansible-playbook playbooks/upgrade.yml -e "skip_confirmation=true"
```

### Upgrade Features

- **Automatic backup** - Pre-upgrade backup created before any changes
- **Version validation** - Validates version format and upgrade path (no downgrades)
- **Major version warning** - Alerts when upgrading across major versions
- **Rolling upgrades** - Cluster nodes upgraded one at a time
- **Cluster-aware** - Manages shard allocation during indexer upgrades
- **Post-upgrade validation** - Verifies all components are healthy after upgrade

### Rollback After Failed Upgrade

```bash
# Restore from pre-upgrade backup
ansible-playbook playbooks/restore.yml -e "restore_from=pre-upgrade-TIMESTAMP"

# Or use the rollback script
./scripts/deploy-with-rollback.sh --rollback
```

### Upgrade Order

The playbook upgrades components in the correct order:
1. Wazuh Indexer (one node at a time)
2. Wazuh Manager (one node at a time)
3. Filebeat (on managers)
4. Wazuh Dashboard
5. Wazuh Agents (batched)

## Post-Deployment Security Lockdown

After deployment completes, the Ansible deployment user (`wazuh-deploy`) is automatically locked down on all hosts:

- SSH access remains enabled (for future deployments)
- Sudo access is restricted to only:
  - Unlock script (`/usr/local/bin/wazuh-unlock-deploy`)
  - Ansible fact gathering
  - Wazuh status checks

### Re-enabling for Updates

Before running any new deployment or update:

```bash
# Unlock all hosts
ansible-playbook unlock-deploy-user.yml

# Run your deployment
ansible-playbook site.yml
# User is automatically re-locked at completion
```

### Manual Unlock (if needed)

```bash
# SSH to host and run unlock script
ssh wazuh-deploy@HOST 'sudo /usr/local/bin/wazuh-unlock-deploy'
```

### Disabling Lockdown

To disable automatic lockdown, set in `group_vars/all.yml`:
```yaml
wazuh_lockdown_deploy_user: false
```

## Security Recommendations

- **Back up `.vault_password`** - Required to decrypt credentials; store securely offline
- Use external CA certificates for production environments
- Restrict network access to management ports
- Enable audit logging on all nodes
- Regularly rotate credentials using `./scripts/manage-vault.sh rotate`
- Monitor certificate expiration with `ansible-playbook playbooks/certificate-management.yml --tags check-expiry`
- Monitor health check results
- Maintain regular backups
- Keep deployment user locked down between deployments

## License

Based on [wazuh/wazuh-ansible](https://github.com/wazuh/wazuh-ansible).

WAZUH - Copyright (C) 2016, Wazuh Inc. (License GPLv2)

## Links

- [Wazuh Documentation](https://documentation.wazuh.com)
- [Wazuh Ansible Docs](https://documentation.wazuh.com/current/deploying-with-ansible/index.html)
- [Wazuh GitHub](https://github.com/wazuh)
