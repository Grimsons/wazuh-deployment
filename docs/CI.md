# CI/CD Pipeline

## Overview

The CI pipeline runs on GitHub Actions (`.github/workflows/ci.yml`) on every push/PR to `main`. It consists of 4 jobs plus an integration test.

## Jobs

### 1. Lint (`lint`)
- **yamllint** — validates all YAML files against `.yamllint`
- **ansible-lint** — runs `--profile production` on roles and playbooks

### 2. ShellCheck (`shellcheck`)
- Checks all shell scripts in the repository for syntax/security issues
- Severity: `error`

### 3. Ansible Syntax Check (`syntax-check`)
- Creates a minimal inventory and group_vars with test credentials
- Runs `ansible-playbook --syntax-check` on all playbooks
- **Test passwords**: stored as GitHub Secrets (`SYNTAX_CHECK_PASSWORD`, `SYNTAX_CHECK_CLUSTER_KEY`)

### 4. Molecule (`molecule`)
- Runs `molecule test` for each role in a matrix (5 roles)
- Each role is tested independently in Docker containers
- Idempotence is verified automatically by `molecule test`

### 5. Full-Stack Integration (`integration`)
- Runs only on push/PR to `main`
- Uses the `full-stack` molecule scenario to test end-to-end deployment
- Spins up indexer, manager, and dashboard in Docker

## Secrets Required

| Secret | Used By | Description |
|--------|---------|-------------|
| `SYNTAX_CHECK_PASSWORD` | Syntax check | Shared password for all vault vars in CI |
| `SYNTAX_CHECK_CLUSTER_KEY` | Syntax check | 32-char cluster key for manager cluster config |

## Cache Strategy

| Cache Key | Path | Invalidated By |
|-----------|------|----------------|
| `pip-v1-` + `requirements.yml` hash | `~/.cache/pip` | Bump `v1` suffix when `pip install` deps change |
| `molecule-v1-` + `requirements.yml` hash | `~/.cache/pip` | Same, for molecule job |
| `galaxy-` + `requirements.yml` hash | `~/.ansible` | Ansible Galaxy collection changes |

## Adding a New Role

1. Create `roles/<name>/molecule/default/molecule.yml` and `converge.yml`
2. Add `<name>` to the `molecule` job matrix in `ci.yml`
3. Run `cd roles/<name> && molecule test` locally first

## Testing Locally

```bash
# Lint
yamllint -c .yamllint .
ansible-lint --profile production roles/ playbooks/ site.yml

# Syntax check
ansible-playbook --syntax-check site.yml -i inventory/hosts.yml

# Molecule (single role)
cd roles/wazuh-indexer && molecule test

# Full integration
cd roles/wazuh-indexer && molecule test -s full-stack
```
