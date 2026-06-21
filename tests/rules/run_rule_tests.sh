#!/bin/bash
set -euo pipefail
# MITRE ATT&CK Rule Test Runner
# Sends test log samples through wazuh-logtest and reports which rules fired
#
# Usage: ./run_rule_tests.sh [test_file.log]
#        ./run_rule_tests.sh          # run all tests in tests/rules/

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# wazuh-logtest (4.x) is interactive/API-based; wazuh-logtest-legacy accepts piped stdin
WAZUH_LOGTEST="${WAZUH_LOGTEST:-/var/ossec/bin/wazuh-logtest-legacy}"
PASS=0
FAIL=0
TOTAL=0

print_result() {
    local technique="$1"
    local file="$2"
    local fired="$3"
    TOTAL=$((TOTAL + 1))
    if [ "$fired" -gt 0 ]; then
        echo "  [PASS] $technique: $fired rule(s) fired"
        PASS=$((PASS + 1))
    else
        echo "  [FAIL] $technique: no rules fired"
        FAIL=$((FAIL + 1))
    fi
}

run_test_file() {
    local test_file="$1"
    local technique
    technique=$(basename "$test_file" .log | tr '_' ' ' | awk '{for(i=1;i<=NF;i++){$i=toupper(substr($i,1,1))tolower(substr($i,2));}print}')

    echo ""
    echo "Testing: $technique ($test_file)"

    if [ ! -x "$WAZUH_LOGTEST" ]; then
        echo "  [SKIP] wazuh-logtest-legacy not found at $WAZUH_LOGTEST (must run on Wazuh manager)"
        return 0
    fi

    # Count lines with actual log content (skip comments and blanks)
    local log_lines
    log_lines=$(grep -v '^[[:space:]]*#' "$test_file" | grep -v '^[[:space:]]*$' | wc -l)

    # Run each log line through wazuh-logtest and count fired rules
    local fired=0
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        result=$(echo "$line" | "$WAZUH_LOGTEST" -q 2>/dev/null | grep -c "Rule ID:" || true)
        [ "$result" -gt 0 ] && fired=$((fired + 1))
    done < "$test_file"

    print_result "$technique" "$test_file" "$fired"
}

echo "═══════════════════════════════════════════════════════════════"
echo "  Wazuh MITRE ATT&CK Rule Test Suite"
echo "═══════════════════════════════════════════════════════════════"

if [ -n "${1:-}" ]; then
    run_test_file "$1"
else
    for test_file in "$SCRIPT_DIR"/*.log; do
        [ -f "$test_file" ] || continue
        run_test_file "$test_file"
    done
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  Results: $PASS/$TOTAL passed, $FAIL failed"
echo "═══════════════════════════════════════════════════════════════"

[ "$FAIL" -eq 0 ]
