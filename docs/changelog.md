# Change Log

All notable changes to this fork will be documented in this file.

For upstream wazuh-ansible changes, see the [wazuh-ansible releases](https://github.com/wazuh/wazuh-ansible/releases).

## [1.1.0] - Security Review, Community Rules, and Hardening

### Added

- **SOCFortress Community Detection Rules** - Integrated 1000+ detection rules from [SOCFortress Wazuh-Rules](https://github.com/socfortress/Wazuh-Rules):
  - 13 Windows Sysmon rule sets (Events 1, 3, 6, 7, 10-15, 17, 18, 22) with MITRE ATT&CK mapping
  - Linux auditd detection rules (64 rules for syscall monitoring, privilege escalation, persistence)
  - Sysmon for Linux rules (14 rules)
  - Suricata IDS enrichment rules
  - YARA malware scan detection rules
  - Wazuh Manager and infrastructure health check rules
  - Active response action alert rules
  - PowerShell malicious command detection with CDB list matching
  - Custom decoders for auditd, Sysmon Linux, manager logs, and YARA
  - Malicious PowerShell CDB threat intelligence list
- **Custom Attack Detection Rules** (ID range 800100-800299):
  - Linux: reverse shell detection, credential dumping, container escape, SSH tunneling, ransomware indicators, SUID/SGID abuse, cron/systemd persistence, authorized_keys modification, reconnaissance commands, defense evasion, kernel module loading, LD_PRELOAD hijacking, data exfiltration
  - Windows: PowerShell event log monitoring with malicious pattern matching
- **Prometheus Alerting Rules** - Pre-built alert rules for Wazuh cluster health monitoring
- **Certificate Management Playbook** - Validation, rotation, and renewal with idempotent skip-if-valid logic
- **Canary/Staged Deployment** - Rolling deployment with health check gates between batches
- **Pre-flight Checks** - Comprehensive validation before deployment (connectivity, resources, versions)
- **Deployment with Rollback** - Automatic rollback point creation and restore capability
- **unlock-deploy-user.yml** - Playbook to unlock the deployment user before redeployments
- **scripts/migrate-from-main.sh** - Migration script for moving from main branch to versioned branches
- **scripts/lockdown-ansible-user.sh** - Script to restrict deployment user sudo access post-deploy
- **scripts/status.sh** - Quick status check of all Wazuh services across hosts
- **Makefile** - Shortcuts for all common operations (`make deploy`, `make health`, `make status`, etc.)
- **playbooks/setup-maintenance-cron.yml** - Automated maintenance scheduling (backups, log cleanup)
- **playbooks/system-update.yml** - OS-level package updates across managed hosts
- **playbooks/log-cleanup.yml** - Log rotation and cleanup for Wazuh components

### Changed

- **Modernized APT repository configuration** - Replaced deprecated `apt-key` with `/etc/apt/keyrings/` and `signed-by` across all Debian/Ubuntu roles (indexer, manager, dashboard, agent)
- **FIM frequency** - Default changed from 43200s (12h) to 21600s (6h) for faster detection
- **Auditd monitoring** - Enabled by default on Linux agents for syscall-level visibility
- **Rule ID ranges** - Renumbered project-specific custom rules from 100xxx to 800xxx to avoid conflicts with SOCFortress community rules

### Fixed

- **Security audit fixes** (~50 issues across CRITICAL/HIGH/MEDIUM/LOW severity):
  - Removed root shell bypass via sudo NOPASSWD rules (`/bin/bash`, `/usr/bin/python3`)
  - Fixed credentials baked into Python monitoring scripts (now uses EnvironmentFile)
  - Fixed YAML-unsafe password generation (`!#$` characters breaking vault syntax)
  - Fixed substring matching in grep (`grep "active"` catching "inactive")
  - Fixed path traversal bypass in single-pass `../` removal
  - Fixed unsafe array construction (`ARRAY=($VAR)` glob expansion)
  - Fixed template variable name mismatches in Prometheus exporters
  - Fixed missing input validation in setup scripts
- **Filebeat systemd unit** - Fixed reliability issues on hosts where filebeat failed to start
- **Go runtime crashes** - Fixed filebeat crashes caused by Go runtime memory issues
- **Fielddata fix for dashboard aggregation** - Fixed MITRE ATT&CK technique field aggregation failures in dashboard visualizations

### Security

- All monitoring exporter credentials moved from config files to systemd EnvironmentFile
- Sudo rules restricted to specific commands only (no shell access)
- Password generation excludes YAML-unsafe characters
- GPG key verification for package repositories
