# Wazuh Upgrade Guide

This document describes how to upgrade Wazuh deployments using the rolling upgrade playbook.

## Overview

The upgrade playbook (`playbooks/upgrade.yml`) performs rolling upgrades with:
- Zero-downtime for clustered deployments
- Automatic pre-upgrade backups
- Component-by-component upgrades
- Post-upgrade health validation

## Prerequisites

Before upgrading:

1. **Run pre-flight checks**
   ```bash
   ansible-playbook playbooks/pre-flight-checks.yml
   ```

2. **Review release notes** for the target version at [Wazuh Release Notes](https://documentation.wazuh.com/current/release-notes/)

3. **Verify backup integrity**
   ```bash
   ansible-playbook playbooks/dr-validate.yml
   ```

4. **Notify stakeholders** of planned maintenance window

## Upgrade Procedure

### Standard Upgrade

```bash
# Upgrade to a specific version
ansible-playbook playbooks/upgrade.yml -e "target_version=4.12.0"

# Or use the make shortcut:
make upgrade
```

### Component-Specific Upgrades

```bash
# Upgrade only indexers
ansible-playbook playbooks/upgrade.yml -e "target_version=4.12.0" --tags indexer

# Upgrade only managers
ansible-playbook playbooks/upgrade.yml -e "target_version=4.12.0" --tags manager

# Upgrade only dashboard
ansible-playbook playbooks/upgrade.yml -e "target_version=4.12.0" --tags dashboard
```

### Agent Upgrades

```bash
# Upgrade all agents
ansible-playbook playbooks/upgrade.yml -e "target_version=4.12.0" --tags agents

# Upgrade specific agent group
ansible-playbook playbooks/upgrade.yml -e "target_version=4.12.0" --limit agent_group_web
```

## Upgrade Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `target_version` | Target Wazuh version | Required |
| `create_backup` | Create backup before upgrade | `true` |
| `rolling_upgrade` | Use rolling upgrade for clusters | `true` |
| `agent_batch_size` | Agents to upgrade per batch | `10` |
| `health_check_retries` | Health check retry attempts | `30` |
| `health_check_delay` | Delay between retries (seconds) | `10` |

## Upgrade Order

The playbook follows this order to minimize disruption:

1. **Pre-upgrade backup** (all components)
2. **Indexer cluster** (one node at a time, with shard allocation paused)
3. **Manager cluster** (workers first, then master)
4. **Dashboard**
5. **Agents** (in batches)
6. **Post-upgrade validation**

## Rolling Upgrade Details

### Indexer Cluster

1. Disable shard allocation
2. Stop indexer node
3. Upgrade packages
4. Start indexer node
5. Wait for node to join cluster
6. Re-enable shard allocation
7. Wait for cluster to be green
8. Proceed to next node

### Manager Cluster

1. Upgrade worker nodes first
2. Verify worker health
3. Upgrade master node last
4. Verify cluster synchronization

## Rollback Procedure

If upgrade fails:

1. **Stop the upgrade process** (Ctrl+C if running)

2. **Check the failure point**
   ```bash
   ansible-playbook playbooks/health-check.yml
   ```

3. **Restore from backup** (if needed)
   ```bash
   ansible-playbook playbooks/restore.yml -e "restore_from=YYYYMMDD_HHMMSS"
   ```

4. **Restart services**
   ```bash
   ansible all -m systemd -a "name=wazuh-indexer state=restarted" --limit wazuh_indexers
   ansible all -m systemd -a "name=wazuh-manager state=restarted" --limit wazuh_managers
   ansible all -m systemd -a "name=wazuh-dashboard state=restarted" --limit wazuh_dashboards
   ```

## Post-Upgrade Verification

1. **Check cluster health**
   ```bash
   ansible-playbook playbooks/health-check.yml
   ```

2. **Verify version**
   ```bash
   curl -k -u admin:<your-password> https://<indexer-ip>:9200
   /var/ossec/bin/wazuh-control info
   ```

3. **Test agent connectivity**
   ```bash
   /var/ossec/bin/agent_control -l
   ```

4. **Verify dashboard access**
   - Navigate to `https://<dashboard-ip>`
   - Check all widgets load correctly

## Troubleshooting

### Indexer Node Won't Join Cluster

```bash
# Check cluster state
curl -k -u admin:<your-password> https://<indexer-ip>:9200/_cluster/health?pretty

# Check node logs
tail -100 /var/log/wazuh-indexer/wazuh-indexer.log
```

### Manager Cluster Sync Issues

```bash
# Check cluster status
/var/ossec/bin/cluster_control -l

# Force sync
/var/ossec/bin/cluster_control -a
```

### Agent Connection Failures After Upgrade

```bash
# Check agent status
/var/ossec/bin/agent_control -l

# Restart agent
systemctl restart wazuh-agent
```

## Version Compatibility Matrix

| Wazuh Version | Indexer | Filebeat | Dashboard |
|---------------|---------|----------|-----------|
| 4.9.x | 2.11.x | 7.10.2 | 2.11.x |
| 4.10.x | 2.13.x | 7.10.2 | 2.13.x |
| 4.11.x | 2.14.x | 7.10.2 | 2.14.x |
| 4.12.x | 2.16.x | 7.10.2 | 2.16.x |
| 4.13.x | 2.17.x | 7.10.2 | 2.17.x |
| 4.14.x | 2.18.x | 7.10.2 | 2.18.x |

Always check [official documentation](https://documentation.wazuh.com/) for the latest compatibility information.
