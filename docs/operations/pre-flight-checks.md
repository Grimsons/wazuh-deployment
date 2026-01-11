# Pre-Flight Checks Guide

This document describes the pre-flight validation process that should be run before any Wazuh deployment or upgrade.

## Overview

The pre-flight checks playbook (`playbooks/pre-flight-checks.yml`) validates:
- System resources (RAM, CPU, disk space)
- Network connectivity between nodes
- Port availability
- DNS resolution
- Package manager access
- Certificate validity
- Existing service status

## Usage

### Run All Checks

```bash
ansible-playbook playbooks/pre-flight-checks.yml
```

### Check Specific Host Groups

```bash
# Check only indexers
ansible-playbook playbooks/pre-flight-checks.yml --limit wazuh_indexers

# Check only managers
ansible-playbook playbooks/pre-flight-checks.yml --limit wazuh_managers
```

### Skip Specific Checks

```bash
# Skip package manager checks (for air-gapped environments)
ansible-playbook playbooks/pre-flight-checks.yml -e "check_package_manager=false"

# Skip certificate checks
ansible-playbook playbooks/pre-flight-checks.yml -e "check_certificates=false"
```

## Checks Performed

### System Resources

| Check | Minimum Requirement | Notes |
|-------|---------------------|-------|
| RAM | 4 GB (Indexer: 8 GB) | Indexer is memory-intensive |
| CPU | 2 cores | 4+ recommended for production |
| Disk | 50 GB free | More for alert retention |

### Network Connectivity

Validates connectivity between:
- All nodes to Indexer nodes (port 9200, 9300)
- All nodes to Manager nodes (port 1514, 1515, 55000)
- All nodes to Dashboard nodes (port 443)

### Port Availability

Checks that required ports are not in use:

| Component | Ports |
|-----------|-------|
| Indexer | 9200, 9300 |
| Manager | 1514, 1515, 1516, 55000 |
| Dashboard | 443 |

### DNS Resolution

Verifies all hostnames in inventory can be resolved.

### Package Manager

Tests connectivity to package repositories:
- APT (Debian/Ubuntu)
- DNF/YUM (RHEL/CentOS/Rocky)

### Certificate Validity

If certificates exist, checks:
- Certificate expiration (warns if < 30 days)
- Certificate chain validity
- Key/certificate matching

## Check Results

The playbook outputs a summary report:

```
══════════════════════════════════════════════════════════════
                 PRE-FLIGHT CHECK RESULTS
══════════════════════════════════════════════════════════════

Host: indexer-1 (192.168.1.10)
  RAM:           16 GB     ✓ PASS (min: 8 GB)
  CPU:           4 cores   ✓ PASS (min: 2)
  Disk:          120 GB    ✓ PASS (min: 50 GB)
  Connectivity:            ✓ PASS
  Ports:                   ✓ PASS

Host: manager-1 (192.168.1.20)
  RAM:           8 GB      ✓ PASS (min: 4 GB)
  CPU:           4 cores   ✓ PASS (min: 2)
  Disk:          80 GB     ✓ PASS (min: 50 GB)
  Connectivity:            ✓ PASS
  Ports:                   ✓ PASS

Overall Status: ✓ ALL CHECKS PASSED
══════════════════════════════════════════════════════════════
```

## Handling Failures

### Insufficient RAM

```bash
# Check current memory usage
free -h

# Identify memory-hungry processes
ps aux --sort=-%mem | head -20

# Options:
# 1. Add more RAM
# 2. Stop unnecessary services
# 3. Use swap (not recommended for production)
```

### Insufficient Disk Space

```bash
# Check disk usage
df -h

# Find large files
du -sh /* 2>/dev/null | sort -h | tail -20

# Clean up options:
# 1. Remove old logs: journalctl --vacuum-time=7d
# 2. Remove old packages: apt autoremove / dnf autoremove
# 3. Clear package cache: apt clean / dnf clean all
```

### Port Already in Use

```bash
# Find process using port
ss -tlnp | grep :9200
lsof -i :9200

# Stop conflicting service
systemctl stop <service-name>
```

### Network Connectivity Failed

```bash
# Test connectivity manually
nc -zv indexer-1 9200
telnet indexer-1 9200

# Check firewall
iptables -L -n
firewall-cmd --list-all

# Verify routing
traceroute indexer-1
```

### DNS Resolution Failed

```bash
# Test DNS
nslookup indexer-1
dig indexer-1

# Check /etc/hosts
cat /etc/hosts

# Check resolver config
cat /etc/resolv.conf
```

### Package Manager Unreachable

```bash
# Test manually
apt update  # Debian/Ubuntu
dnf check-update  # RHEL/CentOS

# For air-gapped environments:
# - Set up local mirror
# - Or skip check: -e "check_package_manager=false"
```

## Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `min_ram_mb` | Minimum RAM in MB | `4096` |
| `min_ram_mb_indexer` | Minimum RAM for Indexer | `8192` |
| `min_cpu_cores` | Minimum CPU cores | `2` |
| `min_disk_gb` | Minimum free disk space | `50` |
| `check_package_manager` | Check package repos | `true` |
| `check_certificates` | Check cert validity | `true` |
| `connectivity_timeout` | Connection timeout (sec) | `5` |

## Integration with Deployment

It's recommended to run pre-flight checks before:

1. **Initial deployment**
   ```bash
   ansible-playbook playbooks/pre-flight-checks.yml
   ansible-playbook site.yml
   ```

2. **Upgrades**
   ```bash
   ansible-playbook playbooks/pre-flight-checks.yml
   ansible-playbook playbooks/upgrade.yml -e "target_version=4.10.0"
   ```

3. **Disaster recovery**
   ```bash
   ansible-playbook playbooks/pre-flight-checks.yml
   ansible-playbook playbooks/restore.yml -e "backup_timestamp=20240115_020000"
   ```

## Automated Validation

For CI/CD pipelines, the playbook exits with:
- `0` - All checks passed
- `1` - One or more checks failed

```bash
#!/bin/bash
if ansible-playbook playbooks/pre-flight-checks.yml; then
    echo "Pre-flight checks passed, proceeding with deployment"
    ansible-playbook site.yml
else
    echo "Pre-flight checks failed, aborting deployment"
    exit 1
fi
```
