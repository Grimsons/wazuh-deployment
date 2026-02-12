# Architecture Diagrams

This document provides visual representations of Wazuh deployment architectures supported by this project.

## Component Overview

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           WAZUH STACK COMPONENTS                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌──────────────────┐    ┌──────────────────┐    ┌──────────────────┐       │
│  │  WAZUH INDEXER   │    │  WAZUH MANAGER   │    │ WAZUH DASHBOARD  │       │
│  │  (OpenSearch)    │    │                  │    │  (Web UI)        │       │
│  │                  │    │                  │    │                  │       │
│  │  - Alert storage │    │  - Log analysis  │    │  - Visualization │       │
│  │  - Search/Query  │    │  - Rule matching │    │  - Management    │       │
│  │  - Aggregation   │    │  - Active resp.  │    │  - Reporting     │       │
│  └────────▲─────────┘    └────────▲─────────┘    └────────▲─────────┘       │
│           │                       │                       │                  │
│           │ Port 9200             │ Port 1514/1515        │ Port 443         │
│           │ (HTTPS)               │ (TCP)                 │ (HTTPS)          │
│           │                       │                       │                  │
│  ┌────────┴─────────┐    ┌───────┴────────┐              │                  │
│  │    FILEBEAT      │    │  WAZUH AGENTS  │              │                  │
│  │                  │    │                │              │                  │
│  │  Forwards alerts │    │  - FIM         │    ┌────────┴─────────┐        │
│  │  from Manager    │    │  - Rootcheck   │    │     USERS        │        │
│  │  to Indexer      │    │  - Syscheck    │    │                  │        │
│  └──────────────────┘    │  - Log collect │    │  Browser access  │        │
│                          └────────────────┘    └──────────────────┘        │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

## All-in-One Deployment

Single server deployment suitable for small environments (< 50 agents).

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         ALL-IN-ONE SERVER                                    │
│                     (Recommended: 8GB RAM, 4 CPU)                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌────────────────────────────────────────────────────────────────────┐     │
│  │                      SINGLE HOST (e.g., 192.168.1.10)              │     │
│  │                                                                     │     │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌───────────┐ │     │
│  │  │   INDEXER   │  │   MANAGER   │  │  DASHBOARD  │  │ FILEBEAT  │ │     │
│  │  │  :9200      │◄─┤  :55000     │  │  :443       │  │           │ │     │
│  │  │  :9300      │  │  :1514      │  │             │  │           │ │     │
│  │  └─────────────┘  │  :1515      │  └─────────────┘  └───────────┘ │     │
│  │                   └─────────────┘                                  │     │
│  └────────────────────────────────────────────────────────────────────┘     │
│                                    ▲                                         │
│                                    │                                         │
│                          Port 1514 (Agent communication)                     │
│                          Port 1515 (Agent enrollment)                        │
│                                    │                                         │
│  ┌─────────────────────────────────┴───────────────────────────────────┐    │
│  │                          MONITORED HOSTS                             │    │
│  │                                                                      │    │
│  │   ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐  │    │
│  │   │ Agent 1 │  │ Agent 2 │  │ Agent 3 │  │ Agent 4 │  │ Agent N │  │    │
│  │   │ Linux   │  │ Linux   │  │ Windows │  │ macOS   │  │   ...   │  │    │
│  │   └─────────┘  └─────────┘  └─────────┘  └─────────┘  └─────────┘  │    │
│  └──────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Production deployment:**
```bash
# 1. Run setup wizard (generates inventory with single host for all components)
./setup.sh          # or ./setup-tui.sh for TUI version

# 2. Deploy with bootstrap (first time)
ansible-playbook site.yml --tags bootstrap,all

# 3. Subsequent deployments
ansible-playbook site.yml
```

**Quick test only (not for production):**
```bash
# Minimal test deployment - no credential management, no index policies
ansible-playbook wazuh-aio.yml -e "target_host=192.168.1.10"
```

---

## Distributed Deployment (Basic)

