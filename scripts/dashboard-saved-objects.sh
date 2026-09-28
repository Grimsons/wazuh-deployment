#!/usr/bin/env bash
# Export, inspect, remap, import, and roll back custom OSD saved objects.
#
# Wazuh 5.x owns its built-in objects. This helper deliberately operates only
# on dashboard, visualization, search, and index-pattern objects supplied by
# the operator; use --include-wazuh to override that safety filter explicitly.
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: dashboard-saved-objects.sh <command> [options]

Commands:
  inventory       List configured 4.x patterns and their 5.x disposition
  export          Export custom saved objects from an OSD 3.x dashboard
  resolve         Remap 4.x index-pattern references in an export file
  import          Import a resolved export into an OSD 3.x dashboard
  rollback        Import a previously exported backup file

Connection options:
  --url URL       Dashboard URL (default: $WAZUH_DASHBOARD_URL)
  --user USER     Dashboard user (default: $WAZUH_DASHBOARD_USER)
  --password VAR  Name of an environment variable containing the password
  --file FILE     Export/import JSON file
  --output FILE   Export output file (default: dashboard-export-<timestamp>.ndjson)
  --include-wazuh Include objects marked "Provided by Wazuh"
  --insecure      Disable TLS certificate verification
EOF
}

die() { echo "dashboard-saved-objects: $*" >&2; exit 1; }
command -v curl >/dev/null || die "curl is required"
command -v jq >/dev/null || die "jq is required"

command_name="${1:-}"
[[ -n "$command_name" ]] || { usage; exit 2; }
[[ "$command_name" == "-h" || "$command_name" == "--help" ]] && { usage; exit 0; }
shift

dashboard_url="${WAZUH_DASHBOARD_URL:-}"
dashboard_user="${WAZUH_DASHBOARD_USER:-admin}"
password_var="WAZUH_DASHBOARD_PASSWORD"
input_file=""
output_file=""
include_wazuh=false
curl_tls=()

while (($#)); do
  case "$1" in
    --url) dashboard_url="${2:?missing URL}"; shift 2 ;;
    --user) dashboard_user="${2:?missing user}"; shift 2 ;;
    --password) password_var="${2:?missing password variable}"; shift 2 ;;
    --file) input_file="${2:?missing file}"; shift 2 ;;
    --output) output_file="${2:?missing output file}"; shift 2 ;;
    --include-wazuh) include_wazuh=true; shift ;;
    --insecure) curl_tls+=(-k); shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

if [[ "$command_name" == export || "$command_name" == import || "$command_name" == rollback ]]; then
  [[ -n "$dashboard_url" ]] || die "set WAZUH_DASHBOARD_URL or pass --url"
  [[ -n "${!password_var:-}" ]] || die "set password variable $password_var"
fi

api() {
  local method="$1" endpoint="$2" body="${3:-}"
  local args=(-sS "${curl_tls[@]}" -u "$dashboard_user:${!password_var}" -H 'osd-xsrf: true' -H 'Content-Type: application/json' -X "$method")
  [[ -n "$body" ]] && args+=(--data-binary "$body")
  curl "${args[@]}" "$dashboard_url$endpoint"
}

custom_filter() {
  if [[ "$include_wazuh" == true ]]; then
    cat
  else
    jq 'del(.saved_objects[]? | select((.attributes.description // "") | startswith("Provided by Wazuh")))'
  fi
}

case "$command_name" in
  inventory)
    sed -n '/^wazuh_dashboard_4x_index_pattern_disposition:/,/^# ═/p' \
      roles/wazuh-dashboard/vars/main.yml
    ;;
  export)
    [[ -n "$output_file" ]] || output_file="dashboard-export-$(date -u +%Y%m%dT%H%M%SZ).json"
    api GET '/api/saved_objects/_export?type=dashboard,visualization,search,index-pattern&includeReferencesDeep=true' \
      | jq -s '{saved_objects: map(select(type == "object"))}' | custom_filter > "$output_file"
    jq -e '.saved_objects | length > 0' "$output_file" >/dev/null || die "dashboard export contains no objects"
    echo "$output_file"
    ;;
  resolve)
    [[ -f "$input_file" ]] || die "--file is required"
    [[ -n "$output_file" ]] || output_file="${input_file%.json}.resolved.json"
    jq --argjson remap '{"wazuh-alerts-*":"wazuh-findings-v5*","wazuh-monitoring-*":"wazuh-metrics-agents*","wazuh-statistics-*":"wazuh-agent-stats*"}' '
      .saved_objects |= map(
        .references = ((.references // []) | map(if .type == "index-pattern" and ($remap[.id] // null) != null then .id = $remap[.id] else . end))
      )' "$input_file" > "$output_file"
    echo "$output_file"
    ;;
  import|rollback)
    [[ -f "$input_file" ]] || die "--file is required"
    payload="$(if [[ "$include_wazuh" == true ]]; then
      jq -c '.saved_objects[]' "$input_file"
    else
      jq -c '.saved_objects[] | select((.attributes.description // "") | startswith("Provided by Wazuh") | not)' "$input_file"
    fi)"
    [[ -n "$payload" ]] || die "saved object file contains no importable objects"
    # OSD returns per-object import errors in HTTP 200; fail if any object did.
    result="$(api POST '/api/saved_objects/_import?overwrite=true' "$payload")"
    echo "$result" | jq .
    echo "$result" | jq -e '(.successes // []) as $ok | ((.errors // []) | length) == 0' >/dev/null \
      || die "saved object import reported errors"
    ;;
  *) usage; exit 2 ;;
esac
