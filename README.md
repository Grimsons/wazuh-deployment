# Wazuh Deployment

Production-ready automated deployment of Wazuh SIEM/XDR stack using Ansible with security hardening, automatic credential management, and comprehensive operational tooling.

## Overview

This project provides an enterprise-grade deployment solution for Wazuh with:

- **Secure by Default** - Ansible Vault encrypted credentials, API rate limiting, TLS 1.2+
- **Interactive Setup** - CLI wizard or beautiful TUI with deployment profiles (minimal/production/custom)
- **One-Command Bootstrap** - Automatic host preparation with SSH key deployment via `--tags bootstrap`
- **Client Preparation** - Cross-platform target host preparation (Ubuntu, Debian, RHEL, Arch Linux)
- **Multiple Deployment Modes** - All-in-One or Distributed multi-node cluster
- **Prometheus Monitoring** - Built-in exporters and pre-configured Grafana dashboard
- **Smart Index Management** - Automatic rollover, tiered retention, cold index closing to prevent 1000-index limit
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

Choose your preferred setup method:

```bash
# Option A: Beautiful TUI (recommended, requires gum)
./setup-tui.sh

# Option B: Traditional CLI wizard
./setup.sh
```

**TUI Setup** offers:
- Visual deployment profiles: **minimal** (single-node), **production** (cluster), **custom**
- Interactive host entry with validation
- Automatic SSH key generation
- Bootstrap inventory for first-time deployment

**CLI Setup** offers the same features with traditional prompts.

Both generate:
- `inventory/hosts.yml` - Ansible inventory
- `inventory/bootstrap.yml` - Initial connection inventory (for first deployment)
- `group_vars/all/main.yml` - Configuration variables
- `group_vars/all/vault.yml` - Encrypted credentials (Ansible Vault)
- `.vault_password` - Vault encryption key (keep secure!)
- `ansible.cfg` - Ansible settings
- `keys/wazuh_ansible_key` - SSH keypair for deployment
- `client-prep/` - Host preparation package (optional)
- `wazuh-client-prep.sh` - Self-extracting installer (optional)

### 2. Deploy (First Time - Bootstrap + Deploy)

For first-time deployment, bootstrap creates the `wazuh-deploy` user with SSH keys on target hosts, then deploys Wazuh—all in one command:

```bash
# If using password authentication for initial root access:
ansible-playbook site.yml --tags bootstrap,all --ask-pass

# If root already has your SSH key:
ansible-playbook site.yml --tags bootstrap,all
```

This connects as root (or your configured initial user), creates the deployment user, deploys SSH keys, then continues with full Wazuh deployment.

### 3. Deploy (Subsequent Runs)

After bootstrap, subsequent deployments use the `wazuh-deploy` user automatically:

```bash
ansible-playbook site.yml
```

### Alternative: Manual Host Preparation

If you prefer to prepare hosts manually instead of using bootstrap:

