# Troubleshooting Guide

This guide covers common issues encountered during Wazuh deployment and operation, along with their solutions.

## Quick Diagnostics

### Health Check Commands

```bash
# Quick status check
./scripts/status.sh
make status

# Run automated health check
ansible-playbook playbooks/health-check.yml
make health

# Check all services status
ansible all -m shell -a "systemctl status wazuh-* --no-pager" --become

# Quick cluster health
curl -k -u admin:<your-password> https://<indexer-ip>:9200/_cluster/health?pretty
```

### Log Locations

| Component | Log Path |
|-----------|----------|
| Wazuh Indexer | `/var/log/wazuh-indexer/wazuh-indexer.log` |
| Wazuh Manager | `/var/ossec/logs/ossec.log` |
| Wazuh Dashboard | `/var/log/wazuh-dashboard/opensearch-dashboards.log` |
| Filebeat | `/var/log/filebeat/filebeat` |
| Wazuh Agent | `/var/ossec/logs/ossec.log` |

---

## Deployment Issues

### Ansible Connection Failures

**Symptoms:**
- `UNREACHABLE! => {"changed": false, "msg": "Failed to connect to the host via ssh"}`
- Timeout errors during playbook execution

**Solutions:**

1. **Verify SSH connectivity:**
   ```bash
   ssh -i keys/wazuh_ansible_key wazuh-deploy@<target-ip>
   ```

2. **Check SSH key permissions:**
   ```bash
   chmod 600 keys/wazuh_ansible_key
   chmod 700 keys/
   ```

3. **Verify target host preparation:**
   ```bash
   # Re-run client preparation
   scp -r client-prep/ root@<target-ip>:/tmp/
   ssh root@<target-ip> 'bash /tmp/client-prep/install.sh'
   ```

4. **Check firewall rules:**
   ```bash
   # On target host
   sudo ufw status
   sudo firewall-cmd --list-all
   ```

### Certificate Generation Failures

**Symptoms:**
- `Certificate files not found`
- `SSL handshake failed`
- OpenSSL errors during setup

**Solutions:**

1. **Regenerate certificates:**
   ```bash
   ./generate-certs.sh --force
   ```

2. **Verify certificate files exist:**
   ```bash
   ls -la files/certs/
   # Should contain: root-ca.pem, admin.pem, admin-key.pem, and node certificates
   ```

3. **Check certificate validity:**
   ```bash
   openssl x509 -in files/certs/root-ca.pem -text -noout | grep -A2 "Validity"
   ```

4. **For external CA issues:**
   ```bash
   # Verify certificate chain
   openssl verify -CAfile files/certs/root-ca.pem files/certs/indexer.pem
   ```

### Vault Password Issues

**Symptoms:**
- `Decryption failed`
- `Vault password file not found`

**Solutions:**

1. **Check vault password file:**
   ```bash
   ls -la .vault_password
   # Should be mode 0600
   ```

2. **Re-initialize vault:**
   ```bash
   ./scripts/manage-vault.sh init
   ```

3. **View encrypted credentials:**
   ```bash
   ./scripts/manage-vault.sh view
   ```

---

## Wazuh Indexer Issues

### Indexer Won't Start

**Symptoms:**
- Service fails to start
- `systemctl status wazuh-indexer` shows failed

**Solutions:**

1. **Check Java heap size:**
   ```bash
   # Edit /etc/wazuh-indexer/jvm.options
   # Recommended: 50% of RAM, min 1GB, max 32GB
   # Default "auto" calculates this at deployment
   # Example for 8GB RAM system:
   -Xms4g
   -Xmx4g
   ```

2. **Check disk space:**
   ```bash
   df -h /var/lib/wazuh-indexer
   # Needs at least 10GB free
   ```

3. **Check file permissions:**
   ```bash
   sudo chown -R wazuh-indexer:wazuh-indexer /var/lib/wazuh-indexer
   sudo chown -R wazuh-indexer:wazuh-indexer /etc/wazuh-indexer
   ```

4. **Check logs for specific error:**
   ```bash
   sudo journalctl -u wazuh-indexer -n 100 --no-pager
   sudo tail -100 /var/log/wazuh-indexer/wazuh-indexer.log
   ```

