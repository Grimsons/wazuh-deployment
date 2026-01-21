# Wazuh Ansible Deployment Guide

Automated deployment of Wazuh SIEM/XDR stack using Ansible with interactive configuration.

## Components

- **Wazuh Indexer**: Stores and indexes security alerts and events (OpenSearch-based)
- **Wazuh Manager**: Central component that analyzes data from agents
- **Wazuh Dashboard**: Web interface for visualization and management
- **Wazuh Agent**: Collects security data from monitored endpoints
- **Filebeat**: Forwards alerts from Manager to Indexer

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
ansible-galaxy collection install ansible.posix
ansible-galaxy collection install community.general
```

## Quick Start

### 1. Run Interactive Setup

```bash
./setup.sh
```

The wizard guides you through:
- Wazuh version selection (default: 4.14.2)
- Node IP addresses (indexer, manager, dashboard)
- Agent hosts (optional)
- Security features (vulnerability detection, FIM, SCA, etc.)
- Email alerts configuration
- Syslog output configuration
- Integrations (Slack, VirusTotal)
- **Automatic certificate generation**

Generated files:
- `inventory/hosts.yml` - Ansible inventory
- `group_vars/all/main.yml` - Configuration variables
- `group_vars/all/vault.yml` - Encrypted credentials (Ansible Vault)
- `.vault_password` - Vault encryption key (keep secure!)
- `ansible.cfg` - Ansible settings
- `keys/` - SSH keypair for deployment
- `files/certs/` - SSL/TLS certificates
- `client-prep/` - Host preparation package

### 2. Prepare Target Machines

The setup script creates a client preparation package that:
- Detects the OS (Ubuntu, Debian, RHEL, Rocky, Fedora, SUSE, Arch Linux)
- Removes unnecessary packages (desktop environments, office suites, games)
- Installs required packages (Python, SSH, etc.)
- Creates an Ansible deployment user with sudo access
- Deploys the SSH public key for passwordless authentication
- Configures firewall rules for Wazuh
- Optimizes system settings

**Method A: Copy folder to target machine**
```bash
scp -r client-prep/ root@TARGET_HOST:/tmp/
ssh root@TARGET_HOST 'cd /tmp/client-prep && sudo ./install.sh'
```

**Method B: Use self-extracting script**
```bash
scp wazuh-client-prep.sh root@TARGET_HOST:/tmp/
ssh root@TARGET_HOST 'sudo bash /tmp/wazuh-client-prep.sh'
```

**Method C: Deploy to multiple hosts**
```bash
# Using the deployment script
./scripts/deploy-prep.sh 192.168.1.10 192.168.1.11 192.168.1.12

# Or from a hosts file
./scripts/deploy-prep.sh -f hosts.txt
```

**Method D: Minimal mode (skip package removal)**
```bash
ssh root@TARGET_HOST 'sudo bash /tmp/wazuh-client-prep.sh --minimal'
```

### 3. Test Connectivity

```bash
ansible all -m ping
```

### 4. Deploy Wazuh Stack

```bash
# Deploy everything
ansible-playbook site.yml

# Or deploy components individually
ansible-playbook playbooks/wazuh-indexer.yml
ansible-playbook playbooks/wazuh-manager.yml
ansible-playbook playbooks/wazuh-dashboard.yml
ansible-playbook playbooks/wazuh-agents.yml
```

### 5. Access the Dashboard

After setup completes, credentials are displayed on screen and stored encrypted in Ansible Vault. To view them later:

```bash
./scripts/manage-vault.sh view
```

Access the dashboard at `https://<dashboard-ip>:443` using the `admin` user.

## Post-Deployment Security

### Deployment User Lockdown

After deployment completes, the deployment user (`wazuh-deploy`) is **automatically locked down** on all hosts for security. This restricts sudo access to only:
- The unlock script
- Ansible fact gathering
- Wazuh status checks

### Running Future Deployments

Before running any new deployment or update:

```bash
# Step 1: Unlock deployment user on all hosts
ansible-playbook unlock-deploy-user.yml

# Step 2: Run your deployment
ansible-playbook site.yml
# User is automatically re-locked at completion
```

### Disabling Lockdown

To disable automatic lockdown, set in `group_vars/all.yml`:
```yaml
wazuh_lockdown_deploy_user: false
```

## Configuration

### Inventory (inventory/hosts.yml)

```yaml
all:
  children:
    wazuh_indexers:
      hosts:
        192.168.1.10:
          indexer_node_name: indexer-1
          indexer_cluster_initial_master: true
    wazuh_managers:
      hosts:
        192.168.1.20:
          manager_node_name: manager-1
          manager_node_type: master
    wazuh_dashboards:
      hosts:
        192.168.1.30:
    wazuh_agents:
      hosts:
        192.168.1.100:
        192.168.1.101:
```

