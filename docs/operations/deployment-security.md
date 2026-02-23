# Deployment Security Guide

This document covers security features and best practices specific to this Wazuh Ansible deployment.

## Credential Management

### Ansible Vault (Default)

All credentials are encrypted using Ansible Vault by default:

| File | Purpose |
|------|---------|
| `.vault_password` | Encryption key for Ansible Vault (KEEP SECURE!) |
| `group_vars/all/vault.yml` | Encrypted credentials storage |

Credentials are displayed at the end of `setup.sh` and stored only in the encrypted vault.

### Vault Management Commands

```bash
# View current credentials
./scripts/manage-vault.sh view

# Edit credentials
./scripts/manage-vault.sh edit

# Rotate all credentials
./scripts/manage-vault.sh rotate

# Change vault encryption password
./scripts/manage-vault.sh rekey
```

### Auto-Generated Credentials

All passwords are automatically generated with the following characteristics:
- 24+ characters length
- Mix of uppercase, lowercase, numbers, and symbols
- Compliant with Wazuh's password requirements
- Stored encrypted in Ansible Vault

### Best Practices

1. **Back up `.vault_password`**: Store this file securely offline - you cannot decrypt credentials without it
2. **Access control**: Restrict access to deployment host and vault password
3. **Rotation**: Rotate credentials periodically using `./scripts/manage-vault.sh rotate`
4. **Rekey periodically**: Change the vault encryption password with `./scripts/manage-vault.sh rekey`

## Certificate Management

### Self-Signed vs External CA

The deployment supports two certificate modes:

| Mode | Use Case | Configuration |
|------|----------|---------------|
| Self-Signed (default) | Development, testing, small deployments | Auto-generated during setup |
| External CA | Production, enterprise environments | User-provided certificates |

### Certificate Management Playbook

```bash
# Check certificate expiration
ansible-playbook playbooks/certificate-management.yml --tags check-expiry

# Validate certificates
ansible-playbook playbooks/certificate-management.yml --tags validate

# Rotate certificates (self-signed)
ansible-playbook playbooks/certificate-management.yml --tags rotate

# Rotate certificates (external CA)
ansible-playbook playbooks/certificate-management.yml --tags rotate -e "external_ca=true"

# Renew expiring certificates (within 30 days)
ansible-playbook playbooks/certificate-management.yml --tags renew
```

### External CA Requirements

When using external CA certificates, place them in `files/certs/`:

| File | Purpose |
|------|---------|
| `root-ca.pem` | Root CA certificate |
| `root-ca-key.pem` | Root CA private key (optional, needed for renewal) |
| `admin.pem`, `admin-key.pem` | Admin certificate for indexer operations |
| `indexer-N.pem`, `indexer-N-key.pem` | Indexer node certificates |
| `manager-N.pem`, `manager-N-key.pem` | Manager node certificates |
| `dashboard.pem`, `dashboard-key.pem` | Dashboard certificate |

Certificates must include proper Subject Alternative Names (SANs) for all hostnames and IP addresses.

### Certificate Backup

Certificate backups are automatically created before rotation in `files/certs/backup/TIMESTAMP/`.

## Post-Deployment User Lockdown

### Overview

After deployment completes, the Ansible deployment user (`wazuh-deploy`) is automatically locked down. This reduces the attack surface by limiting what the deployment user can do on managed hosts.

### What Gets Locked

When locked, the deployment user can only:
- Run the unlock script (`/usr/local/bin/wazuh-unlock-deploy`)
- Execute Python for Ansible fact gathering
- Check Wazuh service status (`systemctl status wazuh-*`)

### Unlocking for Redeployment

```bash
# From control node - unlock all hosts
ansible-playbook unlock-deploy-user.yml

# Or use the make shortcut:
make unlock

# Manual unlock on single host
ssh wazuh-deploy@<host-ip> 'sudo /usr/local/bin/wazuh-unlock-deploy'
```

### Disabling Lockdown

To disable automatic lockdown:

```yaml
# In group_vars/all/main.yml
wazuh_lockdown_deploy_user: false
```

Or skip the lockdown play during deployment:

```bash
ansible-playbook site.yml --skip-tags lockdown
```

## Agent Enrollment Security

### Password-Based Enrollment

By default, agents must provide a password to enroll with the manager:

```yaml
wazuh_authd_use_password: true
```

The enrollment password is:
- Auto-generated during setup
- Stored encrypted in `group_vars/all/vault.yml`
- Deployed to `/var/ossec/etc/authd.pass` on the manager
- Deployed to agents during agent role execution

### SSL/TLS for Enrollment

Agent enrollment uses TLS with:
- Strong cipher suites (no weak ciphers)
- Hostname verification (prevents rogue manager attacks)
- Certificate-based authentication

```yaml
wazuh_authd_ssl_verify_host: true
wazuh_authd_ssl_ciphers: "HIGH:!ADH:!EXP:!MD5:!RC4:!3DES:!CAMELLIA:@STRENGTH"
```

## API Security Hardening

### Rate Limiting

The Wazuh API is protected against brute-force attacks:

| Setting | Default | Description |
|---------|---------|-------------|
| `wazuh_manager_api_max_login_attempts` | 5 | Failed attempts before lockout |
| `wazuh_manager_api_block_time` | 900 | Lockout duration (seconds) |
| `wazuh_manager_api_max_requests_per_minute` | 100 | Request rate limit |

### Remote Command Execution

Remote command execution via API is disabled by default:

```yaml
wazuh_manager_api_allow_remote_localfile: false
wazuh_manager_api_allow_remote_wodle: false
```

