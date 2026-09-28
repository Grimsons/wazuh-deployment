#!/usr/bin/env bats

# The resolver is intentionally exercised with both manifest generations.  The
# 4.x profile keeps the legacy manifest shape; 5.x publishes exact artifacts
# with a digest alongside each package.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"

setup() {
    if ! command -v python3 >/dev/null 2>&1; then
        skip "python3 not installed"
    fi
    if ! python3 -c 'import ansible' >/dev/null 2>&1; then
        skip "ansible not installed"
    fi
}

resolve() {
    local profile="$1"
    PROFILE="$profile" REPO_ROOT="$REPO_ROOT" python3 - <<'PY'
import os
import sys

sys.path.insert(0, os.path.join(os.environ["REPO_ROOT"], "roles", "package-urls", "filter_plugins"))
from package_manifest import resolve_package

manifests = {
    "4": {
        "wazuh-manager": {
            "deb": {
                "amd64": {
                    "url": "https://packages.wazuh.com/4.14/apt/pool/main/w/wazuh-manager/wazuh-manager_4.14.5_amd64.deb",
                    "sha256": "4x-manager-digest",
                }
            }
        }
    },
    "5": {
        "packages": {
            "wazuh-manager": {
                "deb": {
                    "amd64": {
                        "url": "https://packages.wazuh.com/production/5.x/wazuh-manager-5.0.0-1_amd64.deb",
                        "sha256": "5x-manager-digest",
                    }
                }
            }
        }
    },
}

result = resolve_package(manifests[os.environ["PROFILE"]], "wazuh-manager", "deb", "amd64")
print(result["url"])
print(result["checksum"])
PY
}

@test "4.14.5 resolves the legacy package URL and sha256 source" {
    run resolve 4
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "https://packages.wazuh.com/4.14/apt/pool/main/w/wazuh-manager/wazuh-manager_4.14.5_amd64.deb" ]
    [ "${lines[1]}" = "sha256:4x-manager-digest" ]
}

@test "5.0.0 resolves the exact artifact URL and sha256 source" {
    run resolve 5
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "https://packages.wazuh.com/production/5.x/wazuh-manager-5.0.0-1_amd64.deb" ]
    [ "${lines[1]}" = "sha256:5x-manager-digest" ]
}

@test "an artifact without a published checksum fails closed" {
    run python3 - <<'PY'
import sys
sys.path.insert(0, "roles/package-urls/filter_plugins")
from package_manifest import resolve_package

try:
    resolve_package({"wazuh-manager": {"deb": {"amd64": "https://example.invalid/package.deb"}}}, "wazuh-manager", "deb", "amd64")
except Exception:
    raise SystemExit(0)
raise SystemExit(1)
PY
    [ "$status" -eq 0 ]
}