```bash
# Option A: Copy and run client-prep package
scp -r client-prep/ root@TARGET:/tmp/
ssh root@TARGET 'cd /tmp/client-prep && sudo ./install.sh'

# Option B: Use self-extracting installer
scp wazuh-client-prep.sh root@TARGET:/tmp/
ssh root@TARGET 'sudo bash /tmp/wazuh-client-prep.sh'

# Then deploy without bootstrap tag
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
├── setup.sh                     # Interactive CLI setup wizard
├── setup-tui.sh                 # Beautiful TUI setup (requires gum)
├── generate-certs.sh            # Certificate generation
├── site.yml                     # Main deployment playbook (includes bootstrap)
├── wazuh-aio.yml               # All-in-One deployment
├── wazuh-distributed.yml       # Multi-node cluster deployment
├── wazuh-agent.yml             # Agent-only deployment
├── .vault_password              # Ansible Vault encryption key (keep secure!)
│
├── inventory/
│   ├── hosts.yml               # Generated inventory (connects as wazuh-deploy)
│   └── bootstrap.yml           # Bootstrap inventory (connects as root)
│
├── group_vars/
│   └── all/
│       ├── main.yml            # Configuration variables
│       └── vault.yml           # Encrypted credentials (Ansible Vault)
│
├── lib/                         # Shared bash libraries
│   ├── colors.sh               # Terminal colors/formatting
│   ├── validation.sh           # Input validation functions
│   ├── generators.sh           # Password/key generation
│   ├── profiles.sh             # Deployment profiles
│   ├── prompts.sh              # User prompt helpers
│   └── client-prep.sh          # Client prep package generation
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
│   ├── wazuh-indexer/          # Indexer role (includes index management)
│   ├── wazuh-manager/          # Manager role
│   ├── wazuh-dashboard/        # Dashboard role
│   ├── wazuh-agent/            # Agent role
│   ├── wazuh-monitoring/       # Prometheus exporters + Grafana dashboard
│   └── ...
│
├── files/
│   ├── certs/                  # Generated certificates
│   ├── custom_rules/           # Detection rules - project-specific + SOCFortress community
│   ├── custom_decoders/        # Log decoders - project-specific + SOCFortress community
│   ├── cdb_lists/              # Threat intelligence lists (e.g., malicious-powershell)
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

### Index Management (ISM Policy)

**Automatic rollover** prevents hitting OpenSearch's 1000 open index limit:
- Rolls over indices by size (50GB default) or age (1 day default)
- Tiered storage: hot → warm → cold → delete
- **Cold indices are CLOSED** (not just read-only) to save open-index slots

Default retention tiers:
| Phase | Age | State |
|-------|-----|-------|
| **Hot** | 0-7 days | Active, fast storage |
| **Warm** | 7-30 days | Read-only, standard storage |
| **Cold** | 30-90 days | **Closed** (saves open index limit) |
| **Delete** | 90+ days | Removed |

Configure in `group_vars/all.yml`:
```yaml
wazuh_rollover_enabled: true
wazuh_rollover_max_size: "50gb"
wazuh_rollover_max_age: "1d"
wazuh_retention_days: 90
wazuh_close_cold_indices: true  # Critical for preventing 1000-index limit
```

### Prometheus Monitoring

Optional Prometheus exporters with a pre-built Grafana dashboard:

```bash
# Deploy monitoring after main deployment
ansible-playbook site.yml --tags monitoring -e wazuh_monitoring_enabled=true
```

**Metrics exported:**

| Exporter | Port | Metrics |
|----------|------|---------|
| **Indexer** | 9114 | Cluster health, JVM heap, disk, CPU, shards, document counts |
| **Manager** | 9115 | Active/disconnected agents, alerts by severity, rule groups |

**Prometheus scrape config:**
```yaml
scrape_configs:
  - job_name: 'wazuh-indexer'
    static_configs:
      - targets: ['indexer1:9114']
    scheme: https
    tls_config:
      insecure_skip_verify: true

  - job_name: 'wazuh-manager'
    static_configs:
      - targets: ['manager1:9115']
```

**Grafana dashboard** is auto-provisioned, or import manually:
```bash
# Copy to your Grafana instance
scp roles/wazuh-monitoring/files/grafana-wazuh-dashboard.json \
  user@grafana:/etc/grafana/provisioning/dashboards/
