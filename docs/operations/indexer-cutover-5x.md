# Indexer 4.x → 5.x cutover

Replaces the rolling in-place indexer upgrade, which does not exist across this
boundary. A Wazuh indexer 4.x cluster cannot be upgraded to 5.x, and its data
cannot be migrated. Crossing majors is a blue/green replacement: build a new
5.x cluster, move ingest to it, and keep the 4.x cluster read-only for
historical queries.

This runbook replaces the indexer sections of `docs/operations/upgrade.md`.
`playbooks/upgrade.yml` and `playbooks/restore.yml` both refuse a cross-major
indexer operation and point here.

## Why there is no upgrade path

| Concern | Consequence |
| --- | --- |
| Engine | 5.x is OpenSearch 3.x, 4.x is OpenSearch 2.x. The 3.x base reads Lucene segments from its own and the immediately preceding major only, so 4.x shards cannot be opened. |
| Index schema | 5.x ships new schemas and templates under `wazuh-events-v5`, `wazuh-findings-v5` and `wazuh-states-v5`. Field names, types and routing differ from 4.x in ways `_reindex` cannot transform losslessly. |
| Configuration | `cluster.initial_master_nodes` became `cluster.initial_cluster_manager_nodes`. `compatibility.override_main_response_version` was removed — a 5.x node that still defines it will not boot. The anomaly detection, asynchronous search, ML Commons, k-NN, SQL and neural search plugins are no longer shipped, so their settings are dead. |
| Security | 5.x ships a different set of internal users, roles and index patterns. `whitelist.yml` is now `allowlist.yml`. |
| Data | No in-place upgrade, no snapshot restore, no `_reindex`. |

Consequence for planning: retention only applies to data written **after** the
cutover. Anything you need to keep from before must stay queryable on the 4.x
cluster, and you decide when that cluster is decommissioned.

## Before you start

- The 4.x cluster's configuration, security configuration and certificates,
  backed up (`playbooks/backup.yml`).
- A supported host for 5.x, checked against the upstream compatibility matrix.
- 5.x packages.
- Enough disk for a second full cluster. Two clusters exist side by side for
  the whole cutover.
- A decision on how long the 4.x cluster is retained.

## Phase 1 — Build the 5.x cluster

Deploy 5.x on new hosts, with a different cluster name and no shared data path
with the 4.x nodes. Keep them on separate networks or hosts so nothing can
replicate between them; a 5.x node joining a 4.x cluster is not a state the
software supports.

```bash
# group_vars/all/main.yml
wazuh_version: "5.0.0"
wazuh_indexer_cluster_name: wazuh-cluster-5x
```

Set the built-in user passwords before the node is reachable from anywhere
untrusted. 5.x ships every internal user with a hash of its own username and
nothing rotates it, so `wazuh-admin`/`wazuh-admin` is admin-level access:

```yaml
# group_vars/all/vault.yml
wazuh_indexer_5x_user_passwords:
  admin: "{{ vault_indexer_admin_password }}"
  wazuh-manager: "{{ vault_indexer_manager_password }}"
  wazuh-admin: "{{ vault_indexer_wazuh_admin_password }}"
  wazuh-readonly: "{{ vault_indexer_readonly_password }}"
```

The 5.x password tool enforces 8–64 characters, at least one uppercase letter,
one lowercase letter, one digit, and one of `.` `*` `+` `?` `-`. A 4.x vault
password ending in `!` or `#` is rejected, so expect to change these. The role
checks the policy before invoking the tool and reports which user failed.

```bash
ansible-playbook playbooks/wazuh-indexer.yml -i inventory/hosts.yml
```

Certificate paths are not assumed by the role. It parses the rendered
`opensearch.yml` and deploys each certificate to the path the config actually
names, so a customised `wazuh_indexer_certs_path` works without editing the
template. One exception is unavoidable: `wazuh-passwords-tool.sh` authenticates
with the admin certificate at `/etc/wazuh-indexer/certs/admin.pem` and cannot be
pointed elsewhere, so that one file has to live there for password rotation to
work. The role fails with that message rather than letting the tool fail with
an authentication error.

## Phase 2 — Validate the 5.x cluster

Read-only. It checks the engine version, cluster health, that the security
index is actually readable, that every managed index family has an ISM policy in
the `open` state, shard assignment, and a document read per family.

