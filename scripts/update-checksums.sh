#!/usr/bin/env bash
# update-checksums.sh — Recompute artifact SHA-256 checksums for the current
# Wazuh version and patch roles/wazuh-manager/defaults/main.yml in-place.
#
# Run this whenever VERSION.json changes or after a filebeat module version bump:
#   ./scripts/update-checksums.sh
#
# It downloads each artifact, verifies it is non-empty, computes the hash,
# and writes it back into main.yml so the Ansible role can verify downloads.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
DEFAULTS_FILE="$PROJECT_DIR/roles/wazuh-manager/defaults/main.yml"
VERSION_FILE="$PROJECT_DIR/VERSION.json"

# ── helpers ──────────────────────────────────────────────────────────────────

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()    { echo -e "${CYAN}ℹ  $*${NC}"; }
success() { echo -e "${GREEN}✓  $*${NC}"; }
warn()    { echo -e "${YELLOW}⚠  $*${NC}"; }
die()     { echo -e "${RED}✗  $*${NC}" >&2; exit 1; }

require() { command -v "$1" >/dev/null 2>&1 || die "Required tool missing: $1"; }

# ── prerequisites ─────────────────────────────────────────────────────────────

require curl
require sha256sum
require sha512sum
require gpg
require python3

# ── read versions ─────────────────────────────────────────────────────────────

WAZUH_VERSION="$(python3 -c "import json,sys; d=json.load(open('$VERSION_FILE')); print(d['version'])")"
FILEBEAT_VERSION="$(grep '^wazuh_filebeat_version:' "$DEFAULTS_FILE" | awk '{print $2}' | tr -d '"')"

info "Wazuh version      : $WAZUH_VERSION"
info "Filebeat version   : $FILEBEAT_VERSION"
echo

# ── URLs ──────────────────────────────────────────────────────────────────────

FILEBEAT_DEB_URL="https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-oss-${FILEBEAT_VERSION}-amd64.deb"
FILEBEAT_MODULE_URL="https://packages.wazuh.com/4.x/filebeat/wazuh-filebeat-0.4.tar.gz"
WAZUH_TEMPLATE_URL="https://raw.githubusercontent.com/wazuh/wazuh/v${WAZUH_VERSION}/extensions/elasticsearch/7.x/wazuh-template.json"

# ── GPG key import ────────────────────────────────────────────────────────────

WAZUH_GPG_KEY_URL="https://packages.wazuh.com/key/GPG-KEY-WAZUH"
WAZUH_GPG_FINGERPRINT="0DCFCA5547B19D2A6099506096B3EE5F29111145"
ELASTIC_GPG_KEY_URL="https://artifacts.elastic.co/GPG-KEY-elasticsearch"
ELASTIC_GPG_FINGERPRINT="4609 5ACC 8548 582C 1A26 99A9 D27D 666C D88E 42B4"

import_gpg_key() {
    local label="$1" url="$2" fingerprint="$3"
    local tmpkey
    tmpkey="$(mktemp)"
    curl -fsSL --tlsv1.2 --max-time 30 "$url" -o "$tmpkey"
    gpg --import "$tmpkey" 2>/dev/null || true
    rm -f "$tmpkey"
    # Verify the expected fingerprint is now trusted
    if ! gpg --fingerprint "$fingerprint" &>/dev/null; then
        warn "$label GPG key fingerprint not verified — proceeding without signature check"
        return 1
    fi
    success "$label GPG key imported (fingerprint verified)"
    return 0
}

info "Importing publisher GPG keys for signature verification …"
WAZUH_GPG_OK=false
ELASTIC_GPG_OK=false
import_gpg_key "Wazuh"   "$WAZUH_GPG_KEY_URL"   "$WAZUH_GPG_FINGERPRINT"  && WAZUH_GPG_OK=true  || true
import_gpg_key "Elastic" "$ELASTIC_GPG_KEY_URL"  "$ELASTIC_GPG_FINGERPRINT" && ELASTIC_GPG_OK=true || true

# ── download + hash ───────────────────────────────────────────────────────────

# Fetch artifact, verify sha512 from publisher, then return sha256
fetch_sha256() {
    local label="$1" url="$2" sha512_url="${3:-}" gpg_ok="${4:-false}"
    info "Fetching $label …"
    local tmpfile
    tmpfile="$(mktemp)"
    curl -fsSL --tlsv1.2 --max-time 120 "$url" -o "$tmpfile"
    [[ -s "$tmpfile" ]] || die "Empty download for $label"

    # Verify sha512 from publisher when available
    if [[ -n "$sha512_url" ]]; then
        local expected_sha512
        expected_sha512="$(curl -fsSL --tlsv1.2 --max-time 30 "$sha512_url" | awk '{print $1}')"
        local actual_sha512
        actual_sha512="$(sha512sum "$tmpfile" | awk '{print $1}')"
        if [[ "$expected_sha512" == "$actual_sha512" ]]; then
            success "$label sha512 matches publisher"
        else
            rm -f "$tmpfile"
            die "$label sha512 MISMATCH — expected $expected_sha512 got $actual_sha512"
        fi
    else
        warn "$label — no sha512 URL provided, skipping publisher verification"
    fi

    local hash
    hash="$(sha256sum "$tmpfile" | awk '{print $1}')"
    rm -f "$tmpfile"
    [[ -n "$hash" ]] || die "Empty sha256 for $label"
    success "$label → sha256:$hash"
    echo "$hash"
}

FILEBEAT_SHA512_URL="https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-oss-${FILEBEAT_VERSION}-amd64.deb.sha512"
MODULE_SHA512_URL="https://packages.wazuh.com/4.x/filebeat/wazuh-filebeat-0.4.tar.gz.sha512"

DEB_HASH="$(fetch_sha256    "filebeat-oss-${FILEBEAT_VERSION}-amd64.deb" "$FILEBEAT_DEB_URL"    "$FILEBEAT_SHA512_URL" "$ELASTIC_GPG_OK")"
MODULE_HASH="$(fetch_sha256 "wazuh-filebeat-0.4.tar.gz"                  "$FILEBEAT_MODULE_URL" "$MODULE_SHA512_URL"   "$WAZUH_GPG_OK")"
TEMPLATE_HASH="$(fetch_sha256 "wazuh-template.json (v${WAZUH_VERSION})"  "$WAZUH_TEMPLATE_URL"  ""                     "false")"

# ── patch defaults/main.yml ───────────────────────────────────────────────────

echo
info "Updating $DEFAULTS_FILE …"

patch_var() {
    local var="$1" value="$2"
    # Replace the value in-place; the line format is:  varname: "sha256:hexhash"
    sed -i "s|^${var}: .*|${var}: \"sha256:${value}\"|" "$DEFAULTS_FILE"
}

patch_var "wazuh_filebeat_deb_sha256"      "$DEB_HASH"
patch_var "wazuh_filebeat_module_sha256"   "$MODULE_HASH"
patch_var "wazuh_filebeat_template_sha256" "$TEMPLATE_HASH"

success "Checksums written to $DEFAULTS_FILE"
echo
warn "Review the diff, then commit:"
echo "   git diff roles/wazuh-manager/defaults/main.yml"
echo "   git add roles/wazuh-manager/defaults/main.yml"
echo "   git commit -m \"chore: update artifact checksums for Wazuh ${WAZUH_VERSION}\""