```

See [Monitoring Guide](docs/operations/monitoring.md) for detailed setup.

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
| `wazuh_indexer_heap_size` | Indexer JVM heap ("auto" = 50% RAM, max 32g) | auto |
| `wazuh_monitoring_enabled` | Enable Prometheus exporters | false |
| `wazuh_rollover_enabled` | Enable automatic index rollover | true |
| `wazuh_close_cold_indices` | Close cold indices (saves open-index slots) | true |

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

This deployment includes an extensive set of detection rules from multiple sources, deployed automatically to the Wazuh Manager.

### Included Detection Rules

#### Custom Rules (Project-Specific)

Rules developed specifically for this deployment (ID range `800100-800299`):

| File | Description | Rules |
|------|-------------|-------|
| `0800-attack-detection.xml` | Linux attack detection: reverse shells, credential dumping, container escape, SSH tunneling, ransomware indicators, persistence mechanisms | ~20 |
| `800200-win_powershell_rules.xml` | Windows PowerShell event log detection with malicious command matching | 12 |

#### Community Rules ([SOCFortress Wazuh-Rules](https://github.com/socfortress/Wazuh-Rules))

The following rules are sourced from the [SOCFortress Wazuh-Rules](https://github.com/socfortress/Wazuh-Rules) community repository, which provides MITRE ATT&CK-mapped detection rules for Wazuh:

**Windows Sysmon** (requires [Sysmon](https://learn.microsoft.com/en-us/sysinternals/downloads/sysmon) deployed on Windows agents):

| File | Sysmon Event | Description | Rules |
|------|-------------|-------------|-------|
| `100100-..._SYSMON_EVENT1.xml` | Event 1 | Process creation | 864+ |
| `102101-..._SYSMON_EVENT3.xml` | Event 3 | Network connections | ~50 |
| `106101-..._SYSMON_EVENT7.xml` | Event 7 | Image loaded (DLL) | ~40 |
| `109101-..._SYSMON_EVENT10.xml` | Event 10 | Process access | ~20 |
| `110101-..._SYSMON_EVENT11.xml` | Event 11 | File create | ~25 |
| `111101-..._SYSMON_EVENT12.xml` | Event 12 | Registry add/delete | ~80 |
| `112101-..._SYSMON_EVENT13.xml` | Event 13 | Registry value set | ~100 |
| `113101-..._SYSMON_EVENT14.xml` | Event 14 | Registry rename | ~70 |
| `114101-..._SYSMON_EVENT15.xml` | Event 15 | File create stream hash | ~10 |
| `116101-..._SYSMON_EVENT17.xml` | Event 17 | Pipe created | ~20 |
| `117101-..._SYSMON_EVENT18.xml` | Event 18 | Pipe connected | ~15 |
| `121101-..._SYSMON_EVENT22.xml` | Event 22 | DNS query | ~15 |
| `121201-..._SYSMON_EVENT6.xml` | Event 6 | Driver loaded | ~10 |

**Linux Detection:**

| File | Description | Rules |
|------|-------------|-------|
| `200110-auditd.xml` | Linux auditd syscall monitoring (file access, privilege escalation, persistence) | 64 |
| `200150-sysmon_for_linux_rules.xml` | Sysmon for Linux detection | 14 |

**Infrastructure & Other:**

| File | Description | Rules |
|------|-------------|-------|
| `100002-suricata.xml` | Suricata IDS/IPS alert enrichment | 8 |
| `500010-manager_logs.xml` | Wazuh Manager health monitoring | ~5 |
| `200990-healthcheck.xml` | Wazuh infrastructure health checks | 7 |
| `200100-yara_rules.xml` | YARA malware scan result detection | 4 |
| `600000-active_response.xml` | Active response action alerts | 3 |
| `200070-sysmon_reload.xml` | Sysmon configuration reload detection | ~2 |

#### Custom Decoders

| File | Source | Description |
|------|--------|-------------|
| `auditd_decoders.xml` | [SOCFortress](https://github.com/socfortress/Wazuh-Rules) | Enhanced auditd log parsing |
| `decoder-linux-sysmon.xml` | [SOCFortress](https://github.com/socfortress/Wazuh-Rules) | Sysmon for Linux event decoding |
| `decoder-manager-logs.xml` | [SOCFortress](https://github.com/socfortress/Wazuh-Rules) | Wazuh Manager log parsing |
| `yara_decoders.xml` | [SOCFortress](https://github.com/socfortress/Wazuh-Rules) | YARA scan result decoding |

#### CDB Lists (Threat Intelligence)

| File | Source | Description |
|------|--------|-------------|
| `malicious-powershell` | [SOCFortress](https://github.com/socfortress/Wazuh-Rules) | Known malicious PowerShell command patterns |

### File-based Deployment

All rules are automatically deployed from the `files/` directory:
```
files/
├── custom_rules/           # Detection rules (*.xml)
│   ├── 0800-*.xml          # Project-specific rules (800xxx IDs)
│   ├── 100xxx-*.xml        # SOCFortress Windows Sysmon rules
│   ├── 200xxx-*.xml        # SOCFortress Linux/infra rules
│   ├── 500xxx-*.xml        # SOCFortress manager rules
│   ├── 600xxx-*.xml        # SOCFortress active response rules
│   └── 800200-*.xml        # Project-specific PowerShell rules
├── custom_decoders/        # Log decoders (*.xml)
│   ├── auditd_decoders.xml
│   ├── decoder-linux-sysmon.xml
│   ├── decoder-manager-logs.xml
│   └── yara_decoders.xml
├── cdb_lists/              # Threat intelligence lookup lists
│   └── malicious-powershell
└── agent_groups/           # Agent group config files
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

