# Wazuh 5.0 Greenfield Support — Implementation Plan

## Goal

Add `wazuh_major_version`-based conditionals throughout the codebase to support
greenfield (fresh install) Wazuh 5.0 beta deployments alongside existing 4.14.5
stable deployments in a single, version-aware Ansible codebase.

## Motivation

Wazuh 5.0 introduces architectural changes vs 4.x:

| Area               | 4.x                                    | 5.0                                     |
|--------------------|----------------------------------------|-----------------------------------------|
| Repo URL           | `packages.wazuh.com/4.x/apt/`          | `packages-staging.xdrsiem.wazuh.info/pre-release/5.x/apt/` |
| GPG key            | `packages.wazuh.com/key/GPG-KEY-WAZUH` | `packages-staging.xdrsiem.wazuh.info/key/GPG-KEY-WAZUH` |
| Manager path       | `/var/ossec`                           | `/var/wazuh-manager`                    |
| Config file        | `/var/ossec/etc/ossec.conf`            | `/var/wazuh-manager/etc/wazuh-manager.conf` |
| Config format      | XML (`<ossec_config>`)                 | XML (same structure, `<indexer>` block replaces `<wodle name="indexer">`) |
| Indexer comms      | Filebeat 7.10.2                        | Native indexer-connector (built-in)     |
| Manager cert name  | `server.pem` / `server-key.pem`        | `manager.pem` / `manager-key.pem`       |
| Indexer security   | `securityadmin.sh` (or built-in script) | `indexer-security-init.sh` (built-in only) |
| Daemons            | Multiple separate daemons              | Monolithic `wazuh-manager`              |
| Agent ID 000       | Exists                                 | Removed                                 |
| OS user            | `wazuh`                                | `wazuh-manager`                         |
| OpenSearch version | 2.x                                    | 3.6.0                                   |

## Official Docs Reference

From https://documentation.wazuh.com/5.0-beta/ (verified):

- **5.0 DOES use repos** (staging repos at `packages-staging.xdrsiem.wazuh.info/pre-release/5.x/`).
  The direct-download approach in wazuh-ansible `main` is their own invention.
- **wazuh-manager.conf is XML** with `<ossec_config>` root — almost identical to
  4.x `ossec.conf`. Key structural difference: `<indexer>` block replaces the
  separate Filebeat config entirely.
- **Keystore tool**: `/var/wazuh-manager/bin/wazuh-manager-keystore -f indexer -k`
- **Cluster control**: `/var/wazuh-manager/bin/cluster_control -l`
- **OpenSearch**: 3.6.0, uses `cluster_initial_manager_nodes` instead of `cluster_initial_master_nodes`

These differences are deep enough that a simple path-swap won't suffice — we need
**strategy-level branching** where entire task files are conditionally included.

## Phases

### Phase 0: Variable Abstraction Layer

- Add `roles/vars/main.yml` with derived version variables
- Add path abstraction vars to `group_vars/all/main.yml`:
  - `wazuh_manager_install_path`
  - `wazuh_manager_config_path`
  - `wazuh_manager_certs_path`
  - `wazuh_manager_log_path`
  - `wazuh_manager_owner`
  - `wazuh_manager_group`
  - `wazuh_is_5x` — derived from version split
  - `wazuh_use_repos` — `true` for 4.x, `false` for 5.x
  - `wazuh_use_filebeat` — `true` for 4.x, `false` for 5.x
- **Prerequisite**: All other phases depend on these vars

### Phase 1: Version-Aware Repo URLs

5.0 uses the same apt/yum repo workflow as 4.x — just different URLs and GPG key.
No new download strategy needed.

- **`wazuh-manager`**, **`wazuh-indexer`**, **`wazuh-dashboard`**, and
  **`wazuh-agent`** defaults: make repo URLs version-aware by deriving from
  `wazuh_version` directly in each role's `defaults/main.yml`:

  ```yaml
  wazuh_repo_major_minor: "{{ wazuh_version.split('.')[0:2] | join('.') }}"
  wazuh_repo_major: "{{ wazuh_version.split('.')[0] }}.x"
  wazuh_repo_gpg_key: >-
    {{ 'https://packages-staging.xdrsiem.wazuh.info/key/GPG-KEY-WAZUH'
       if (wazuh_version.split('.')[0] == '5') and (wazuh_version is match('.*-.*'))
       else 'https://packages.wazuh.com/key/GPG-KEY-WAZUH' }}
  wazuh_repo_url_apt: >-
    {{ 'https://packages-staging.xdrsiem.wazuh.info/pre-release/5.x/apt/'
       if (wazuh_version.split('.')[0] == '5') and (wazuh_version is match('.*-.*'))
       else 'https://packages.wazuh.com/' + wazuh_repo_major + '/apt/' }}
  wazuh_repo_url_yum: >-
    {{ 'https://packages-staging.xdrsiem.wazuh.info/pre-release/5.x/yum/'
       if (wazuh_version.split('.')[0] == '5') and (wazuh_version is match('.*-.*'))
       else 'https://packages.wazuh.com/' + wazuh_repo_major + '/yum/' }}
  ```

  Any 5.x pre-release version (matching `*-*` like `5.0.0-beta2`) uses the
  staging repo; production releases (no hyphen) use the normal production repo
  pattern. The `repository.yml` and `install.yml` tasks remain completely
  unchanged — only the URL variables differ.

