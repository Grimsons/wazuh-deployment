# Prometheus Monitoring Guide

This guide covers setting up Prometheus monitoring for your Wazuh deployment, including exporters and Grafana dashboards.

## Overview

The `wazuh-monitoring` role deploys:

| Component | Port | Description |
|-----------|------|-------------|
| **OpenSearch Exporter** | 9114 | Indexer cluster metrics (JVM, disk, shards, docs) |
| **Manager API Exporter** | 9115 | Agent stats, alerts by severity, manager health |
| **Grafana Dashboard** | - | Pre-built dashboard with all key metrics |

## Quick Start

### Deploy Exporters

After your main Wazuh deployment, enable monitoring:

```bash
ansible-playbook site.yml --tags monitoring -e wazuh_monitoring_enabled=true
```

Or enable permanently in `group_vars/all.yml`:

```yaml
wazuh_monitoring_enabled: true
```

### Configure Prometheus

Add these scrape targets to your `prometheus.yml`:

```yaml
scrape_configs:
  # Indexer metrics (one target per indexer node)
  - job_name: 'wazuh-indexer'
    static_configs:
      - targets:
          - 'indexer1.example.com:9114'
          - 'indexer2.example.com:9114'
          - 'indexer3.example.com:9114'
    scheme: https
    tls_config:
      insecure_skip_verify: true  # For self-signed certs
    # Optional: use basic auth if configured
    # basic_auth:
    #   username: admin
    #   password: your-password

  # Manager metrics (one target per manager node)
  - job_name: 'wazuh-manager'
    static_configs:
      - targets:
          - 'manager1.example.com:9115'
          - 'manager2.example.com:9115'
```

### Import Grafana Dashboard

**Option 1: Auto-provisioning** (if Grafana is on a dashboard node)

The dashboard is automatically provisioned to `/etc/grafana/provisioning/dashboards/wazuh-dashboard.json`.

**Option 2: Manual import via UI**

1. Copy `roles/wazuh-monitoring/files/grafana-wazuh-dashboard.json` to your machine
2. In Grafana: **Dashboards → Import → Upload JSON file**
3. Select your Prometheus datasource

**Option 3: Import via API**

```bash
curl -X POST \
  -H "Authorization: Bearer YOUR_GRAFANA_API_KEY" \
  -H "Content-Type: application/json" \
  -d @roles/wazuh-monitoring/files/grafana-wazuh-dashboard.json \
  http://your-grafana:3000/api/dashboards/db
```

**Option 4: Copy to provisioning directory**

```bash
scp roles/wazuh-monitoring/files/grafana-wazuh-dashboard.json \
  user@grafana-server:/etc/grafana/provisioning/dashboards/wazuh.json
sudo systemctl restart grafana-server
```

## Metrics Reference

### Indexer Metrics (Port 9114)

#### Cluster Health
| Metric | Description |
|--------|-------------|
| `wazuh_indexer_cluster_status` | Cluster status (0=green, 1=yellow, 2=red) |
| `wazuh_indexer_cluster_nodes_total` | Total nodes in cluster |
| `wazuh_indexer_cluster_data_nodes` | Number of data nodes |
| `wazuh_indexer_cluster_active_shards` | Active shard count |
| `wazuh_indexer_cluster_unassigned_shards` | Unassigned shards (should be 0) |
| `wazuh_indexer_cluster_active_shards_percent` | Percentage of active shards |

#### Node Statistics
| Metric | Labels | Description |
|--------|--------|-------------|
| `wazuh_indexer_jvm_heap_used_percent` | `node` | JVM heap usage % |
| `wazuh_indexer_jvm_heap_used_bytes` | `node` | JVM heap used (bytes) |
| `wazuh_indexer_disk_used_percent` | `node` | Disk usage % |
| `wazuh_indexer_disk_free_bytes` | `node` | Free disk space |
| `wazuh_indexer_cpu_percent` | `node` | CPU usage % |
| `wazuh_indexer_load_average_1m` | `node` | 1-minute load average |
| `wazuh_indexer_node_docs_count` | `node` | Documents on node |
| `wazuh_indexer_node_store_size_bytes` | `node` | Store size on node |