Separate servers for each component. Suitable for medium environments (50-500 agents).

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                       DISTRIBUTED DEPLOYMENT                                 │
│                    (3 Servers, Medium Environment)                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│   INDEXER NODE                MANAGER NODE               DASHBOARD NODE      │
│   192.168.1.10                192.168.1.11               192.168.1.12        │
│   (8GB RAM, 4 CPU)            (8GB RAM, 4 CPU)           (4GB RAM, 2 CPU)    │
│                                                                              │
│  ┌─────────────────┐        ┌─────────────────┐        ┌─────────────────┐  │
│  │  WAZUH INDEXER  │        │  WAZUH MANAGER  │        │ WAZUH DASHBOARD │  │
│  │                 │        │                 │        │                 │  │
│  │  - OpenSearch   │        │  - Analysis     │        │  - Web UI       │  │
│  │  - Security     │◄───────┤  - Filebeat     │        │  - API access   │  │
│  │    plugin       │  :9200 │  - Authd        │        │                 │  │
│  │                 │        │                 │        │                 │  │
│  │  Ports:         │        │  Ports:         │        │  Ports:         │  │
│  │  - 9200 (API)   │        │  - 55000 (API)  │        │  - 443 (HTTPS)  │  │
│  │  - 9300 (Clust) │        │  - 1514 (Agent) │        │                 │  │
│  │                 │        │  - 1515 (Enroll)│        │                 │  │
│  └────────▲────────┘        └────────▲────────┘        └────────▲────────┘  │
│           │                          │                          │           │
│           │                          │                          │           │
│           │        ┌─────────────────┴──────────────────┐       │           │
│           │        │         WAZUH AGENTS               │       │           │
│           │        │                                    │       │           │
│           │        │  ┌───────┐ ┌───────┐ ┌───────┐    │       │           │
│           │        │  │Agent 1│ │Agent 2│ │Agent N│    │       │           │
│           │        │  └───────┘ └───────┘ └───────┘    │       │           │
│           │        └────────────────────────────────────┘       │           │
│           │                                                     │           │
│           │              ┌──────────────────────┐               │           │
│           └──────────────┤   ADMIN/ANALYSTS     ├───────────────┘           │
│                          │   (Browser Access)   │                           │
│                          └──────────────────────┘                           │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

**Deployment command:**
```bash
ansible-playbook site.yml
```

---

## High Availability Cluster

