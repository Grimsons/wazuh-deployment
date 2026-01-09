# Wazuh Certificates

This directory contains SSL/TLS certificates for Wazuh components.

## Generating Certificates

Run the certificate generation script from the project root:

```bash
./generate-certs.sh
```

This will generate all required certificates based on your `group_vars/all.yml` configuration.

## Required Certificate Files

| File | Description |
|------|-------------|
| `root-ca.pem` | Root CA certificate |
| `root-ca-key.pem` | Root CA private key |
| `admin.pem` | Admin certificate (for indexer security init) |
| `admin-key.pem` | Admin private key |
| `indexer-1.pem` | Indexer node certificate (name matches `indexer_node_name`) |
| `indexer-1-key.pem` | Indexer node private key |
| `manager-1.pem` | Manager node certificate (name matches `manager_node_name`) |
| `manager-1-key.pem` | Manager node private key |
| `dashboard.pem` | Dashboard certificate |
| `dashboard-key.pem` | Dashboard private key |

## Multi-Node Deployments

For multi-node clusters, generate certificates for each node:

- Indexers: `indexer-1.pem`, `indexer-2.pem`, `indexer-3.pem`, etc.
- Managers: `manager-1.pem`, `manager-2.pem`, etc.

The certificate names must match the `indexer_node_name` and `manager_node_name` variables in your inventory.

## Using Custom Certificates

If using your own CA-signed certificates:

1. Place your certificates in this directory with the naming convention above
2. Ensure the certificate CN/SAN includes the node hostname and IP
3. All certificates must be signed by the same Root CA

## Security Note

Certificate files (*.pem) are gitignored and should NEVER be committed to version control.