### Phase 2: Filebeat Guard (Manager)

- Guard the `filebeat.yml` include in `roles/wazuh-manager/tasks/main.yml`:
  ```yaml
  when:
    - wazuh_filebeat_enabled
    - wazuh_use_filebeat
  ```
- No 5.x equivalent needed — manager has native indexer-connector
- Keystore tasks in `configure.yml` are shared (same binary, different path)

### Phase 3: Config Templates (Manager)

Both 4.x and 5.0 use XML config with `<ossec_config>` root. Key differences:
- **4.x**: `ossec.conf` at `/var/ossec/etc/ossec.conf`; Filebeat via
  `filebeat.yml`; `<wodle name="indexer">` block.
- **5.0**: `wazuh-manager.conf` at `/var/wazuh-manager/etc/wazuh-manager.conf`;
  no Filebeat; `<indexer>` block directly specifies hosts/certs/keystore.

- Keep `ossec.conf.j2` for 4.x.
- Create `wazuh-manager.conf.j2` for 5.0 — structurally similar but:
  - `<indexer>` block replaces the separate Filebeat config
  - Certificate paths use `{{ wazuh_manager_install_path }}/etc/certs/`
  - Service user references use `{{ wazuh_manager_owner }}`
  - Keystore path uses `{{ wazuh_manager_install_path }}/bin/wazuh-keystore`
- Dispatch in `configure.yml`:
  ```yaml
  - name: Deploy config from template
    ansible.builtin.template:
      src: "{{ 'wazuh-manager.conf.j2' if wazuh_is_5x else 'ossec.conf.j2' }}"
      dest: "{{ wazuh_manager_config_file }}"
      owner: "{{ wazuh_manager_owner }}"
      group: "{{ wazuh_manager_group }}"
      mode: '0640'
      backup: true
  ```
- Replace all hardcoded `/var/ossec/` paths in `configure.yml` with
  `{{ wazuh_manager_install_path }}`:
  - Keystore: `{{ wazuh_manager_install_path }}/bin/wazuh-keystore`
  - Config validation: `{{ wazuh_manager_install_path }}/bin/wazuh-analysisd -t`
  - Rules/decoders directories: `{{ wazuh_manager_install_path }}/etc/rules`
  - Permission fixup paths

### Phase 4: Indexer Security Init

- Simplify `roles/wazuh-indexer/tasks/security_init.yml`:
  - 4.x: current dual-path (try built-in, fall back to `securityadmin.sh`)
  - 5.x: single `indexer-security-init.sh` call

### Phase 5: Health Checks

- `playbooks/health-check.yml` — version-aware:
  - Guard Filebeat check with `when: not wazuh_is_5x`
  - Replace `/var/ossec/bin/agent_control` → `{{ wazuh_manager_install_path }}/bin/agent_control`
  - Replace `/var/ossec/logs/ossec.log` → `{{ wazuh_manager_install_path }}/logs/ossec.log`
  - Replace `/var/ossec/queue/` → `{{ wazuh_manager_install_path }}/queue/`
  - Replace `/var/ossec/bin/wazuh-control` → `{{ wazuh_manager_install_path }}/bin/wazuh-control`
  - E2E test (`wazuh-logtest-legacy`, agent ID `000`): 4.x only

### Phase 6: Pre-Flight Checks

- `playbooks/pre-flight-checks.yml`:
  - Guard `artifacts.elastic.co` DNS check with `when: not wazuh_is_5x`
  - Skip apt/yum update tests for 5.x (no repos)
  - Replace `/var/ossec/bin/wazuh-control info` → `{{ wazuh_manager_install_path }}/bin/wazuh-control info`

### Phase 7: Agent Role

- `roles/wazuh-agent/tasks/linux.yml`:
  - Guard repo setup with `when: not wazuh_is_5x`
  - Add 5.x package download path
  - Agent enrollment: `/var/ossec/etc/authd.pass` path stays (agent-side structure unchanged in 5.x)
  - Agent config: `ossec.conf` path stays (agents keep XML config in 5.x)

### Phase 8: Playbook & Certificate Updates

- **Certificate naming**: Official 5.0 uses `manager.pem`/`manager-key.pem`
  instead of `server.pem`/`server-key.pem`. Our `certs.yml` currently names
  manager certs `server.pem` — add version-conditional cert name variable:
  ```yaml
  wazuh_manager_cert_name: "{{ 'manager' if wazuh_is_5x else 'server' }}"
  ```
- **`site.yml`**: No structural change needed — roles stay the same, repo
  URLs flow from defaults.
- **`upgrade.yml`**: Update version regex to accept `5.0.0-*` (pre-release
  identifiers like `5.0.0-beta2`). Update: `^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9]+)?$`
