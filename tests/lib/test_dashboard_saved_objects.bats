#!/usr/bin/env bats

setup() {
  script="$BATS_TEST_DIRNAME/../../scripts/dashboard-saved-objects.sh"
}

@test "helper has a safe, executable interface" {
  [ -x "$script" ]
  run "$script" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"resolve"* ]]
}

@test "resolve remaps retired 4.x pattern references" {
  input="$BATS_TEST_TMPDIR/export.json"
  output="$BATS_TEST_TMPDIR/resolved.json"
  cat > "$input" <<'EOF'
{"saved_objects":[{"type":"visualization","id":"v1","references":[{"type":"index-pattern","id":"wazuh-alerts-*"}]}]}
EOF
  run "$script" resolve --file "$input" --output "$output"
  [ "$status" -eq 0 ]
  run jq -r '.saved_objects[0].references[0].id' "$output"
  [ "$output" = "wazuh-findings-v5*" ]
}

@test "inventory contract documents all role-created 4.x patterns" {
  run rg -q 'wazuh-alerts-\*' roles/wazuh-dashboard/vars/main.yml
  [ "$status" -eq 0 ]
  run rg -q 'wazuh-monitoring-\*' roles/wazuh-dashboard/vars/main.yml
  [ "$status" -eq 0 ]
  run rg -q 'wazuh-statistics-\*' roles/wazuh-dashboard/vars/main.yml
  [ "$status" -eq 0 ]
}
