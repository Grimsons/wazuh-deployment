# Wazuh Deployment

An Ansible-based deployment toolkit for the Wazuh SIEM/XDR platform. This project automates the installation, configuration, and ongoing management of Wazuh Indexer, Manager, Dashboard, and Agent components across single-node or distributed environments.

Key features:

- **Interactive setup** via CLI wizard or TUI (with [gum](https://github.com/charmbracelet/gum))
- **Automated certificate generation** and credential management (Ansible Vault)
- **Bootstrap workflow** that provisions a dedicated deployment user with SSH key auth
- **Post-deployment lockdown** of the deployment user for security
- **SOCFortress community detection rules** (1000+ rules with MITRE ATT&CK mapping)
- **Operational playbooks** for backups, upgrades, health checks, certificate rotation, and more
- **Makefile** shortcuts for all common operations

## Documentation

This documentation is built with [mdBook](https://rust-lang.github.io/mdBook/). To build and serve locally:

```bash
# Build (output in book/)
./build.sh

# Serve at http://127.0.0.1:3000
./server.sh
```

For deployment instructions, start with the [Deployment Guide](getting-started/deployment.md) or the [Cheatsheet](cheatsheet.md).