Only enable if absolutely necessary and with network restrictions in place.

## TLS Configuration

### Minimum Protocol Version

All components use TLS 1.2 minimum:

```yaml
wazuh_tls_minimum_version: "TLSv1.2"
```

### Cipher Suites

Strong, compliance-ready cipher suites:

```yaml
wazuh_tls_ciphers: "TLS_AES_256_GCM_SHA384:TLS_CHACHA20_POLY1305_SHA256:..."
```

### Certificate Verification

For production environments:

```yaml
wazuh_ssl_verify_certificates: true  # Verify all SSL connections
wazuh_ssl_verify_hostname: true      # Verify hostnames in certificates
```

## Dashboard Security

### Session Management

```yaml
wazuh_dashboard_session_timeout: 60  # Session timeout in minutes
```

### Cookie Security

```yaml
wazuh_dashboard_cookie_secure: true      # HTTPS-only cookies
wazuh_dashboard_cookie_same_site: "Strict"  # CSRF protection
```

### HTTP Security Headers

```yaml
wazuh_dashboard_xframe_options: "DENY"  # Clickjacking protection
wazuh_dashboard_csp_strict: true        # Content Security Policy
```

## Network Security

### Firewall Configuration

When enabled, the deployment configures host firewalls:

```yaml
wazuh_configure_firewall: true
```

Opened ports:
- 1514/tcp - Agent communication
- 1515/tcp - Agent enrollment
- 1516/tcp - Manager cluster (if enabled)
- 9200/tcp - Indexer API
- 9300/tcp - Indexer cluster
- 443/tcp - Dashboard HTTPS
- 55000/tcp - Manager API

### Network Segmentation Recommendations

1. **Management network**: Isolate indexer, manager, and dashboard on dedicated VLAN
2. **Agent network**: Allow only ports 1514, 1515 from agent networks
3. **Admin access**: Restrict dashboard (443) and API (55000) to admin networks

## Compliance Considerations

### Audit Logging

Enable audit logging for compliance requirements:

```yaml
wazuh_audit_logging_enabled: true
wazuh_audit_log_type: "internal_opensearch"
```

### Data Retention

Configure retention to meet compliance requirements:

```yaml
wazuh_retention_enabled: true
wazuh_retention_days: 1095  # 3 years for most compliance frameworks
```

### Supported Compliance Frameworks

Wazuh includes rules and dashboards for:
- PCI-DSS
- HIPAA
- GDPR
- NIST 800-53
- TSC (SOC 2)
- GPG13

## Detection Rules

### Included Rulesets

This deployment ships with detection rules from two sources:

1. **Project-specific rules** (ID range `800100-800299`) - Custom rules for Linux attack detection, PowerShell monitoring, and threat hunting
2. **[SOCFortress Wazuh-Rules](https://github.com/socfortress/Wazuh-Rules)** - Community-maintained detection rules with MITRE ATT&CK mapping, covering:
   - Windows Sysmon (13 event types, 1000+ rules)
   - Linux auditd (64 rules)
   - Sysmon for Linux (14 rules)
   - Suricata IDS, YARA, and infrastructure health

All rules are deployed to the Manager at `/var/ossec/etc/rules/` and `/var/ossec/etc/decoders/` during the manager role execution. No additional agent configuration is needed for rules to take effect - agents send events, and the manager evaluates them against all loaded rules.

### Rule ID Ranges

| Range | Source | Description |
|-------|--------|-------------|
| `1-99999` | Wazuh built-in | Default rules shipped with Wazuh |
| `100000-199999` | [SOCFortress](https://github.com/socfortress/Wazuh-Rules) | Community detection rules |
| `200000-699999` | [SOCFortress](https://github.com/socfortress/Wazuh-Rules) | Linux, infra, and response rules |
| `800100-800299` | Project-specific | Custom attack detection and PowerShell rules |

### Prerequisites for Full Detection Coverage

- **Windows Sysmon rules**: Requires [Sysmon](https://learn.microsoft.com/en-us/sysinternals/downloads/sysmon) installed on Windows agents with a comprehensive configuration (e.g., [SwiftOnSecurity/sysmon-config](https://github.com/SwiftOnSecurity/sysmon-config))
- **Auditd rules**: Requires auditd configured on Linux agents (enabled by default in this deployment)
- **Suricata rules**: Requires Suricata IDS/IPS forwarding logs to Wazuh
- **YARA rules**: Requires YARA integration configured on agents

## Security Checklist

### Pre-Deployment

- [ ] Secure control node with encryption and access controls
- [ ] Back up `.vault_password` file securely (offline storage recommended)
- [ ] Generate certificates (done automatically by setup.sh)
- [ ] Review `group_vars/all/main.yml` security settings
- [ ] Plan network segmentation

### Post-Deployment

- [ ] Verify all services are running with TLS
- [ ] Confirm deployment user is locked down
- [ ] Test agent enrollment with password
- [ ] Verify dashboard access with correct credentials
- [ ] Check audit logging is active
- [ ] Test backup and restore procedures
- [ ] Back up `.vault_password` file securely

### Ongoing

- [ ] Monitor health check results
- [ ] Review security alerts daily
- [ ] Rotate credentials periodically (`./scripts/manage-vault.sh rotate`)
- [ ] Monitor certificate expiration (`make certs-check`)
- [ ] Keep Wazuh version updated
- [ ] Review and update firewall rules
- [ ] Test disaster recovery procedures
- [ ] Periodically rekey vault password (`./scripts/manage-vault.sh rekey`)
