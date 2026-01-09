# Wazuh Deployment

Automated deployment of Wazuh SIEM/XDR stack using Ansible with interactive setup and client preparation tools.

## Overview

This project provides a streamlined way to deploy Wazuh infrastructure with:

- **Interactive Setup** - Configure your deployment through a guided CLI wizard
- **Client Preparation** - Automated target host preparation with OS detection and optimization
- **Multiple Deployment Modes** - All-in-One (single node) or Distributed (multi-node cluster)
- **Certificate Management** - Automated SSL/TLS certificate generation
- **Cross-Platform Agent Support** - Linux, Windows, and macOS agents

## Components

| Component | Description |
|-----------|-------------|
| **Wazuh Indexer** | Stores and indexes security alerts and events (OpenSearch-based) |
| **Wazuh Manager** | Central component that analyzes data from agents |
| **Wazuh Dashboard** | Web interface for visualization and management |
| **Wazuh Agent** | Collects security data from monitored endpoints |

## Prerequisites

- **Control Node:**
  - Ansible 2.12+
  - Python 3.8+
  - Bash shell

- **Target Hosts:**
  - Ubuntu 20.04+, Debian 10+, RHEL/CentOS 8+, Rocky Linux 8+
  - SSH access (root or sudo user)
  - Minimum 4GB RAM for indexer/manager, 2GB for agents

### Required Ansible Collections

```bash
ansible-galaxy install -r requirements.yml
```

Or manually:

```bash
ansible-galaxy collection install ansible.posix community.general
```

## Quick Start

### 1. Run Interactive Setup

```bash
./setup.sh
```

The wizard will guide you through:
- Wazuh version selection
- Node IP addresses (indexer, manager, dashboard)
- Agent hosts (optional)
- Credentials configuration
- Feature toggles (vulnerability detection, FIM, etc.)

This generates:
- `inventory/hosts.yml` - Ansible inventory
- `group_vars/all.yml` - Configuration variables
- `ansible.cfg` - Ansible settings
- `keys/` - SSH keypair for deployment
- `client-prep/` - Host preparation package

### 2. Prepare Target Hosts

The setup creates a client preparation package that:
- Detects OS (Ubuntu, Debian, RHEL, Rocky, Fedora, etc.)
- Removes unnecessary packages (desktop environments, games, etc.)
- Installs required dependencies
- Creates deployment user with sudo access
- Deploys SSH public key
- Configures firewall rules
- Optimizes system settings

**Option A: Copy and run**
```bash
scp -r client-prep/ root@TARGET:/tmp/
ssh root@TARGET 'bash /tmp/client-prep/install.sh'
```

**Option B: Self-extracting script**
```bash
scp wazuh-client-prep.sh root@TARGET:/tmp/
ssh root@TARGET 'bash /tmp/wazuh-client-prep.sh'
```

**Option C: Deploy to multiple hosts**
```bash
./scripts/deploy-prep.sh 192.168.1.10 192.168.1.11 192.168.1.12
# Or from file
./scripts/deploy-prep.sh -f hosts.txt
```

### 3. Generate Certificates

```bash
./generate-certs.sh
```

### 4. Test Connectivity

```bash
ansible all -m ping
```

### 5. Deploy

**Full stack deployment:**
```bash
ansible-playbook site.yml
```

**Individual components:**
```bash
ansible-playbook playbooks/wazuh-indexer.yml
ansible-playbook playbooks/wazuh-manager.yml
ansible-playbook playbooks/wazuh-dashboard.yml
ansible-playbook playbooks/wazuh-agents.yml
```

**All-in-One (single server):**
```bash
ansible-playbook wazuh-aio.yml
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
│
├── inventory/
│   ├── hosts.yml               # Generated inventory
│   └── hosts.yml.example       # Example inventory
│
├── group_vars/
│   ├── all.yml                 # Generated variables
│   └── all.yml.example         # Example variables
│
├── playbooks/
│   ├── wazuh-indexer.yml       # Indexer deployment
│   ├── wazuh-manager.yml       # Manager deployment
│   ├── wazuh-dashboard.yml     # Dashboard deployment
│   └── wazuh-agents.yml        # Agent deployment
│
├── roles/
│   ├── wazuh-indexer/          # Indexer role
│   ├── wazuh-manager/          # Manager role
│   ├── wazuh-dashboard/        # Dashboard role
│   ├── wazuh-agent/            # Agent role
│   ├── package-urls/           # Package URL configuration
│   └── vars/                   # Shared variables
│
├── scripts/
│   ├── prepare-client.sh       # Client preparation script
│   └── deploy-prep.sh          # Multi-host prep deployment
│
├── client-prep/                # Generated client prep package
├── keys/                       # Generated SSH keys
├── files/certs/               # Generated certificates
│
├── docs/                       # Documentation
├── tools/                      # Utility scripts
│
├── DEPLOYMENT.md              # Detailed deployment guide
├── SECURITY.md                # Security guidelines
└── CHANGELOG.md               # Version history
```