Multi-node cluster for production environments (500+ agents).

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    HIGH AVAILABILITY CLUSTER                                 │
│              (Multi-node, Production Environment)                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│  ┌───────────────────────────── INDEXER CLUSTER ──────────────────────────┐ │
│  │                         (3+ nodes recommended)                          │ │
│  │                                                                         │ │
│  │  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐        │ │
│  │  │  INDEXER-1      │  │  INDEXER-2      │  │  INDEXER-3      │        │ │
│  │  │  192.168.1.10   │  │  192.168.1.11   │  │  192.168.1.12   │        │ │
│  │  │  (Master)       │◄─┤  (Data)         │◄─┤  (Data)         │        │ │
│  │  │                 │  │                 │  │                 │        │ │
│  │  │  :9200, :9300   │  │  :9200, :9300   │  │  :9200, :9300   │        │ │
│  │  └─────────────────┘  └─────────────────┘  └─────────────────┘        │ │
│  │            ▲                   ▲                   ▲                   │ │
│  │            └───────────────────┼───────────────────┘                   │ │
│  │                    Inter-node communication (:9300)                    │ │
│  └─────────────────────────────────┬───────────────────────────────────────┘ │
│                                    │                                         │
│                              :9200 │ (Load Balanced)                         │
│                                    ▼                                         │
│  ┌───────────────────────── MANAGER CLUSTER ──────────────────────────────┐ │
│  │                        (2+ nodes recommended)                           │ │
│  │                                                                         │ │
│  │  ┌─────────────────────────┐      ┌─────────────────────────┐          │ │
│  │  │  MANAGER-1 (Master)     │      │  MANAGER-2 (Worker)     │          │ │
│  │  │  192.168.1.20           │◄────►│  192.168.1.21           │          │ │
│  │  │                         │:1516 │                         │          │ │
│  │  │  - wazuh-manager        │      │  - wazuh-manager        │          │ │
│  │  │  - filebeat             │      │  - filebeat             │          │ │
│  │  │                         │      │                         │          │ │
│  │  │  :55000, :1514, :1515   │      │  :55000, :1514, :1515   │          │ │
│  │  └─────────────────────────┘      └─────────────────────────┘          │ │
│  │                                                                         │ │
│  └───────────────────────────────┬─────────────────────────────────────────┘ │
│                                  │                                           │
│                    :1514 (Load Balanced for Agents)                          │
│                                  │                                           │
│  ┌───────────────────────────────┼─────────────────────────────────────────┐ │
│  │                          LOAD BALANCER                                  │ │
│  │                       (HAProxy / Nginx / F5)                            │ │
│  │                          192.168.1.100                                  │ │
│  │                                                                         │ │
│  │    :443 ──► Dashboard        :1514 ──► Manager (Agent Traffic)          │ │
│  │    :9200 ─► Indexer          :1515 ──► Manager (Enrollment)             │ │
│  └───────────────────────────────┼─────────────────────────────────────────┘ │
│                                  │                                           │
│  ┌───────────────────────────────┴─────────────────────────────────────────┐ │
│  │                          DASHBOARD NODES                                │ │
│  │                                                                         │ │
│  │  ┌─────────────────────┐         ┌─────────────────────┐               │ │
│  │  │  DASHBOARD-1        │         │  DASHBOARD-2        │               │ │
│  │  │  192.168.1.30       │         │  192.168.1.31       │               │ │
│  │  │  :443               │         │  :443               │               │ │
│  │  └─────────────────────┘         └─────────────────────┘               │ │
│  └─────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────────┐ │
│  │                         WAZUH AGENTS (1000+)                            │ │
│  │                                                                         │ │
│  │  ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐    │ │
│  │  │Linux   │ │Windows │ │Docker  │ │Cloud   │ │Network │ │  ...   │    │ │
│  │  │Servers │ │Servers │ │Hosts   │ │Inst.   │ │Devices │ │        │    │ │
│  │  └────────┘ └────────┘ └────────┘ └────────┘ └────────┘ └────────┘    │ │
│  └─────────────────────────────────────────────────────────────────────────┘ │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Network Flow Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          DATA FLOW                                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│    AGENTS                    MANAGER                INDEXER      DASHBOARD   │
│                                                                              │
│  ┌─────────┐                                                                │
│  │ Log     │                                                                │
│  │ Sources │                                                                │
│  │         │                                                                │
│  │ - Files │    ┌─────────────────────────────────────────────────────┐    │
│  │ - Events│    │                    WAZUH MANAGER                    │    │
│  │ - Syscol│    │                                                     │    │
│  │         │    │  1. Receive    2. Decode     3. Match      4. Alert │    │
│  └────┬────┘    │     Logs   ──►   Logs    ──►  Rules   ──►  Generate │    │
│       │         │                                                     │    │
│       │         └──────────────────────────────────────┬──────────────┘    │
│       ▼                                                │                    │
│  ┌─────────┐          Port 1514 (TCP)                  │                    │
│  │ AGENT   │─────────────────────────►                 │                    │
│  │         │                                           ▼                    │
│  │ - ossec │                                    ┌─────────────┐             │
│  │ - FIM   │                                    │  FILEBEAT   │             │
│  │ - SCA   │                                    │             │             │
│  │         │                                    │ JSON alerts │             │
│  └─────────┘                                    └──────┬──────┘             │
│                                                        │                    │
│                                                        │ Port 9200          │
│                                                        │ (HTTPS)            │
│                                                        ▼                    │
│                                                 ┌─────────────┐             │
│                                                 │   INDEXER   │             │
│                                                 │             │             │
│                                                 │ - Index     │             │
│                                                 │ - Store     │             │
│                                                 │ - Search    │             │
│                                                 └──────┬──────┘             │
│                                                        │                    │
│                                                        │ Port 9200          │
│                                                        │ (Query)            │
│                                                        ▼                    │
│                                                 ┌─────────────┐   Port 443  │
│                                                 │  DASHBOARD  │◄────────────│
│                                                 │             │   (HTTPS)   │
│                                                 │ - Visualize │             │
│                                                 │ - Analyze   │   ┌──────┐  │
│                                                 │ - Report    │   │ USER │  │
│                                                 └─────────────┘   └──────┘  │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Port Reference

