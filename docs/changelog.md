# Change Log

All notable changes to this fork will be documented in this file.

For upstream wazuh-ansible changes, see the [wazuh-ansible releases](https://github.com/wazuh/wazuh-ansible/releases).

## [1.2.0] - Docker Environment, Certificate Fixes, and Keystore Management

### Added

- **Docker Test Environment** — Full Docker-based local development environment:
  - `docker-compose.yml`: systemd containers for indexer, manager, dashboard, agent
  - `docker-bootstrap.yml`: bootstrap playbook for Docker container SSH setup
  - `inventory/docker-hosts.yml`: pre-configured inventory for Docker containers
  - Docker profile in `setup-tui.sh` and `lib/profiles.sh`
  - `make setup-docker`, `make check-docker`, `make docker-setup` targets
- **Keystore Credential Management** — New `roles/wazuh-manager/tasks/keystore.yml`:
  - Idempotent storage of indexer passwords in Wazuh keystore
  - Conditional `wazuh-manager` restart when credentials change
  - Stale hash cleanup on package reinstall
- **Pre-Commit Hook** — `.githooks/pre-commit` that rejects commits with unencrypted `vault.yml`
- **`make setup-hooks`** — Configures `.githooks/` as the git hooks path (auto-run by `make check`)
- **Implementation Plan** — `docs/implementation-plan-5.0.md`: phased Wazuh 5.0 greenfield support plan

### Changed

- **Certificate Naming** — Dashboard certificate CN changed from `dashboard` to `dashboard-1`:
  - `setup.sh`, `setup-tui.sh`, `generate-certs.sh`, `scripts/migrate-from-main.sh`
  - `dashboard_node_name` variable added to inventory generation (indexed loop)
  - All dashboard cert references use `{{ dashboard_node_name | default("dashboard-1") }}`
- **Vault Password File** — Makefile now passes `--vault-password-file .vault_pass.sh` explicitly on all `ansible-playbook` calls (20 targets), because `ansible.cfg` is gitignored and generated per-environment
- **Container Networking** — `wazuh_is_container` flag enables `wazuh_indexer_network_host: 0.0.0.0`, `wazuh_dashboard_host: 0.0.0.0` bind for Docker containers
- **Binary Prefix** — `wazuh_manager_binary_prefix: "wazuh-"` default in `roles/wazuh-manager/defaults/main.yml`
- **Config File Selection** — `wazuh_manager_config_file` now selects `ossec.conf` for 4.x, `wazuh-manager.conf` for 5.x via `wazuh_is_5x` flag
- **Certificate Paths** — Source cert path in `site.yml` pre_tasks made absolute (`{{ playbook_dir }}/files/certs`); CN validation added after cert copy to all three `certificates.yml` files
- **Agent Role** — Expanded `linux.yml` with additional syscollector and enrollment hardening; updated `ossec.conf.j2` template

### Fixed

- **Root CA Mismatch** — Fixed inconsistency where manager's root CA differed from indexer/dashboard (prevented Filebeat → Indexer TLS)
- **Keystore Prompts** — Guarded unguarded prompts in Backup and Log Cleanup sections of `setup-tui.sh`
- **Skip-if-Set Logic** — `prompt_with_default()` and `prompt_yes_no()` now skip already-configured values in setup scripts
- **Config Path Guard** — Fixed `default(omit)` filter for `wazuh_manager_config_file` to prevent undefined variable errors
- **`.gitignore` Additions** — Added `.vault_pass.sh`, `.ansible/`, `.opencode/`, `**/files/certs/*.pem` to prevent accidental commits

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
