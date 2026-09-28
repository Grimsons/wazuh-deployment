#!/usr/bin/env bats

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"

@test "legacy 4.x restore keeps the requested timestamp" {
    python3 -c "
s = open('$REPO_ROOT/playbooks/restore.yml').read()
start = s.index('Set backup source path')
guard = s[start:s.index('Resolve the effective target version', start)]
assert \"+ '/' + restore_from\" in guard
"
}

@test "restore refuses a missing or malformed effective target version" {
    python3 -c "
s = open('$REPO_ROOT/playbooks/restore.yml').read()
start = s.index('Resolve the effective target version')
guard = s[start:s.index('Refuse the legacy archive path', start)]
assert 'wazuh_effective_version' in guard
assert 'Cannot safely restore without a valid target Wazuh version' in guard
assert 'is not match' in guard
assert 'restore_target_major | length > 0' not in s
"
}