### Cluster Health Yellow/Red

**Symptoms:**
- `curl ... /_cluster/health` returns yellow or red status
- Unassigned shards

**Solutions:**

1. **Check cluster status:**
   ```bash
   curl -k -u admin:<your-password> https://localhost:9200/_cluster/health?pretty
   curl -k -u admin:<your-password> https://localhost:9200/_cat/shards?v | grep -i unassigned
   ```

2. **For single-node clusters (yellow is normal):**
   ```bash
   # Set replicas to 0 for single-node
   curl -k -u admin:<your-password> -X PUT "https://localhost:9200/_settings" \
     -H 'Content-Type: application/json' \
     -d '{"index": {"number_of_replicas": 0}}'
   ```

3. **Force shard allocation:**
   ```bash
   curl -k -u admin:<your-password> -X POST "https://localhost:9200/_cluster/reroute?retry_failed=true"
   ```

### Authentication Failed (401 Errors)

**Symptoms:**
- Dashboard login fails
- API calls return 401
- `Invalid credentials` errors

**Solutions:**

1. **Verify password from vault:**
   ```bash
   ./scripts/manage-vault.sh view
   ```

2. **Re-apply security configuration:**
   ```bash
   sudo /usr/share/wazuh-indexer/bin/indexer-security-init.sh
   ```

3. **If password was changed, update internal_users.yml:**
   ```bash
   # Hash new password
   sudo /usr/share/wazuh-indexer/plugins/opensearch-security/tools/hash.sh -p "<new-password>"

   # Update /etc/wazuh-indexer/opensearch-security/internal_users.yml with hash

   # Re-apply security config
   sudo /usr/share/wazuh-indexer/plugins/opensearch-security/tools/securityadmin.sh \
     -cd /etc/wazuh-indexer/opensearch-security \
     -cacert /etc/wazuh-indexer/certs/root-ca.pem \
     -cert /etc/wazuh-indexer/certs/admin.pem \
     -key /etc/wazuh-indexer/certs/admin-key.pem \
     -h 127.0.0.1 -p 9200 -icl -nhnv
   ```

---

## Wazuh Manager Issues

### Manager Won't Start

**Symptoms:**
- Service fails to start
- `wazuh-control status` shows services down

**Solutions:**

1. **Check configuration syntax:**
   ```bash
   sudo /var/ossec/bin/wazuh-control -t
   ```

2. **Check logs:**
   ```bash
   sudo tail -100 /var/ossec/logs/ossec.log
   ```

3. **Common config errors:**
   - Invalid XML in ossec.conf
   - Missing closing tags
   - Invalid IP addresses in cluster config

4. **Reset to default config:**
   ```bash
   sudo cp /var/ossec/etc/ossec.conf.rpmnew /var/ossec/etc/ossec.conf
   # Then re-run playbook
   ansible-playbook playbooks/wazuh-manager.yml
   ```

### Agent Enrollment Failures

**Symptoms:**
- Agents can't register
- `Invalid password` errors
- Connection refused on port 1515

**Solutions:**

1. **Verify authd is running:**
   ```bash
   sudo /var/ossec/bin/wazuh-control status | grep authd
   ```

2. **Check enrollment password:**
   ```bash
   # On the manager
   sudo cat /var/ossec/etc/authd.pass
   # Compare with vault value
   ./scripts/manage-vault.sh view | grep enrollment
   ```

3. **Check firewall allows port 1515:**
   ```bash
   sudo ss -tlnp | grep 1515
   ```

4. **Test enrollment manually:**
   ```bash
   # On agent
   sudo /var/ossec/bin/agent-auth -m <manager-ip> -P "<enrollment-password>"
   ```

### Cluster Synchronization Issues

**Symptoms:**
- `cluster_control -l` shows disconnected nodes
- Configuration not syncing between nodes

**Solutions:**

1. **Check cluster status:**
   ```bash
   sudo /var/ossec/bin/cluster_control -l
   sudo /var/ossec/bin/cluster_control -i
   ```

2. **Verify cluster key matches on all nodes:**
   ```bash
   sudo cat /var/ossec/etc/ossec.conf | grep -A5 "<cluster>"
   ```

