# Dashboard saved-object migration to Wazuh 5.x

Wazuh 5.0 has no automatic 4.x upgrade path. OpenSearch Dashboards 3.x also
does not make a 4.x saved-object export portable: index-pattern IDs and field
references are part of dashboards, visualizations, and searches. Treat the
4.x dashboard as a source to inventory, export, manually revalidate, and then
import into the new 5.x dashboard.

## What is in the repository

The authoritative inventory is
`roles/wazuh-dashboard/vars/main.yml`:

- `wazuh_dashboard_5x_index_patterns` lists the patterns provisioned by the
  Wazuh 5.x plugin and the expected time field for each family.
- `wazuh_dashboard_4x_index_pattern_disposition` records every 4.x pattern
  previously created by this role and whether it is retired or replaced.
- `wazuh_dashboard_5x_index_pattern_remap` is the safe starting point for
  imported custom objects; it is not a substitute for panel-by-panel review.

The 5.x role never creates plugin-owned patterns. It reads each saved object,
checks its title, time field, and backing index, and fails if a custom object
still refers to a retired 4.x pattern. Set
`wazuh_dashboard_verify_saved_objects=true` to enable the reference check.

## Export and revalidate

Run the helper from a machine that can reach the dashboard. Use an environment
variable for the password so it is not stored in shell history:

```bash
export WAZUH_DASHBOARD_URL=https://dashboard.example.test:443
export WAZUH_DASHBOARD_USER=admin
export WAZUH_DASHBOARD_PASSWORD='...'
export WAZUH_DASHBOARD_OLD_EXPORT=dashboard-4x.json

scripts/dashboard-saved-objects.sh export --insecure --output "$WAZUH_DASHBOARD_OLD_EXPORT"
scripts/dashboard-saved-objects.sh resolve --file "$WAZUH_DASHBOARD_OLD_EXPORT" \
  --output dashboard-5x-resolved.json
```

The export excludes objects whose description starts with `Provided by Wazuh`.
Those are plugin-owned and are recreated by the 5.x health check. Do not pass
`--include-wazuh` unless comparing a vendor export; importing those objects can
overwrite the 5.x panels with stale 4.x references.

For every retained dashboard, visualization, and search:

1. Open the object in Dashboard Management and confirm that every reference
   resolves to a 5.x pattern.
2. Choose the correct successor family. Alerts split into events and findings;
   monitoring splits into metrics families; statistics splits into agent state.
3. Rebuild queries and aggregations for changed fields. In particular,
   `rule.level` is now a severity string, not the 4.x integer scale.
4. Confirm the time field is `@timestamp` only for event/metric families. State
   families intentionally have no time field.
5. Open each dashboard in a browser with representative 5.x data and verify
   that panels load, time filters change results, and drilldowns work. This is
   a QA step; Ansible/API checks do not prove visual rendering.

Import only after this review:

```bash
scripts/dashboard-saved-objects.sh import --insecure \
  --file dashboard-5x-resolved.json
ansible-playbook site.yml --tags dashboard \
  -e wazuh_is_5x=true -e wazuh_dashboard_verify_saved_objects=true
```

An import response containing any `errors` is a failed migration. Do not
delete the source export; fix the named object and repeat the resolve/review.

## Retired objects and replacements

| 4.x pattern | 5.x disposition | Action |
| --- | --- | --- |
| `wazuh-alerts-*` | retired; findings/events | Rebuild rule panels on `wazuh-findings-v5*` or event panels on `wazuh-events-v5*`. |
| `wazuh-monitoring-*` | retired; metrics families | Select the matching `wazuh-metrics-*` family; there is no one-to-one replacement. |
| `wazuh-statistics-*` | retired; agent state | Rebuild on `wazuh-agent-stats*` or `wazuh-agent-config*`; old time ranges do not carry over. |
| `wazuh-archives-*` | retired; no dashboard successor | Keep only on the read-only 4.x cluster if historical archive views are required. |

## Rollback

Saved-object rollback is independent of the indexer cutover. Keep the original
4.x export and a pre-import 5.x export. If the import causes a bad dashboard,
restore the pre-import 5.x file:

```bash
scripts/dashboard-saved-objects.sh rollback --insecure \
  --file dashboard-5x-before-import.json
```

If the 5.x dashboard itself is unhealthy, stop the dashboard deployment and
return traffic to the known-good 4.x dashboard backed by the read-only 4.x
cluster. Do not restore 4.x saved objects into 5.x blindly: that recreates the
retired pattern references. After rollback, rerun the browser checks and keep
the failed export and import response with the change record.
