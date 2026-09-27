#!/usr/bin/env bash
# check-ga-gate.sh — Decide whether the default VERSION.json pin may move
# to a given Wazuh version.
#
#   ./scripts/check-ga-gate.sh                 # gate 5.0.0
#   ./scripts/check-ga-gate.sh --target 5.1.0  # gate another line
#
# Exit status is the verdict: 0 only when a GA release, a checksummed
# stable channel and the target version in that channel all check out.
# Anything else — including a network failure — is a closed gate, because a
# gate that cannot be evaluated must not authorise a pin flip.
#
# --fixture-dir DIR replays saved bodies (release.json, Release, Packages)
# instead of fetching, so the whole script is testable offline.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# shellcheck source-path=SCRIPTDIR SCRIPTDIR/..
# shellcheck source=lib/colors.sh
source "$PROJECT_DIR/lib/colors.sh"
# shellcheck source=lib/ga_gate.sh
source "$PROJECT_DIR/lib/ga_gate.sh"

die() { echo -e "${RED}✗  $*${NC}" >&2; exit 1; }

TARGET="$(ga_gate_default_target)"
TIMEOUT="${WAZUH_GATE_TIMEOUT:-30}"
FIXTURE_DIR=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --target) TARGET="${2:?--target needs a version}"; shift 2 ;;
        --target=*) TARGET="${1#*=}"; shift ;;
        --timeout) TIMEOUT="${2:?--timeout needs seconds}"; shift 2 ;;
        --fixture-dir) FIXTURE_DIR="${2:?--fixture-dir needs a path}"; shift 2 ;;
        --fixture-dir=*) FIXTURE_DIR="${1#*=}"; shift ;;
        -h|--help)
            sed -n '2,14p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) die "Unknown argument: $1" ;;
    esac
done

# ── fetching ──────────────────────────────────────────────────────────────────

# fetch <url> <fixture-name> -> body on stdout.  An HTTP error is reported
# as an empty body plus a non-zero status so the caller can distinguish
# "upstream said no" from "we could not ask".
fetch() {
    local url="$1" fixture="$2" status

    if [[ -n "$FIXTURE_DIR" ]]; then
        [[ -r "$FIXTURE_DIR/$fixture" ]] || return 1
        cat "$FIXTURE_DIR/$fixture"
        return 0
    fi

    status="$(curl -sS -L --max-time "$TIMEOUT" -o "$SCRATCH_BODY" -w '%{http_code}' "$url" 2>/dev/null)" || {
        echo "  (request failed: $url)" >&2
        return 1
    }
    if [[ "$status" != "200" ]]; then
        echo "  (HTTP $status from $url)" >&2
        return 1
    fi
    cat "$SCRATCH_BODY"
}

SCRATCH_BODY="$(mktemp)"
trap 'rm -f "$SCRATCH_BODY"' EXIT

# ── checks ────────────────────────────────────────────────────────────────────

CHECKS_RUN=0
CHECKS_PASSED=0

# check <label> <outcome> <detail>
report() {
    CHECKS_RUN=$((CHECKS_RUN + 1))
    if [[ "$2" == "pass" ]]; then
        CHECKS_PASSED=$((CHECKS_PASSED + 1))
        echo -e "  ${GREEN}✓${NC} $1 $3"
    else
        echo -e "  ${RED}✗${NC} $1 $3"
    fi
}

print_header "Wazuh GA gate — target $TARGET"

if ga_gate_target_is_prerelease "$TARGET"; then
    report "target is a GA version" "fail" "$TARGET is a pre-release; a pre-release can never open this gate"
    echo
    print_header "GATE CLOSED — $CHECKS_PASSED/$CHECKS_RUN checks passed"
    exit 1
fi

RELEASE_URL="$(ga_gate_release_api_url "$TARGET")"
CHANNEL_URL="$(ga_gate_release_index_url "$TARGET")"
PACKAGES_URL="$(ga_gate_packages_index_url "$TARGET")"

RELEASE_BODY="$(fetch "$RELEASE_URL" release.json)" || RELEASE_BODY=""
if [[ -n "$RELEASE_BODY" ]] && ga_gate_has_ga_release "$RELEASE_BODY" "$TARGET"; then
    report "GA release published" "pass" "$RELEASE_URL"
else
    report "GA release published" "fail" "no non-prerelease release $RELEASE_URL"
fi

CHANNEL_BODY="$(fetch "$CHANNEL_URL" Release)" || CHANNEL_BODY=""
if [[ -n "$CHANNEL_BODY" ]] && ga_gate_release_file_has_checksums "$CHANNEL_BODY"; then
    report "stable channel is checksummed" "pass" "$CHANNEL_URL"
else
    report "stable channel is checksummed" "fail" "no SHA256/SHA512 digest index at $CHANNEL_URL"
fi

PACKAGES_BODY="$(fetch "$PACKAGES_URL" Packages)" || PACKAGES_BODY=""
if [[ -n "$PACKAGES_BODY" ]] && ga_gate_package_index_has_version "$PACKAGES_BODY" "$TARGET"; then
    report "target in stable channel" "pass" "$(ga_gate_managed_packages | tr '\n' ' ')"
else
    report "target in stable channel" "fail" "$TARGET not in the stable channel at $PACKAGES_URL"
fi

echo
if [[ "$CHECKS_PASSED" -eq "$CHECKS_RUN" ]]; then
    print_header "GATE OPEN — $CHECKS_RUN/$CHECKS_RUN checks passed"
    echo -e "  ${CYAN}Next:${NC} flip VERSION.json to $TARGET (stage: stable), then re-run make test."
    exit 0
fi

print_header "GATE CLOSED — $CHECKS_PASSED/$CHECKS_RUN checks passed"
echo -e "  ${CYAN}Do not${NC} move the default pin to $TARGET. Keep the current stable line."
exit 1