### Key Variables (group_vars/all/main.yml)

| Variable | Description | Default |
|----------|-------------|---------|
| `wazuh_version` | Wazuh version to install | 4.14.2 |
| `wazuh_indexer_http_port` | Indexer HTTP port | 9200 |
| `wazuh_manager_api_port` | Manager API port | 55000 |
| `wazuh_dashboard_port` | Dashboard HTTPS port | 443 |
| `wazuh_manager_cluster_enabled` | Enable manager cluster | false |
| `wazuh_authd_use_password` | Require password for agent enrollment | true |
| `wazuh_lockdown_deploy_user` | Lock down deploy user after completion | true |

### Feature Toggles

| Variable | Description | Default |
|----------|-------------|---------|
| `wazuh_vulnerability_detection_enabled` | Vulnerability detection | true |
| `wazuh_fim_enabled` | File integrity monitoring | true |
| `wazuh_rootkit_detection_enabled` | Rootkit detection | true |
| `wazuh_sca_enabled` | Security Configuration Assessment | true |
| `wazuh_syscollector_enabled` | System inventory collection | true |
| `wazuh_log_collection_enabled` | Log collection | true |
| `wazuh_active_response_enabled` | Active response | true |

### Integrations

| Variable | Description | Default |
|----------|-------------|---------|
| `wazuh_email_notification_enabled` | Email alerts | false |
| `wazuh_syslog_output_enabled` | Syslog forwarding | false |
| `wazuh_docker_listener_enabled` | Docker monitoring | false |
| `wazuh_office365_enabled` | Office 365 audit logs | false |
| `wazuh_github_enabled` | GitHub audit logs | false |
| `wazuh_aws_enabled` | AWS CloudTrail/GuardDuty | false |
| `wazuh_azure_enabled` | Azure Log Analytics | false |
| `wazuh_gcp_enabled` | GCP Pub/Sub | false |

## Multi-Node Deployment

### Indexer Cluster

For high availability, deploy multiple indexer nodes:

```yaml
wazuh_indexer_nodes:
  - name: indexer-1
    ip: 192.168.1.10
  - name: indexer-2
    ip: 192.168.1.11
  - name: indexer-3
    ip: 192.168.1.12
```

### Manager Cluster

For manager clustering, enable and configure:

```yaml
wazuh_manager_cluster_enabled: true
wazuh_manager_cluster_name: "wazuh-cluster"
wazuh_manager_cluster_key: "your-32-character-cluster-key!!"

wazuh_manager_nodes:
  - name: manager-1
    ip: 192.168.1.20
  - name: manager-2
    ip: 192.168.1.21
```

## Tags

Use tags for selective deployment:

```bash
# Deploy only indexers
ansible-playbook site.yml --tags indexer

# Deploy only managers
ansible-playbook site.yml --tags manager

# Deploy only dashboard
ansible-playbook site.yml --tags dashboard

# Deploy only agents
ansible-playbook site.yml --tags agent

# Skip lockdown
ansible-playbook site.yml --skip-tags lockdown
```

## Troubleshooting

### Check Service Status

```bash
# On indexer
systemctl status wazuh-indexer

# On manager
systemctl status wazuh-manager
systemctl status filebeat

# On dashboard
systemctl status wazuh-dashboard

# On agent
systemctl status wazuh-agent
```

### View Logs

```bash
# Indexer logs
tail -f /var/log/wazuh-indexer/wazuh-indexer.log

# Manager logs
tail -f /var/ossec/logs/ossec.log

# Dashboard logs
tail -f /var/log/wazuh-dashboard/opensearch-dashboards.log

# Filebeat logs
tail -f /var/log/filebeat/filebeat
```

### API Health Check

```bash
# View credentials (run ./scripts/manage-vault.sh view to get passwords)

# Indexer health
curl -k -u admin:PASSWORD https://localhost:9200/_cluster/health?pretty

# Manager API
curl -k -u wazuh:PASSWORD https://localhost:55000/
```

### Agent Not Connecting

1. Verify manager IP and port 1514 accessibility
2. Check enrollment password matches on both sides
3. Verify `/var/ossec/etc/authd.pass` exists on agent
4. Check `/var/ossec/logs/ossec.log` on agent for errors

### MITRE ATT&CK Fields Not Working

If MITRE technique aggregations fail in the dashboard:
1. Verify Filebeat is running and forwarding alerts
2. New indices (created after deployment) will have correct mappings
3. For existing indices, reindex may be required

## Security Considerations

1. Back up `.vault_password` securely - required to decrypt credentials
2. Use external CA certificates for production environments
3. Restrict network access to management ports
4. Enable firewall rules (`wazuh_configure_firewall: true`)
5. Keep deployment user locked down between deployments
6. Rotate credentials regularly (`./scripts/manage-vault.sh rotate`)
7. Enable audit logging for compliance
