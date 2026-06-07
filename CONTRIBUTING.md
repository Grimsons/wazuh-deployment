# Contributing

## Quick Start

```bash
# Clone and set up
git clone <repo>
cd wazuh-deployment
make setup

# Run all linters locally
ansible-lint roles/ playbooks/ site.yml
yamllint -c .yamllint .
shellcheck --severity=error scripts/*.sh setup*.sh

# Run syntax check
ansible-playbook site.yml --syntax-check

# Run molecule tests for a specific role
cd roles/wazuh-indexer && molecule test
cd roles/wazuh-manager && molecule test

# Run all tests
make test
```

## Pull Request Checklist

- [ ] `yamllint` passes with no errors
- [ ] `ansible-lint --profile production` passes
- [ ] `shellcheck --severity=error` passes on all `.sh` files
- [ ] `ansible-playbook --syntax-check` passes on `site.yml` and all playbooks
- [ ] Molecule tests pass for affected roles (`molecule test`)
- [ ] No plaintext secrets in YAML files (use `{{ vault_* }}` variables)
- [ ] New variables have defaults in `defaults/main.yml`
- [ ] New playbooks are documented in `docs/SUMMARY.md`

## Versioning

The current Wazuh version is defined in `VERSION.json`. Update this file when upgrading.

## Testing

- Each role (except utility roles) has a Molecule scenario under `molecule/default/`
- The `full-stack` scenario tests cross-role integration
- Environment variables containing `CI-TEST-ONLY` in comments are test defaults — never use in production

## Secrets

Always use Ansible Vault for credentials. See `group_vars/all/vault.yml.example` for the required structure.
