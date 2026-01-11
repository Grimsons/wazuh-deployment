# Wazuh Disaster Recovery Guide

This document outlines the disaster recovery (DR) procedures for Wazuh deployments managed by this Ansible project.

## Table of Contents

1. [Overview](#overview)
2. [Recovery Objectives](#recovery-objectives)
3. [Backup Strategy](#backup-strategy)
4. [Recovery Procedures](#recovery-procedures)
5. [DR Testing](#dr-testing)
6. [Runbooks](#runbooks)
7. [Contact Information](#contact-information)

---

## Overview

### Scope

This DR plan covers:
- **Wazuh Indexer** - Alert storage and indexing (OpenSearch-based)
- **Wazuh Manager** - Central analysis engine and agent management
- **Wazuh Dashboard** - Web interface for visualization
- **Configuration Data** - Rules, decoders, agent groups, certificates

### Not Covered

- Agent reinstallation (agents can re-enroll automatically)
- Historical alert data beyond backup retention (use index snapshots for long-term)
- External integrations (Slack, email, etc. - reconfigure manually)

---

## Recovery Objectives

### RTO (Recovery Time Objective)

| Scenario | Target RTO | Notes |
|----------|------------|-------|
| Single component failure | 15 minutes | Restore from backup |
| Complete cluster failure | 45 minutes | Full restore procedure |
| Data center failure | 2 hours | Deploy to DR site |

### RPO (Recovery Point Objective)

| Data Type | Target RPO | Backup Frequency |
|-----------|------------|------------------|
| Configuration | 24 hours | Daily backup |
| Alert data | 1 hour | Continuous to Indexer |
| Index snapshots | 24 hours | Daily snapshot |

---

## Backup Strategy

### Automated Backups

```bash
# Schedule daily backup via cron
0 2 * * * cd /path/to/wazuh-deployment && ansible-playbook playbooks/backup.yml
```

### What Gets Backed Up

#### Indexer
- `/etc/wazuh-indexer/opensearch.yml` - Cluster configuration
- `/etc/wazuh-indexer/opensearch-security/` - Security settings
- `/etc/wazuh-indexer/jvm.options` - JVM configuration
- `/etc/wazuh-indexer/certs/` - SSL certificates

#### Manager
- `/var/ossec/etc/ossec.conf` - Main configuration
- `/var/ossec/etc/rules/` - Custom detection rules
- `/var/ossec/etc/decoders/` - Custom log decoders
- `/var/ossec/etc/lists/` - CDB lists (threat intel)
- `/var/ossec/etc/shared/` - Agent group configurations
- `/var/ossec/etc/client.keys` - Agent registration keys
- `/var/ossec/api/configuration/` - API settings

#### Dashboard
- `/etc/wazuh-dashboard/opensearch_dashboards.yml` - Dashboard config
- `/usr/share/wazuh-dashboard/data/wazuh/config/wazuh.yml` - Wazuh plugin config
- `/etc/wazuh-dashboard/certs/` - SSL certificates

#### Credentials
- `./credentials/indexer_admin_password.txt`
- `./credentials/api_password.txt`
- `./credentials/manager_cluster_key.txt` (if clustered)

### Backup Locations

```
./backups/
├── 20240115_020000/           # Timestamp-based directories
│   ├── indexer/
│   │   ├── opensearch.yml
│   │   ├── opensearch-security/
│   │   └── certs/
│   ├── manager/
│   │   ├── ossec.conf
│   │   ├── rules/
│   │   ├── decoders/
│   │   └── client.keys
│   ├── dashboard/
│   │   ├── opensearch_dashboards.yml
│   │   └── certs/
│   └── credentials/
├── 20240116_020000/
└── checksums.sha256
```

### Backup Retention

| Environment | Retention | Storage |
|-------------|-----------|---------|
| Production | 30 days | Off-site + local |
| Staging | 7 days | Local only |
| Development | 3 days | Local only |

---

## Recovery Procedures

### Procedure 1: Single Component Recovery

#### Indexer Node Recovery

```bash
# 1. Stop the failed indexer
ssh indexer-1 "sudo systemctl stop wazuh-indexer"

# 2. Restore configuration
ansible-playbook playbooks/restore.yml \
  -e "backup_timestamp=20240115_020000" \
  -e "restore_indexer=true" \
  --limit indexer-1

# 3. Start and verify
ssh indexer-1 "sudo systemctl start wazuh-indexer"
ansible-playbook playbooks/health-check.yml --limit indexer-1
```

#### Manager Node Recovery

```bash
# 1. Stop the failed manager
ssh manager-1 "sudo systemctl stop wazuh-manager"

# 2. Restore configuration
ansible-playbook playbooks/restore.yml \
  -e "backup_timestamp=20240115_020000" \
  -e "restore_manager=true" \
  --limit manager-1

# 3. Start and verify
ssh manager-1 "sudo systemctl start wazuh-manager"
ansible-playbook playbooks/health-check.yml --limit manager-1
```

### Procedure 2: Complete Cluster Recovery

```bash
# 1. Validate backup integrity
ansible-playbook playbooks/dr-validate.yml -e "backup_timestamp=20240115_020000"

# 2. Run pre-flight checks on new infrastructure
ansible-playbook playbooks/pre-flight-checks.yml

# 3. Deploy fresh Wazuh installation
ansible-playbook site.yml

# 4. Stop all services for restore
ansible all -m systemd -a "name=wazuh-indexer state=stopped" --limit wazuh_indexers
ansible all -m systemd -a "name=wazuh-manager state=stopped" --limit wazuh_managers
ansible all -m systemd -a "name=wazuh-dashboard state=stopped" --limit wazuh_dashboards

# 5. Restore from backup
ansible-playbook playbooks/restore.yml -e "backup_timestamp=20240115_020000"

# 6. Start services
ansible all -m systemd -a "name=wazuh-indexer state=started" --limit wazuh_indexers
ansible all -m systemd -a "name=wazuh-manager state=started" --limit wazuh_managers
ansible all -m systemd -a "name=wazuh-dashboard state=started" --limit wazuh_dashboards

# 7. Verify recovery
ansible-playbook playbooks/health-check.yml
```

### Procedure 3: Index Data Recovery

For recovering historical alert data (requires index snapshots):

```bash
# 1. Register snapshot repository (if not exists)
curl -X PUT "https://indexer:9200/_snapshot/backup_repo" \
  -H "Content-Type: application/json" \
  -u admin:password \
  -d '{
    "type": "fs",
    "settings": {
      "location": "/mnt/snapshots"
    }
  }'

# 2. List available snapshots
curl -X GET "https://indexer:9200/_snapshot/backup_repo/_all" -u admin:password

# 3. Restore specific indices
curl -X POST "https://indexer:9200/_snapshot/backup_repo/snapshot_20240115/_restore" \
  -H "Content-Type: application/json" \
  -u admin:password \
  -d '{
    "indices": "wazuh-alerts-*",
    "ignore_unavailable": true,
    "include_global_state": false
  }'
```

---

## DR Testing

### Monthly DR Test Procedure

```bash
# 1. Validate current backups
ansible-playbook playbooks/dr-validate.yml

# 2. Perform test restore (non-destructive)
ansible-playbook playbooks/dr-validate.yml -e "dr_test_mode=true"

# 3. Document results
# Report generated automatically in docs/dr-reports/
```

### Quarterly Full DR Test

1. **Preparation**
   - Notify stakeholders
   - Prepare DR environment (separate from production)
   - Export latest backup to DR site

2. **Execution**
   ```bash
   # Deploy to DR environment
   cd /path/to/wazuh-deployment
   cp inventory/hosts.yml inventory/hosts-dr.yml
   # Edit hosts-dr.yml with DR site IPs

   ansible-playbook site.yml -i inventory/hosts-dr.yml
   ansible-playbook playbooks/restore.yml -i inventory/hosts-dr.yml \
     -e "backup_timestamp=LATEST"
   ```

3. **Validation**
   - [ ] All services running
   - [ ] Dashboard accessible
   - [ ] Agents can connect (test agent)
   - [ ] Alerts flowing to Indexer
   - [ ] Custom rules loaded
   - [ ] API responding

4. **Documentation**
   - Record actual RTO achieved
   - Document any issues encountered
   - Update procedures if needed

---

## Runbooks

### Runbook 1: Indexer Cluster Red Status

**Symptoms:** Cluster health is RED, queries failing

**Steps:**
1. Check cluster status:
   ```bash
   curl -X GET "https://indexer:9200/_cluster/health?pretty" -u admin:password
   ```

2. Identify unassigned shards:
   ```bash
   curl -X GET "https://indexer:9200/_cat/shards?v&h=index,shard,prirep,state,unassigned.reason" -u admin:password
   ```

3. If node failure, restore from backup:
   ```bash
   ansible-playbook playbooks/restore.yml -e "restore_indexer=true" --limit failed-node
   ```

4. Force shard allocation (last resort):
   ```bash
   curl -X POST "https://indexer:9200/_cluster/reroute?retry_failed=true" -u admin:password
   ```

### Runbook 2: Manager Not Receiving Alerts

**Symptoms:** No new alerts, agents showing disconnected

**Steps:**
1. Check manager status:
   ```bash
   /var/ossec/bin/wazuh-control status
   ```

2. Check agent connections:
   ```bash
   /var/ossec/bin/agent_control -l
   ```

3. Review logs:
   ```bash
   tail -100 /var/ossec/logs/ossec.log
   ```

4. If cluster issue:
   ```bash
   /var/ossec/bin/cluster_control -l
   ```

5. Restart if needed:
   ```bash
   /var/ossec/bin/wazuh-control restart
   ```

### Runbook 3: Certificate Expiry

**Symptoms:** SSL errors, services failing to start

**Steps:**
1. Check certificate expiry:
   ```bash
   openssl x509 -enddate -noout -in /etc/wazuh-indexer/certs/indexer.pem
   ```

2. Generate new certificates:
   ```bash
   ./generate-certs.sh
   ```

3. Deploy new certificates:
   ```bash
   ansible-playbook playbooks/wazuh-indexer.yml --tags certificates
   ansible-playbook playbooks/wazuh-manager.yml --tags certificates
   ansible-playbook playbooks/wazuh-dashboard.yml --tags certificates
   ```

4. Restart services:
   ```bash
   ansible all -m systemd -a "name=wazuh-indexer state=restarted" --limit wazuh_indexers
   ansible all -m systemd -a "name=wazuh-manager state=restarted" --limit wazuh_managers
   ansible all -m systemd -a "name=wazuh-dashboard state=restarted" --limit wazuh_dashboards
   ```

---

## Checklists

### Pre-Recovery Checklist

- [ ] Identify the failure scope (single node, cluster, data center)
- [ ] Determine required backup timestamp
- [ ] Validate backup integrity: `ansible-playbook playbooks/dr-validate.yml`
- [ ] Notify stakeholders of recovery initiation
- [ ] Prepare recovery environment (if different from failed)
- [ ] Document start time for RTO measurement

### Post-Recovery Checklist

- [ ] All services running: `ansible-playbook playbooks/health-check.yml`
- [ ] Dashboard accessible and functional
- [ ] API responding: `curl https://manager:55000/`
- [ ] Agents reconnecting (may take several minutes)
- [ ] New alerts being generated and stored
- [ ] Custom rules and decoders loaded
- [ ] Integrations functional (email, Slack, etc.)
- [ ] Document actual RTO achieved
- [ ] Create incident report

---

## Contact Information

### Primary Contacts

| Role | Name | Phone | Email |
|------|------|-------|-------|
| Security Lead | [Name] | [Phone] | [Email] |
| Infrastructure | [Name] | [Phone] | [Email] |
| On-Call | Rotation | [Phone] | [Email] |

### Escalation Path

1. **Level 1:** On-call engineer (15 min response)
2. **Level 2:** Security team lead (30 min response)
3. **Level 3:** Infrastructure manager (1 hour response)

### External Support

- **Wazuh Support:** https://wazuh.com/support/
- **Community Slack:** https://wazuh.com/community/
- **GitHub Issues:** https://github.com/wazuh/wazuh/issues

---

## Revision History

| Date | Version | Author | Changes |
|------|---------|--------|---------|
| YYYY-MM-DD | 1.0 | [Author] | Initial DR plan |

---

## Appendix A: Command Reference

```bash
# Backup commands
ansible-playbook playbooks/backup.yml                    # Full backup
ansible-playbook playbooks/backup.yml -e "include_indices=true"  # Include index snapshot

# Restore commands
ansible-playbook playbooks/restore.yml -e "backup_timestamp=20240115_020000"
ansible-playbook playbooks/restore.yml -e "restore_indexer=true"   # Indexer only
ansible-playbook playbooks/restore.yml -e "restore_manager=true"   # Manager only

# Validation commands
ansible-playbook playbooks/dr-validate.yml               # Validate latest backup
ansible-playbook playbooks/dr-validate.yml -e "dr_test_mode=true"  # Full test
ansible-playbook playbooks/health-check.yml              # Check all services
ansible-playbook playbooks/pre-flight-checks.yml         # Pre-deployment checks

# Health check commands
curl -X GET "https://indexer:9200/_cluster/health?pretty" -u admin:password
/var/ossec/bin/wazuh-control status
/var/ossec/bin/cluster_control -l   # For clustered managers
```

## Appendix B: Recovery Time Benchmarks

Based on testing with typical production data:

| Backup Size | Restore Time | Notes |
|-------------|--------------|-------|
| < 1 GB | 5-10 min | Config only |
| 1-10 GB | 15-30 min | Config + small indices |
| 10-100 GB | 1-2 hours | Large index restore |
| > 100 GB | 2-4 hours | Full data recovery |

*Note: Times assume local backup storage. Network transfer adds additional time.*