| Port | Protocol | Component | Purpose |
|------|----------|-----------|---------|
| 443 | HTTPS | Dashboard | Web UI access |
| 9200 | HTTPS | Indexer | REST API |
| 9300 | TCP | Indexer | Inter-node cluster communication |
| 55000 | HTTPS | Manager | Wazuh API |
| 1514 | TCP | Manager | Agent event communication |
| 1515 | TCP | Manager | Agent enrollment (authd) |
| 1516 | TCP | Manager | Cluster daemon (wazuh-clusterd) |
| 514 | UDP/TCP | Manager | Syslog collection (optional) |

---

## Firewall Rules Summary

### Indexer Node

```bash
# Inbound
-A INPUT -p tcp --dport 9200 -s MANAGER_IP -j ACCEPT      # From Manager/Filebeat
-A INPUT -p tcp --dport 9200 -s DASHBOARD_IP -j ACCEPT    # From Dashboard
-A INPUT -p tcp --dport 9300 -s INDEXER_CLUSTER -j ACCEPT # Cluster nodes

# Outbound
-A OUTPUT -p tcp --dport 9300 -d INDEXER_CLUSTER -j ACCEPT # To cluster nodes
```

### Manager Node

```bash
# Inbound
-A INPUT -p tcp --dport 1514 -j ACCEPT                    # Agent traffic
-A INPUT -p tcp --dport 1515 -j ACCEPT                    # Agent enrollment
-A INPUT -p tcp --dport 1516 -s MANAGER_CLUSTER -j ACCEPT # Manager cluster
-A INPUT -p tcp --dport 55000 -s DASHBOARD_IP -j ACCEPT   # API from Dashboard

# Outbound
-A OUTPUT -p tcp --dport 9200 -d INDEXER_IP -j ACCEPT     # To Indexer
-A OUTPUT -p tcp --dport 1516 -d MANAGER_CLUSTER -j ACCEPT # Manager cluster
```

### Dashboard Node

```bash
# Inbound
-A INPUT -p tcp --dport 443 -j ACCEPT                     # HTTPS access

# Outbound
-A OUTPUT -p tcp --dport 9200 -d INDEXER_IP -j ACCEPT     # To Indexer
-A OUTPUT -p tcp --dport 55000 -d MANAGER_IP -j ACCEPT    # To Manager API
```

### Agent

```bash
# Outbound only
-A OUTPUT -p tcp --dport 1514 -d MANAGER_IP -j ACCEPT     # Event communication
-A OUTPUT -p tcp --dport 1515 -d MANAGER_IP -j ACCEPT     # Enrollment
```

---

## Certificate Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                       CERTIFICATE HIERARCHY                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│                          ┌──────────────────┐                                │
│                          │    ROOT CA       │                                │
│                          │  (root-ca.pem)   │                                │
│                          │                  │                                │
│                          │  Self-signed or  │                                │
│                          │  External CA     │                                │
│                          └────────┬─────────┘                                │
│                                   │                                          │
│                    Signs all component certificates                          │
│                                   │                                          │
│          ┌────────────────────────┼────────────────────────┐                │
│          │                        │                        │                │
│          ▼                        ▼                        ▼                │
│  ┌───────────────┐      ┌───────────────┐      ┌───────────────┐           │
│  │  ADMIN CERT   │      │ INDEXER CERT  │      │ MANAGER CERT  │           │
│  │               │      │               │      │               │           │
│  │ admin.pem     │      │ indexer.pem   │      │ manager.pem   │           │
│  │ admin-key.pem │      │ indexer-key   │      │ manager-key   │           │
│  │               │      │               │      │               │           │
│  │ Used for:     │      │ Used for:     │      │ Used for:     │           │
│  │ - securityadm │      │ - HTTPS API   │      │ - API TLS     │           │
│  │ - Index mgmt  │      │ - Node-to-node│      │ - Filebeat    │           │
│  └───────────────┘      └───────────────┘      └───────────────┘           │
│                                                                              │
│                         ┌───────────────┐                                   │
│                         │DASHBOARD CERT │                                   │
│                         │               │                                   │
│                         │ dashboard.pem │                                   │
│                         │ dashboard-key │                                   │
│                         │               │                                   │
│                         │ Used for:     │                                   │
│                         │ - HTTPS UI    │                                   │
│                         └───────────────┘                                   │
│                                                                              │
│  Certificate Locations:                                                      │
│  ├── files/certs/           (Ansible control node)                          │
│  ├── /etc/wazuh-indexer/certs/                                              │
│  ├── /etc/wazuh-dashboard/certs/                                            │
│  ├── /etc/filebeat/certs/                                                   │
│  └── /var/ossec/etc/sslmanager.cert (Manager)                               │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Deployment Decision Tree

