# Wazuh 5.x readiness audit

Date: 2026-09-26
Branch: `upgrade/wazuh-5.0`

## Result

The shared deployment configuration makes `setup.sh` and `setup-tui.sh` version/profile driven. Both entry points accept `--config FILE`; command-line and environment values take precedence over the file. The local shell and Ansible checks are green after gating the remaining Filebeat operations in the full-site smoke test and system-update playbook.

This is not a production compatibility sign-off yet. A live Wazuh 5.x canary is still required.

## Verified locally

- `bats tests/lib/*.bats`: 172/172 passed.
- `bash -n` passed for the changed shell entry points and libraries.
- Ansible syntax checks passed for upgrade, health, alert, backup, restore, credential rotation, system update, canary, and full-site playbooks with the repository roles path.
- `setup.sh --help` exposes `--config FILE`.
- `setup-tui.sh --help` exposes `--config FILE` and `--check` passes with `gum` installed.
- The rule runner executes, but has no `.log` fixtures: 0/0 detections tested.
- Custom rules, decoders, CDB lists, SCA content, and agent-group content are present for deployment; live `analysisd` loading and representative detections remain unverified.

## Changes made during this audit

- `site.yml` now skips Filebeat service/output checks when `wazuh_use_filebeat` is false and reports `N/A (5.x)`.
- `playbooks/system-update.yml` now excludes Filebeat from manager stop/start loops when the version contract disables it.
- A regression test covers both Filebeat gates.

## Remaining release gates

1. Run the generated deployment in a reachable Docker daemon or isolated canary with a pinned Wazuh 5.x image/packages.
2. Verify manager/indexer/dashboard service health, API authentication, certificates, agent enrollment/upgrade, backups/restores, and rollback.
3. Load the custom rules/decoders/lists/SCA policies in `analysisd` and run representative log fixtures; record detection results.
4. Review remaining intentional 4.x examples and operational fallbacks, especially agent helper scripts and documentation, before changing the repository default from `4.14.5`.

The current runner has Docker installed but cannot access `/var/run/docker.sock`, so Docker execution is an environment blocker rather than a failed test.