#### Wazuh-Specific
| Metric | Description |
|--------|-------------|
| `wazuh_alerts_index_count` | Number of wazuh-alerts-* indices |
| `wazuh_alerts_total_docs` | Total documents in alerts indices |
| `wazuh_alerts_total_size_bytes` | Total size of alerts indices |

### Manager Metrics (Port 9115)

#### Agent Statistics
| Metric | Labels | Description |
|--------|--------|-------------|
| `wazuh_agents_total` | - | Total registered agents |
| `wazuh_agents_active` | - | Currently active agents |
| `wazuh_agents_disconnected` | - | Disconnected agents |
| `wazuh_agents_pending` | - | Pending agents |
| `wazuh_agents_never_connected` | - | Never-connected agents |
| `wazuh_agents_by_status` | `status` | Agents by connection status |
| `wazuh_agents_by_os` | `os` | Agents by operating system |

#### Alert Statistics
| Metric | Labels | Description |
|--------|--------|-------------|
| `wazuh_alerts_total` | - | Total alerts in scrape window |
| `wazuh_alerts_critical` | - | Level 12+ alerts |
| `wazuh_alerts_high` | - | Level 10-11 alerts |
| `wazuh_alerts_medium` | - | Level 7-9 alerts |
| `wazuh_alerts_low` | - | Level 0-6 alerts |
| `wazuh_alerts_by_level` | `level` | Alerts by exact level (0-15) |
| `wazuh_alerts_by_rule_group` | `group` | Top 10 rule groups |

#### Manager Status
| Metric | Description |
|--------|-------------|
| `wazuh_manager_status` | Manager running (1) or stopped (0) |
| `wazuh_manager_cluster_enabled` | Cluster mode enabled |
| `wazuh_manager_cluster_nodes` | Nodes in manager cluster |
| `wazuh_manager_is_master` | Is this node the cluster master |

## Grafana Dashboard Panels

The pre-built dashboard includes:

### Overview Row
- Cluster Status (green/yellow/red indicator)
- Active Agents count
- Disconnected Agents count (with warning thresholds)
- Critical Alerts count
- Cluster Nodes count
- Active Shards count

### Agents Row
- Agents by Status (pie chart)
- Agents by OS (pie chart)
- Agent Status Over Time (time series)

### Alerts Row
- Alerts by Severity (stacked bar chart)
- Alerts by Rule Group (top 10 bar gauge)

### Indexer Performance Row
- JVM Heap Usage % (with 75%/90% thresholds)
- Disk Usage % (with 75%/90% thresholds)
- CPU Usage %

### Storage Row
- Wazuh Alerts Total Size
- Alerts Index Count
- Total Documents
- Unassigned Shards
- Store Size by Node (time series)
- Document Count by Node (time series)

## Alert Rules

Example Prometheus alerting rules:

```yaml
groups:
  - name: wazuh
    rules:
      - alert: WazuhClusterRed
        expr: wazuh_indexer_cluster_status == 2
        for: 5m
        labels:
          severity: critical
        annotations:
          summary: "Wazuh indexer cluster is RED"
          description: "Cluster health is red for more than 5 minutes"

      - alert: WazuhClusterYellow
        expr: wazuh_indexer_cluster_status == 1
        for: 15m
        labels:
          severity: warning
        annotations:
          summary: "Wazuh indexer cluster is YELLOW"

      - alert: WazuhAgentsDisconnected
        expr: wazuh_agents_disconnected > 10
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "{{ $value }} Wazuh agents disconnected"

      - alert: WazuhJvmHeapHigh
        expr: wazuh_indexer_jvm_heap_used_percent > 85
        for: 10m
        labels:
          severity: warning
        annotations:
          summary: "JVM heap usage high on {{ $labels.node }}"

      - alert: WazuhDiskSpaceLow
        expr: wazuh_indexer_disk_used_percent > 80
        for: 15m
        labels:
          severity: warning
        annotations:
          summary: "Disk usage high on {{ $labels.node }}: {{ $value }}%"

      - alert: WazuhCriticalAlerts
        expr: rate(wazuh_alerts_critical[5m]) > 1
        for: 5m
        labels:
          severity: warning
        annotations:
          summary: "High rate of critical Wazuh alerts"
```