Agent groups are **pre-created during deployment** so they appear in the Wazuh Dashboard immediately, ready for agent assignment. Group configurations are pushed from the Manager to agents and are **additive** to the agent's local `ossec.conf` - they add role-specific monitoring on top of the platform-specific base config.

### Default Groups

| Group | OS | Description | Key Additions |
|-------|-----|-------------|---------------|
| `linux-servers` | Linux | General-purpose servers | FIM on `/opt`, `/root/.ssh`, cron directories |
| `linux-web-servers` | Linux | Nginx, Apache, HAProxy | Web logs, `/var/www` FIM with change tracking |
| `linux-db-servers` | Linux | MySQL, PostgreSQL, MongoDB | Database logs, config FIM, data dir ignores |
| `linux-docker-hosts` | Linux | Docker/container hosts | Docker listener wodle, `/etc/docker` FIM |
| `windows-servers` | Windows | General-purpose servers | IIS FIM, server baseline labels |
| `windows-dc` | Windows | Domain Controllers | AD event channels, NTDS/SYSVOL/GPO FIM, AD registry |
| `windows-workstations` | Windows | End-user desktops | User startup FIM, Downloads monitoring (executables) |
| `macos-endpoints` | macOS | Workstations/laptops | User preferences, shell profile FIM |

### Assigning Agents to Groups

After agents enroll, assign them to groups via:

```bash
# CLI (on the Manager)
/var/ossec/bin/agent_groups -a -i <agent_id> -g linux-web-servers

# API
curl -k -X PUT "https://manager:55000/agents/<agent_id>/group/linux-web-servers" \
  -H "Authorization: Bearer $TOKEN"

# Or use the Wazuh Dashboard UI: Agents → Select agent → Groups
```

### Customizing Groups

Override in `group_vars/all.yml` to add custom groups or modify defaults:

```yaml
wazuh_agent_groups:
  - name: "linux-web-servers"
    os: "Linux"
    description: "Web servers with custom paths"
    config:
      syscheck:
        directories:
          - path: "/var/www"
            realtime: true
            report_changes: true
      localfile:
        - location: "/var/log/nginx/access.log"
          format: "syslog"
        - location: "Security"              # Windows event channels also supported
          format: "eventchannel"
          query: "Event/System[EventID=4625]"
      wodle:
        - name: "docker-listener"
          enabled: true
      labels:
        - key: "group.role"
          value: "web-server"
```

Custom files per group can be placed in `files/agent_groups/<group_name>/` and will be deployed to the Manager's shared directory for that group.

## Deployment Modes

### Recommended: Setup Script + site.yml (Production)

The full workflow with all security features:

```bash
# 1. Run interactive setup (generates inventory, vault, certs, SSH keys)
./setup-tui.sh   # or ./setup.sh

# 2. Deploy with bootstrap (first time)
ansible-playbook site.yml --tags bootstrap,all

# 3. Subsequent deployments
ansible-playbook site.yml
```

**Includes:** Vault-encrypted credentials, SSH key generation, bootstrap workflow, index management, certificate generation, client-prep package, deployment lockdown.

### Quick: wazuh-aio.yml (Testing Only)

Minimal single-server deployment for quick testing:

```bash
ansible-playbook wazuh-aio.yml -e "target_host=192.168.1.10"
```

> **Warning:** This is a bare-bones deployment using role defaults. It does NOT include:
> - Credential encryption (Ansible Vault)
> - SSH key generation
> - Bootstrap workflow
> - Index management policies
> - Certificate generation
> - Client preparation package
> - Post-deployment lockdown
>
> **Use only for local testing. For anything production-facing, use the setup script workflow above.**

### Quick: wazuh-distributed.yml (Testing Only)

Same as above but for multi-node testing. Requires manual inventory setup.

```bash
ansible-playbook wazuh-distributed.yml
```

### Selective Deployment (Tags)

Deploy specific components using the full workflow:

```bash
ansible-playbook site.yml --tags indexer
ansible-playbook site.yml --tags manager
ansible-playbook site.yml --tags dashboard
ansible-playbook site.yml --tags bootstrap   # Bootstrap only
ansible-playbook site.yml --tags monitoring  # Prometheus exporters
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
- [SOCFortress Wazuh-Rules](https://github.com/socfortress/Wazuh-Rules) - Community detection rules (MITRE ATT&CK mapped)
- [SOCFortress](https://www.socfortress.co/) - Open-source security operations community