```bash
ansible-playbook playbooks/indexer-cutover.yml -i inventory/hosts.yml \
  --tags validate-blue -e "cutover_count_docs=true"
```

Do not continue past a failure here. The checks that matter most:

- **`OpenSearch 3.x`** — confirms the node really is a 5.x indexer and not a 4.x
  node with 5.x packages.
- **Security index readable** — an index that exists but is empty or left over
  from a failed `indexer-security-init.sh` authenticates against the wrong
  configuration and writes nothing.
- **ISM policies `open`** — a policy in a failed phase has stopped managing its
  indices, so rollover and retention are off for that family and it will
  eventually hit the 1000 open index limit.

## Phase 3 — Move ingest

Point the Wazuh Manager at the 5.x cluster and confirm data arrives. Do this
before decommissioning anything: the Manager is the only writer, so this is the
step that actually transfers responsibility for new data.

```
Wazuh Manager filebeat output → wazuh-indexer-5x:9200
```

Watch for a full rollover cycle (daily, per the default settings) before calling
the cutover done. A cluster can look healthy on day one and still be missing a
broken ISM policy that only surfaces when rollover first fires.

## Phase 4 — Retain 4.x read-only

Only needed if you have to query pre-cutover history. A 5.x dashboard cannot
read 4.x indices, so users needing history keep a dashboard pointed at the 4.x
cluster.

Stop ingest into 4.x first, then make the cluster read-only so nothing can write
to it by accident:

```bash
curl -sk -u admin:$PASSWORD -X PUT \
  https://4x-indexer:9200/_cluster/settings \
  -H 'Content-Type: application/json' -d '{
  "persistent": {"cluster.routing.allocation.enable": "none"}
}'
```

Confirm no Manager is still ingesting:

```bash
ansible-playbook playbooks/indexer-cutover.yml -i inventory/legacy-hosts.yml \
  --tags validate-legacy
```

Plan a decommission date from your retention policy. When it arrives, remove the
4.x hosts from the inventory and decommission them.

## Field renames to expect in dashboards

5.x uses new schemas, so field names that a 4.x dashboard aggregated on may not
exist under the same name. The clearest case in Wazuh's own event schema is the
actor identity: 4.x `data.user` became `data.dstuser` for the destination
account, with `data.srcuser` for the source. An aggregation on the old path
returns nothing rather than an error, so check saved objects that group by
actor after the cutover.

## What this procedure does not do

- It does not migrate data. There is no path to do so.
- It does not roll back by restoring into 5.x. To go back, repoint ingest at
  the 4.x cluster, which is still there and still read-only. Restore it to
  writable first (`cluster.routing.allocation.enable: primaries`).
- It does not reuse 4.x certificates automatically. Certificates are carried
  over, but every `plugins.security.ssl.*` path has to be checked against the
  5.x layout; do not copy `opensearch.yml` itself.

## Known risks

- **ISM action compatibility is unverified against a live 5.0 indexer.** The
  policies this repository creates for 5.x use `rollover`, `replica_count`,
  `force_merge`, `index_priority`, `read_only`, `close` and `delete`. These are
  ISM actions carried from 4.x and are expected to be valid in OpenSearch 3.x,
  but that has not been confirmed on a real 5.x cluster, and an unknown action
  puts a policy into the `failed` phase. `--tags validate-blue` checks every
  policy's phase, so run it against a real 5.x cluster before the cutover and
  treat a non-`open` phase as a blocker.
- **The 5.x system index list is taken from the 5.x documentation, not observed
  on a node.** `wazuh_indexer_system_indices_5x` lists the content-manager
  bookkeeping indices and `.wazuh-internal-state`. `.wazuh-settings` is
  deliberately excluded: it is a normal index whose access the shipped roles
  grant explicitly, and declaring it a system index would override those grants.
  If the 5.x distribution adds a plugin that owns indices, add them.
- **The 4.x history is only as available as the 4.x cluster.** Nothing in the
  5.x cluster can serve it.

## Related

- `playbooks/indexer-cutover.yml` — the validation used above.
- `roles/wazuh-indexer/tasks/index_management_5x.yml` — the 5.x ISM policies and
  index families.
- `roles/wazuh-indexer/tasks/security_users_5x.yml` — password rotation.
- `docs/operations/upgrade.md` — in-place upgrades, same major only.