3. **Check network connectivity between nodes:**
   ```bash
   nc -zv <other-manager-ip> 1516
   ```

4. **Restart cluster:**
   ```bash
   sudo /var/ossec/bin/wazuh-control restart
   ```

---

## Wazuh Dashboard Issues

### Dashboard Won't Load

**Symptoms:**
- Browser shows connection refused
- HTTPS certificate errors
- Blank page or loading forever

**Solutions:**

1. **Check service status:**
   ```bash
   sudo systemctl status wazuh-dashboard
   sudo journalctl -u wazuh-dashboard -n 50
   ```

2. **Verify port is listening:**
   ```bash
   sudo ss -tlnp | grep 443
   ```

3. **Check Indexer connectivity from Dashboard:**
   ```bash
   curl -k -u admin:<your-password> https://<indexer-ip>:9200/
   ```

4. **Check dashboard config:**
   ```bash
   sudo cat /etc/wazuh-dashboard/opensearch_dashboards.yml | grep -v "^#"
   ```

### MITRE ATT&CK Visualizations Not Working

**Symptoms:**
- MITRE dashboard shows no data
- Field mapping errors

**Solutions:**

1. **Check index mappings:**
   ```bash
   curl -k -u admin:<your-password> "https://localhost:9200/wazuh-alerts-*/_mapping" | jq '.[] | .mappings.properties.rule.properties.mitre'
   ```

2. **For existing indices with wrong mappings, reindex:**
   ```bash
   # Wait for new daily index, or manually reindex
   ```

3. **Verify Filebeat template is applied:**
   ```bash
   curl -k -u admin:<your-password> "https://localhost:9200/_template/wazuh"
   ```

### Wazuh App Shows "API is not reachable"

**Symptoms:**
- Dashboard loads but Wazuh app can't connect to API
- Red banner about API connection

**Solutions:**

1. **Check API configuration in Dashboard:**
   ```bash
   sudo cat /usr/share/wazuh-dashboard/data/wazuh/config/wazuh.yml
   ```

2. **Verify API is running:**
   ```bash
   curl -k -u wazuh:<your-api-password> https://<manager-ip>:55000/
   ```

3. **Check API credentials from vault:**
   ```bash
   ./scripts/manage-vault.sh view | grep api
   ```

---

## Wazuh Agent Issues

### Agent Not Connecting

**Symptoms:**
- Agent shows as disconnected in manager
- No heartbeat from agent

**Solutions:**

1. **Check agent status:**
   ```bash
   sudo /var/ossec/bin/wazuh-control status
   ```

2. **Verify manager IP in agent config:**
   ```bash
   sudo cat /var/ossec/etc/ossec.conf | grep -A5 "<client>"
   ```

3. **Test connectivity to manager:**
   ```bash
   nc -zv <manager-ip> 1514
   ```

4. **Check agent key:**
   ```bash
   sudo cat /var/ossec/etc/client.keys
   # Should have a valid key entry
   ```

5. **Re-register agent:**
   ```bash
   sudo /var/ossec/bin/agent-auth -m <manager-ip> -P "<enrollment-password>"
   sudo systemctl restart wazuh-agent
   ```

### Agent Not Sending Logs

**Symptoms:**
- Agent connected but no alerts in dashboard
- Missing log data

**Solutions:**

1. **Check localfile configuration:**
   ```bash
   sudo cat /var/ossec/etc/ossec.conf | grep -A10 "<localfile>"
   ```

2. **Verify log files exist and are readable:**
   ```bash
   ls -la /var/log/syslog  # or the configured log path
   ```

3. **Check agent logs for errors:**
   ```bash
   sudo tail -100 /var/ossec/logs/ossec.log
   ```

---

## Filebeat Issues

### Filebeat Not Forwarding Alerts

**Symptoms:**
- No new alerts in Indexer
- Filebeat errors in logs

**Solutions:**

1. **Check Filebeat status:**
   ```bash
   sudo systemctl status filebeat
   sudo filebeat test config
   sudo filebeat test output
   ```

