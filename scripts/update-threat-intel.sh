#!/usr/bin/env bash
# Threat Intelligence Feed Updater
# Downloads IP, domain, and hash indicators from public threat feeds
# and formats them as Wazuh CDB lists.
#
# Usage:
#   ./scripts/update-threat-intel.sh          # Update all feeds
#   ./scripts/update-threat-intel.sh --dry-run # Show what would be downloaded
#
# Feeds:
#   - abuse.ch Feodo Tracker (C2 IPs)
#   - abuse.ch SSL Blacklist (malicious IPs)
#   - abuse.ch URLhaus (malicious domains)
#   - AlienVault OTX reputation (malicious IPs)
#
# Schedule via cron:
#   0 */6 * * * cd /path/to/wazuh-deployment && ./scripts/update-threat-intel.sh
#
# After updating, redeploy rules to push lists to the manager:
#   ansible-playbook site.yml --tags manager

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
IOC_DIR="$PROJECT_DIR/files/cdb_lists/malicious-ioc"
LOG_DIR="$PROJECT_DIR/logs"
LOG_FILE="$LOG_DIR/threat-intel-update.log"
TMP_DIR=$(mktemp -d)
DRY_RUN=false

# Parse arguments
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=true ;;
  esac
done

# Ensure directories exist
mkdir -p "$IOC_DIR" "$LOG_DIR"

log() {
  local msg="[$(date '+%Y-%m-%d %H:%M:%S')] $1"
  echo "$msg" | tee -a "$LOG_FILE"
}

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# Validate IP address format
is_valid_ip() {
  local ip="$1"
  [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]
}

# Validate domain format
is_valid_domain() {
  local domain="$1"
  [[ "$domain" =~ ^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?$ ]]
}

# Validate hash format (MD5, SHA1, or SHA256)
is_valid_hash() {
  local hash="$1"
  [[ "$hash" =~ ^[a-fA-F0-9]{32}$ ]] || \
  [[ "$hash" =~ ^[a-fA-F0-9]{40}$ ]] || \
  [[ "$hash" =~ ^[a-fA-F0-9]{64}$ ]]
}

download_feed() {
  local url="$1"
  local output="$2"
  local name="$3"

  log "Downloading $name..."
  if curl -sS --max-time 60 --retry 3 -o "$output" "$url" 2>>"$LOG_FILE"; then
    local lines
    lines=$(wc -l < "$output")
    log "  Downloaded $lines lines from $name"
    return 0
  else
    log "  ERROR: Failed to download $name"
    return 1
  fi
}

# ═══════════════════════════════════════════════════
# Malicious IPs
# ═══════════════════════════════════════════════════
update_malicious_ips() {
  local ip_file="$TMP_DIR/ips.txt"
  > "$ip_file"

  # abuse.ch Feodo Tracker - C2 botnet IPs
  if download_feed \
    "https://feodotracker.abuse.ch/downloads/ipblocklist_recommended.txt" \
    "$TMP_DIR/feodo.txt" "Feodo Tracker"; then
    grep -v '^#' "$TMP_DIR/feodo.txt" | grep -v '^$' >> "$ip_file" || true
  fi

  # abuse.ch SSL Blacklist - IPs with malicious SSL certs
  if download_feed \
    "https://sslbl.abuse.ch/blacklist/sslipblacklist.txt" \
    "$TMP_DIR/sslbl.txt" "SSL Blacklist"; then
    grep -v '^#' "$TMP_DIR/sslbl.txt" | grep -v '^$' >> "$ip_file" || true
  fi

  # AlienVault OTX reputation
  if download_feed \
    "https://reputation.alienvault.com/reputation.generic" \
    "$TMP_DIR/otx.txt" "AlienVault OTX"; then
    # Format: IP # category
    awk '{print $1}' "$TMP_DIR/otx.txt" | grep -v '^#' | grep -v '^$' >> "$ip_file" || true
  fi

  # Deduplicate, validate, format as CDB
  local count=0
  local output="$IOC_DIR/malicious-ip"
  > "${output}.tmp"

  while IFS= read -r ip; do
    ip=$(echo "$ip" | tr -d '[:space:]')
    if is_valid_ip "$ip"; then
      echo "${ip}:" >> "${output}.tmp"
      count=$((count + 1))
    fi
  done < <(sort -u "$ip_file")

  if [ "$DRY_RUN" = true ]; then
    log "DRY RUN: Would write $count malicious IPs"
    rm -f "${output}.tmp"
  else
    sort -u "${output}.tmp" > "$output"
    rm -f "${output}.tmp"
    log "Updated malicious-ip: $count entries"
  fi
}