## Configuration

### Key Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `wazuh_version` | Wazuh version to install | 4.9.0 |
| `wazuh_indexer_http_port` | Indexer HTTP port | 9200 |
| `wazuh_manager_api_port` | Manager API port | 55000 |
| `wazuh_dashboard_port` | Dashboard HTTPS port | 443 |
| `wazuh_agent_port` | Agent communication port | 1514 |

### Feature Toggles

| Variable | Description | Default |
|----------|-------------|---------|
| `wazuh_vulnerability_detection_enabled` | Vulnerability detection | true |
| `wazuh_fim_enabled` | File integrity monitoring | true |
| `wazuh_rootkit_detection_enabled` | Rootkit detection | true |
| `wazuh_log_collection_enabled` | Log collection | true |
| `wazuh_active_response_enabled` | Active response | true |
| `wazuh_configure_firewall` | Configure firewall rules | true |

### Inventory Example

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

## Deployment Modes

### All-in-One (AIO)

Single server with all components:

```bash
ansible-playbook wazuh-aio.yml -e "target_host=192.168.1.10"
```

### Distributed Cluster

Multi-node deployment with:
- 3 Indexer nodes (cluster)
- 2 Manager nodes (master + worker)
- 1 Dashboard node

```bash
ansible-playbook wazuh-distributed.yml
```

### Selective Deployment

Use tags for specific components:

```bash
ansible-playbook site.yml --tags indexer
ansible-playbook site.yml --tags manager
ansible-playbook site.yml --tags dashboard
ansible-playbook site.yml --tags agent
```

## Post-Deployment

### Access Dashboard

1. Open `https://<dashboard-ip>:443`
2. Login with configured credentials
3. **Change default passwords immediately**

### Verify Services

```bash
# Indexer
systemctl status wazuh-indexer
curl -k -u admin:admin https://localhost:9200/_cluster/health?pretty

# Manager
systemctl status wazuh-manager
/var/ossec/bin/cluster_control -l

# Dashboard
systemctl status wazuh-dashboard

# Agent
systemctl status wazuh-agent
/var/ossec/bin/agent_control -l
```

### View Logs

```bash
# Indexer
tail -f /var/log/wazuh-indexer/wazuh-indexer.log

# Manager
tail -f /var/ossec/logs/ossec.log

# Dashboard
tail -f /var/log/wazuh-dashboard/opensearch-dashboards.log

# Agent
tail -f /var/ossec/logs/ossec.log
```

## Troubleshooting

See [DEPLOYMENT.md](DEPLOYMENT.md) for detailed troubleshooting guides.

Common issues:
- **Connection refused**: Check firewall rules and service status
- **Certificate errors**: Regenerate certificates with `./generate-certs.sh`
- **Agent not connecting**: Verify manager address and port 1514 accessibility

## Security

See [SECURITY.md](SECURITY.md) for security guidelines and best practices.

Key recommendations:
- Change all default passwords immediately
- Use strong, unique passwords for each component
- Restrict network access to management ports
- Consider external CA for production deployments
- Enable audit logging

## License

Based on [wazuh/wazuh-ansible](https://github.com/wazuh/wazuh-ansible).

WAZUH - Copyright (C) 2016, Wazuh Inc. (License GPLv2)

See [LICENSE](LICENSE) for full license text.

## Links

- [Wazuh Documentation](https://documentation.wazuh.com)
- [Wazuh Ansible Docs](https://documentation.wazuh.com/current/deploying-with-ansible/index.html)
- [Wazuh Website](https://wazuh.com)
- [Wazuh GitHub](https://github.com/wazuh)
