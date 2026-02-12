# Compatibility

This section outlines the supported platforms, versions, and dependencies for deploying Wazuh using this deployment toolkit. Ensuring compatibility is essential for a successful deployment.

## Version Compatibility Matrix

### Wazuh Component Versions

| This Toolkit | Wazuh Version | OpenSearch | Filebeat | Notes |
|--------------|---------------|------------|----------|-------|
| 1.x          | 4.14.x        | 2.11.x     | 7.10.2   | Current stable |
| 1.x          | 4.13.x        | 2.11.x     | 7.10.2   | Supported |
| 1.x          | 4.12.x        | 2.11.x     | 7.10.2   | Supported |

### Control Node Requirements

| Component | Minimum Version | Recommended Version | Notes |
|-----------|-----------------|---------------------|-------|
| Ansible   | 2.12            | 2.16+               | ansible-core |
| Python    | 3.8             | 3.10+               | Required for Ansible |
| Bash      | 4.0             | 5.0+                | For setup scripts |
| gum       | 0.10            | 0.14+               | Optional, for TUI |

### Ansible Collections

| Collection | Minimum Version | Purpose |
|------------|-----------------|---------|
| ansible.posix | 1.4.0 | POSIX system management |
| community.general | 6.0.0 | General purpose modules |

Install required collections:
```bash
ansible-galaxy collection install ansible.posix community.general
```

### Target Operating Systems

#### Server Components (Indexer, Manager, Dashboard)

| OS Family | Distribution | Versions | Architecture |
|-----------|--------------|----------|--------------|
| Debian    | Ubuntu       | 20.04, 22.04, 24.04 | x86_64 |
| Debian    | Debian       | 10, 11, 12 | x86_64 |
| RHEL      | RHEL/CentOS  | 8, 9 | x86_64 |
| RHEL      | Rocky Linux  | 8, 9 | x86_64 |
| RHEL      | AlmaLinux    | 8, 9 | x86_64 |
| RHEL      | Amazon Linux | 2, 2023 | x86_64 |
| Arch      | Arch Linux   | Rolling | x86_64 |

#### Agent Hosts

| OS | Versions | Architecture | Notes |
|----|----------|--------------|-------|
| Ubuntu | 18.04+ | x86_64, arm64 | |
| Debian | 10+ | x86_64, arm64 | |
| RHEL/CentOS | 7, 8, 9 | x86_64, arm64 | |
| Rocky/Alma | 8, 9 | x86_64, arm64 | |
| Amazon Linux | 2, 2023 | x86_64, arm64 | |
| Arch Linux | Rolling | x86_64 | |
| Windows | 10, 11, Server 2016+ | x86_64 | Via Ansible WinRM |
| macOS | 11+ | x86_64, arm64 | Intel and Apple Silicon |

### Hardware Requirements

| Component | CPU Cores | RAM (Min) | RAM (Recommended) | Disk |
|-----------|-----------|-----------|-------------------|------|
| Indexer   | 2         | 4 GB      | 8 GB              | 50 GB SSD |
| Manager   | 2         | 2 GB      | 4 GB              | 20 GB |
| Dashboard | 2         | 2 GB      | 4 GB              | 10 GB |
| Agent     | 1         | 512 MB    | 1 GB              | 1 GB |
| All-in-One| 4         | 8 GB      | 16 GB             | 100 GB SSD |

### Network Ports

| Port | Protocol | Component | Purpose |
|------|----------|-----------|---------|
| 22   | TCP      | All       | SSH (Ansible) |
| 443  | TCP      | Dashboard | HTTPS UI |
| 1514 | TCP/UDP  | Manager   | Agent events |
| 1515 | TCP      | Manager   | Agent enrollment |
| 1516 | TCP      | Manager   | Manager cluster |
| 9200 | TCP      | Indexer   | REST API |
| 9300 | TCP      | Indexer   | Cluster transport |
| 55000| TCP      | Manager   | Wazuh API |
| 9114 | TCP      | Indexer   | Prometheus metrics (optional) |
| 9115 | TCP      | Manager   | Prometheus metrics (optional) |

Also, review the official Ansible documentation to ensure your control node meets the compatibility requirements. You can find more information at the following link: [Ansible documentation - Release and Maintenance](https://docs.ansible.com/ansible/latest/reference_appendices/release_and_maintenance.html)

## Central Components Compatibility

To install the central components of Wazuh (indexer, manager, and dashboard), it is necessary to use a machine running a Linux operating system. The installation of Wazuh via Ansible is compatible with the two major Linux distribution families: Debian and Red Hat.

For detailed information on the compatibility of Wazuh components, please refer to the Wazuh documentation:

- Packages List: [Wazuh Packages List](https://documentation.wazuh.com/current/installation-guide/packages-list.html)

## Agents Compatibility

Wazuh agents are compatible with a wide variety of operating systems. However, the installation and enrollment of agents using Ansible are only supported on Linux, Windows, and macOS operating systems.

For more detailed information on Wazuh agents’ compatibility, please refer to the Wazuh documentation:

- Compatibility Matrix: [Wazuh Compatibility Matrix](https://documentation.wazuh.com/current/user-manual/capabilities/system-inventory/compatibility-matrix.html)
- Packages List: [Wazuh Packages List](https://documentation.wazuh.com/current/installation-guide/packages-list.html)

## Notes on Compatibility

- Ensure the target systems meet the minimum hardware and software requirements for Wazuh.
- Verify that the network configuration allows proper communication between Wazuh components (e.g., manager, agents, and dashboard).
- Refer to the Wazuh documentation for detailed information on the [Architecture](https://documentation.wazuh.com/current/getting-started/architecture.html) and network requirements.
- For distributed deployments, ensure all nodes are running compatible operating systems and Wazuh versions.
