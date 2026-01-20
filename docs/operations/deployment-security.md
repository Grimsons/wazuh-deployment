# Deployment Security Guide

This document covers security features and best practices specific to this Wazuh Ansible deployment.

## Credential Management

### Auto-Generated Credentials

All passwords are automatically generated during deployment with the following characteristics:
- 22+ characters length
- Mix of uppercase, lowercase, numbers, and symbols
- Compliant with Wazuh's password requirements
- Stored in `credentials/` directory with mode 0600

### Credential Files

| File | Purpose |
|------|---------|
| `credentials/indexer_admin_password.txt` | Dashboard and Indexer admin login |
| `credentials/api_password.txt` | Wazuh API authentication |
| `credentials/agent_enrollment_password.txt` | Agent enrollment authentication |

### Best Practices

1. **Secure storage**: Keep `credentials/` directory on encrypted storage
2. **Access control**: Restrict access to deployment host
3. **Rotation**: Rotate credentials periodically (requires redeployment)
4. **Backup**: Include credentials in secure backups

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

# Manual unlock on single host
ssh wazuh-deploy@HOST 'sudo /usr/local/bin/wazuh-unlock-deploy'
```

### Disabling Lockdown

To disable automatic lockdown:

```yaml
# In group_vars/all.yml
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
- Auto-generated during manager deployment
- Stored in `credentials/agent_enrollment_password.txt`
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

## Security Checklist

### Pre-Deployment

- [ ] Secure control node with encryption and access controls
- [ ] Generate certificates (done automatically by setup.sh)
- [ ] Review `group_vars/all.yml` security settings
- [ ] Plan network segmentation

### Post-Deployment

- [ ] Verify all services are running with TLS
- [ ] Confirm deployment user is locked down
- [ ] Test agent enrollment with password
- [ ] Verify dashboard access with correct credentials
- [ ] Check audit logging is active
- [ ] Test backup and restore procedures

### Ongoing

- [ ] Monitor health check results
- [ ] Review security alerts daily
- [ ] Rotate credentials periodically
- [ ] Keep Wazuh version updated
- [ ] Review and update firewall rules
- [ ] Test disaster recovery procedures