## Configuration Variables

Set these in `group_vars/all.yml`:

```yaml
# Enable/disable monitoring
wazuh_monitoring_enabled: true

# Indexer exporter settings
wazuh_indexer_exporter_enabled: true
wazuh_indexer_metrics_port: 9114

# Manager exporter settings
wazuh_manager_exporter_enabled: true
wazuh_manager_exporter_port: 9115
wazuh_manager_exporter_scrape_interval: 30  # seconds

# Grafana dashboard provisioning
wazuh_grafana_dashboard_enabled: true
wazuh_grafana_provisioning_dir: "/etc/grafana/provisioning/dashboards"
```

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         Prometheus                               │
│                    (scrapes every 30s)                          │
└───────────────────────────┬─────────────────────────────────────┘
                            │
        ┌───────────────────┼───────────────────┐
        │                   │                   │
        ▼                   ▼                   ▼
┌───────────────┐   ┌───────────────┐   ┌───────────────┐
│   Indexer 1   │   │   Indexer 2   │   │   Indexer 3   │
│  :9114/metrics│   │  :9114/metrics│   │  :9114/metrics│
│               │   │               │   │               │
│ opensearch-   │   │ opensearch-   │   │ opensearch-   │
│ exporter.py   │   │ exporter.py   │   │ exporter.py   │
└───────────────┘   └───────────────┘   └───────────────┘

        ┌───────────────────┬───────────────────┐
        │                   │                   │
        ▼                   ▼                   ▼
┌───────────────┐   ┌───────────────┐   ┌───────────────┐
│   Manager 1   │   │   Manager 2   │   │               │
│  :9115/metrics│   │  :9115/metrics│   │    Grafana    │
│               │   │               │   │               │
│ wazuh-manager-│   │ wazuh-manager-│   │   Dashboard   │
│ exporter.py   │   │ exporter.py   │   │   (imported)  │
└───────────────┘   └───────────────┘   └───────────────┘
```

## Troubleshooting

### Exporter not starting

Check systemd status:
```bash
systemctl status wazuh-opensearch-exporter
systemctl status wazuh-manager-exporter
journalctl -u wazuh-opensearch-exporter -f
```

### No metrics from indexer

Verify OpenSearch is accessible:
```bash
curl -k -u admin:password https://localhost:9200/_cluster/health
```

### No metrics from manager

Verify Wazuh API is accessible:
```bash
curl -k -u wazuh-wui:password https://localhost:55000/security/user/authenticate
```

### Prometheus can't scrape

Check firewall rules:
```bash
# On indexer
sudo firewall-cmd --list-ports | grep 9114
sudo ufw status | grep 9114

# On manager
sudo firewall-cmd --list-ports | grep 9115
sudo ufw status | grep 9115
```

### Dashboard shows no data

1. Verify Prometheus datasource is configured in Grafana
2. Check Prometheus targets: `http://prometheus:9090/targets`
3. Verify metrics exist: `http://prometheus:9090/graph` → query `wazuh_agents_active`

## Disabling Monitoring

To remove exporters:

```bash
# Stop and disable services
ansible all -m systemd -a "name=wazuh-opensearch-exporter state=stopped enabled=no" --become
ansible all -m systemd -a "name=wazuh-manager-exporter state=stopped enabled=no" --become

# Remove files
ansible all -m file -a "path=/opt/wazuh-exporter state=absent" --become
ansible all -m file -a "path=/etc/systemd/system/wazuh-opensearch-exporter.service state=absent" --become
ansible all -m file -a "path=/etc/systemd/system/wazuh-manager-exporter.service state=absent" --become
```