- **`generate-certs.sh`**: May need to accept 5.x `config.yml` format
  (uses `cluster_initial_manager_nodes` instead of `cluster_initial_master_nodes`).
  Our script uses our own `certs.yml` config file, not upstream `config.yml`,
  so impact is minimal.
- **`playbooks/docker-bootstrap.yml`**: No changes needed.

### Phase 9: Docker Profile & Setup

- `lib/profiles.sh`: Add `WAZUH_VERSION` env var to docker profile (default `4.14.5`)
- `setup.sh`: Wire version selection into repo URL generation
  - Don't need 5.x repo URLs at all (no repos in 5.x)
  - GPG key URL stays the same (`packages.wazuh.com/key/GPG-KEY-WAZUH`)
- `docker-compose.yml`: Add version env var, potentially a `docker-compose-5.yml` variant
- `Makefile`: `docker-setup` target accepts `WAZUH_VERSION=5.0.0-beta2`

### Phase 10: Certificate Path Abstraction

- `group_vars/all/main.yml`: `wazuh_manager_certs_path` becomes version-aware
- `roles/wazuh-manager/tasks/certificates.yml`: Use abstracted path
- `roles/wazuh-manager/tasks/filebeat.yml`: References `/var/ossec/etc/certs/` — only runs on 4.x so no change needed

## Execution Order

```
Phase 0 ──► Phase 1 ──► Phase 2 ──► Phase 3 ──► Phase 4
                │                                          │
                ▼                                          ▼
          Phase 7 ──► Phase 8 ──► Phase 5 ──► Phase 6
                                        │
                                        ▼
                                   Phase 9 ──► Phase 10
```

## Files Modified / Created

| Phase | Files |
|-------|-------|
| 0 | `roles/vars/main.yml` **(new)**, `group_vars/all/main.yml` |
| 1 | `roles/wazuh-manager/defaults/main.yml`, `roles/wazuh-indexer/defaults/main.yml`, `roles/wazuh-dashboard/defaults/main.yml`, `roles/wazuh-agent/defaults/main.yml` |
| 2 | `roles/wazuh-manager/tasks/main.yml` |
| 3 | `roles/wazuh-manager/templates/wazuh-manager.conf.j2` **(new)**, `roles/wazuh-manager/tasks/configure.yml`, `roles/wazuh-manager/tasks/api.yml` |
| 4 | `roles/wazuh-indexer/tasks/security_init.yml` |
| 5 | `playbooks/health-check.yml` |
| 6 | `playbooks/pre-flight-checks.yml` |
| 7 | `roles/wazuh-agent/tasks/linux.yml` (minimal — repo URLs flow from defaults) |
| 8 | `group_vars/all/main.yml` (cert names), `playbooks/upgrade.yml`, `playbooks/certificate-management.yml` |
| 9 | `lib/profiles.sh`, `setup.sh`, `Makefile` |
| 10 | `group_vars/all/main.yml`, `roles/wazuh-manager/tasks/certificates.yml` |

## Testing Strategy

### Lint / Syntax
- `make lint` after every phase — catches Jinja errors early

### Unit (dry-run)
- `make deploy-check` against existing 4.x inventory — verifies no regression after each phase

### Integration (4.x)
1. Deploy full 4.x stack to Docker containers: `make deploy`
2. Verify all 3 components healthy: `make health`
3. Deploy agent: `make deploy-agent`
4. Verify agent shows active: `make health -e "check_agents=true"`

### Integration (5.0 beta)
1. After Phase 0-3: deploy 5.0.0-beta2 to fresh Docker containers
2. Verify install completes, manager starts, API responds
3. After Phase 4: verify indexer security initialized, cluster healthy
4. After Phase 7: deploy 5.0 agent, verify enrollment
5. Run `make health` across all nodes
6. Verify alert flow with end-to-end test

### Regression
- After all phases complete: full 4.14.5 deployment from scratch
- All health checks pass
- No unexpected changes in generated configs

## Key Risks

1. **Beta docs are light**: Some areas (agent config, `wazuh-manager.conf` full
   schema) still marked "under construction." wazuh-ansible `main` may be needed
   as supplementary reference.
2. **Pre-release repos may change**: The staging repo URL scheme could differ
   between beta versions. Pin to `packages-staging.xdrsiem.wazuh.info/pre-release/5.x/`.
3. **wazuh-ansible divergence**: Their `main` branch no longer supports 4.x,
   and they use direct-download instead of repos. We own backward compat entirely.
4. **Beta stability**: `5.0.0-beta2/3` may have breaking changes between
   releases. Pin to a specific version, absorb upstream changes deliberately.
5. **Certificate naming**: Official 5.0 uses `manager.pem` not `server.pem`.
   If we rename, 4.x cert generation breaks. Keep both paths version-conditional.
6. **Agent 5.0 behavior**: Agents still use XML `ossec.conf` in 5.0, but
   enrollment may differ (no agent ID `000`). Needs verification.