# ═══════════════════════════════════════════════════
# Malicious Domains
# ═══════════════════════════════════════════════════
update_malicious_domains() {
  local domain_file="$TMP_DIR/domains.txt"
  > "$domain_file"

  # abuse.ch URLhaus - malicious URLs (extract domains)
  if download_feed \
    "https://urlhaus.abuse.ch/downloads/text_online/" \
    "$TMP_DIR/urlhaus.txt" "URLhaus"; then
    # Extract domains from URLs: http(s)://domain/path
    grep -v '^#' "$TMP_DIR/urlhaus.txt" | grep -v '^$' | \
      sed -E 's|https?://([^/:]+).*|\1|' | \
      grep -v '^[0-9]' >> "$domain_file" || true
  fi

  # Deduplicate, validate, format as CDB
  local count=0
  local output="$IOC_DIR/malicious-domains"
  > "${output}.tmp"

  while IFS= read -r domain; do
    domain=$(echo "$domain" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
    if is_valid_domain "$domain" && [ -n "$domain" ]; then
      echo "${domain}:" >> "${output}.tmp"
      count=$((count + 1))
    fi
  done < <(sort -u "$domain_file")

  if [ "$DRY_RUN" = true ]; then
    log "DRY RUN: Would write $count malicious domains"
    rm -f "${output}.tmp"
  else
    sort -u "${output}.tmp" > "$output"
    rm -f "${output}.tmp"
    log "Updated malicious-domains: $count entries"
  fi
}

# ═══════════════════════════════════════════════════
# Malware Hashes
# ═══════════════════════════════════════════════════
update_malware_hashes() {
  local hash_file="$TMP_DIR/hashes.txt"
  > "$hash_file"

  # abuse.ch URLhaus payloads (SHA256 hashes)
  if download_feed \
    "https://urlhaus.abuse.ch/downloads/payloads/" \
    "$TMP_DIR/urlhaus_payloads.csv" "URLhaus Payloads"; then
    # CSV format: id,dateadded,url,payload_url,file_type,file_size,sha256_hash,md5_hash,...
    tail -n +10 "$TMP_DIR/urlhaus_payloads.csv" | \
      awk -F'"' '{for(i=1;i<=NF;i++){if($i~/^[a-f0-9]{64}$/){print $i}}}' >> "$hash_file" || true
  fi

  # abuse.ch MalwareBazaar recent SHA256 hashes
  if download_feed \
    "https://bazaar.abuse.ch/export/txt/sha256/recent/" \
    "$TMP_DIR/bazaar.txt" "MalwareBazaar"; then
    grep -v '^#' "$TMP_DIR/bazaar.txt" | grep -v '^$' >> "$hash_file" || true
  fi

  # Deduplicate, validate, format as CDB (keep EICAR test entry)
  local count=0
  local output="$IOC_DIR/malware-hashes"
  > "${output}.tmp"

  # Preserve EICAR test hashes
  echo "44d88612fea8a8f36de82e1278abb02f:EICAR-Test-File" >> "${output}.tmp"
  echo "275a021bbfb6489e54d471899f7db9d1663fc695ec2fe2a2c4538aabf651fd0f:EICAR-SHA256" >> "${output}.tmp"

  while IFS= read -r hash; do
    hash=$(echo "$hash" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
    if is_valid_hash "$hash"; then
      echo "${hash}:" >> "${output}.tmp"
      count=$((count + 1))
    fi
  done < <(sort -u "$hash_file")

  if [ "$DRY_RUN" = true ]; then
    log "DRY RUN: Would write $count malware hashes (+ 2 EICAR test entries)"
    rm -f "${output}.tmp"
  else
    sort -u "${output}.tmp" > "$output"
    rm -f "${output}.tmp"
    log "Updated malware-hashes: $count entries (+ EICAR test entries)"
  fi
}

# ═══════════════════════════════════════════════════
# Main
# ═══════════════════════════════════════════════════
log "========================================="
log "Threat Intelligence Feed Update"
log "========================================="

if [ "$DRY_RUN" = true ]; then
  log "DRY RUN MODE - no files will be modified"
fi

update_malicious_ips
update_malicious_domains
update_malware_hashes

log "========================================="
log "Update complete"
log "========================================="
log ""
log "Next steps:"
log "  1. Review updated lists in $IOC_DIR/"
log "  2. Deploy to manager: ansible-playbook site.yml --tags manager"
log "  3. Or use: make deploy-rules"