```
                            ┌─────────────────────┐
                            │ How many agents do  │
                            │ you need to monitor?│
                            └──────────┬──────────┘
                                       │
                    ┌──────────────────┼──────────────────┐
                    │                  │                  │
                    ▼                  ▼                  ▼
            ┌───────────┐      ┌───────────┐      ┌───────────┐
            │  < 50     │      │  50-500   │      │   > 500   │
            │  agents   │      │  agents   │      │  agents   │
            └─────┬─────┘      └─────┬─────┘      └─────┬─────┘
                  │                  │                  │
                  ▼                  ▼                  ▼
          ┌───────────────┐  ┌───────────────┐  ┌───────────────┐
          │  ALL-IN-ONE   │  │  DISTRIBUTED  │  │   HA CLUSTER  │
          │               │  │    (Basic)    │  │               │
          │  1 server     │  │  3 servers    │  │  7+ servers   │
          │  8GB RAM      │  │  8GB each     │  │  Varies       │
          │               │  │               │  │               │
          │  site.yml     │  │  site.yml     │  │  site.yml     │
          │  (1 host inv) │  │  (3 host inv) │  │  (custom inv) │
          └───────────────┘  └───────────────┘  └───────────────┘

    All deployments use: ./setup.sh → ansible-playbook site.yml
    The setup wizard generates the appropriate inventory for your scale.
```

---

## Integration Points

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      EXTERNAL INTEGRATIONS                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                              │
│                           ┌─────────────────┐                                │
│                           │  WAZUH MANAGER  │                                │
│                           └────────┬────────┘                                │
│                                    │                                         │
│      ┌─────────────────────────────┼─────────────────────────────┐          │
│      │                             │                             │          │
│      ▼                             ▼                             ▼          │
│  ┌─────────┐                 ┌─────────┐                  ┌─────────┐       │
│  │ SLACK   │                 │ EMAIL   │                  │VIRUSTOTL│       │
│  │         │                 │ (SMTP)  │                  │         │       │
│  │ Webhook │                 │         │                  │ API     │       │
│  │ alerts  │                 │ Alerts  │                  │ Lookups │       │
│  └─────────┘                 └─────────┘                  └─────────┘       │
│                                                                              │
│      ┌─────────────────────────────┼─────────────────────────────┐          │
│      │                             │                             │          │
│      ▼                             ▼                             ▼          │
│  ┌─────────┐                 ┌─────────┐                  ┌─────────┐       │
│  │PAGERDUTY│                 │ SYSLOG  │                  │  CLOUD  │       │
│  │         │                 │         │                  │         │       │
│  │Incident │                 │ Forward │                  │ AWS/GCP │       │
│  │ mgmt    │                 │ to SIEM │                  │ Azure   │       │
│  └─────────┘                 └─────────┘                  └─────────┘       │
│                                                                              │
│  ┌─────────────────────────────────────────────────────────────────────┐    │
│  │                        CLOUD LOG SOURCES                            │    │
│  │                                                                     │    │
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐  │    │
│  │  │  AWS    │  │  Azure  │  │   GCP   │  │Office365│  │ GitHub  │  │    │
│  │  │CloudTrl │  │Activity │  │ Pub/Sub │  │ Audit   │  │ Audit   │  │    │
│  │  │GuardDuty│  │Sign-in  │  │         │  │ Logs    │  │ Logs    │  │    │
│  │  └─────────┘  └─────────┘  └─────────┘  └─────────┘  └─────────┘  │    │
│  └─────────────────────────────────────────────────────────────────────┘    │
│                                                                              │
└─────────────────────────────────────────────────────────────────────────────┘
```