2. **Verify Filebeat can reach Indexer:**
   ```bash
   curl -k -u admin:<your-password> https://<indexer-ip>:9200/
   ```

3. **Check Filebeat configuration:**
   ```bash
   sudo cat /etc/filebeat/filebeat.yml | grep -A20 "output.elasticsearch"
   ```

4. **Check for certificate issues:**
   ```bash
   sudo tail -50 /var/log/filebeat/filebeat | grep -i error
   ```

---

## Performance Issues

### High CPU Usage

**Solutions:**

1. **Check which process:**
   ```bash
   top -c | head -20
   ```

2. **For Indexer high CPU:**
   - Reduce refresh interval
   - Add more nodes to cluster
   - Check for expensive queries

3. **For Manager high CPU:**
   - Check agent count vs server specs
   - Review active response rules
   - Check for log parsing issues

### High Memory Usage

**Solutions:**

1. **For Indexer:**
   ```bash
   # Adjust heap size (max 50% of RAM)
   sudo vi /etc/wazuh-indexer/jvm.options
   ```

2. **For Manager:**
   ```bash
   # Check analysisd memory limits
   sudo cat /var/ossec/etc/internal_options.conf | grep analysisd
   ```

### Slow Dashboard

**Solutions:**

1. **Increase dashboard memory:**
   ```bash
   sudo vi /etc/wazuh-dashboard/node.options
   # Adjust --max-old-space-size
   ```

2. **Check Indexer performance:**
   ```bash
   curl -k -u admin:<your-password> "https://localhost:9200/_nodes/stats/jvm?pretty"
   ```

---

## Recovery Procedures

### Restore from Backup

```bash
# List available backups
ls -la backups/

# Restore specific backup
ansible-playbook playbooks/restore.yml -e "restore_from=BACKUP_TIMESTAMP"

# Or use the make shortcut:
make restore BACKUP_ID=BACKUP_TIMESTAMP
```

### Reset Admin Password

```bash
# Option 1: Use the vault rotation (recommended)
./scripts/manage-vault.sh rotate
ansible-playbook site.yml  # Redeploy with new credentials

# Option 2: Manual reset
# Generate new password hash
sudo /usr/share/wazuh-indexer/plugins/opensearch-security/tools/hash.sh -p "<new-password>"

# Update internal_users.yml with new hash
sudo vi /etc/wazuh-indexer/opensearch-security/internal_users.yml

# Apply changes
sudo /usr/share/wazuh-indexer/bin/indexer-security-init.sh

# Update the vault with the new password
./scripts/manage-vault.sh edit
```

### Full Stack Restart

```bash
# Stop all services (in order)
ansible wazuh_agents -m systemd -a "name=wazuh-agent state=stopped" --become
ansible wazuh_dashboards -m systemd -a "name=wazuh-dashboard state=stopped" --become
ansible wazuh_managers -m systemd -a "name=wazuh-manager state=stopped" --become
ansible wazuh_managers -m systemd -a "name=filebeat state=stopped" --become
ansible wazuh_indexers -m systemd -a "name=wazuh-indexer state=stopped" --become

# Start all services (in order)
ansible wazuh_indexers -m systemd -a "name=wazuh-indexer state=started" --become
sleep 30
ansible wazuh_managers -m systemd -a "name=wazuh-manager state=started" --become
ansible wazuh_managers -m systemd -a "name=filebeat state=started" --become
ansible wazuh_dashboards -m systemd -a "name=wazuh-dashboard state=started" --become
ansible wazuh_agents -m systemd -a "name=wazuh-agent state=started" --become
```

---

## Getting Help

If issues persist after trying these solutions:

1. **Collect diagnostic information:**
   ```bash
   ansible-playbook playbooks/health-check.yml -e "check_agents=true check_indices=true" > health-report.txt
   ```

2. **Check Wazuh documentation:**
   - [Wazuh Documentation](https://documentation.wazuh.com)
   - [Wazuh GitHub Issues](https://github.com/wazuh/wazuh/issues)

3. **Community support:**
   - [Wazuh Slack](https://wazuh.com/community/join-us-on-slack/)
   - [Wazuh Google Group](https://groups.google.com/g/wazuh)
