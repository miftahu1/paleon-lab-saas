#!/bin/bash
# TLS DNS polling script for Site 3
# Checks that three hostnames resolve to the expected Elastic IP and
# then runs the TLS setup script once.

set -euo pipefail

LOG=/var/log/tls-setup.log
MARKER=/var/lib/site3/tls-setup-done
START_FILE=/var/lib/site3/tls-poll-start
EXPECTED_FILE=/var/lib/site3/expected_ip
DOMAIN=paleon-lab-saas.dev

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG"; }

if [[ -f "$MARKER" ]]; then
  log "TLS already set up; exiting"
  exit 0
fi

if [[ ! -f "$EXPECTED_FILE" ]]; then
  log "Expected IP file missing: $EXPECTED_FILE"
  exit 1
fi

EXPECTED_IP=$(cat "$EXPECTED_FILE")
log "Expected IP for DNS checks: $EXPECTED_IP"

if [[ ! -f "$START_FILE" ]]; then
  date +%s > "$START_FILE"
  log "Recorded polling start time"
fi

START_TS=$(cat "$START_FILE")
NOW_TS=$(date +%s)
ELAPSED=$((NOW_TS - START_TS))

# If more than 3600 seconds (~60 min) have passed, timeout
if (( ELAPSED > 3600 )); then
  log "TIMEOUT: DNS did not propagate within expected window (elapsed ${ELAPSED}s)"
  systemctl disable --now site3-tls-poll.timer 2>/dev/null || true
  log "TIMEOUT: DNS did not propagate within expected window (elapsed ${ELAPSED}s)" >> "$LOG"
  exit 0
fi

resolve_ips() {
  host="$1"
  # Prefer dig, fallback to nslookup parsing
  if command -v dig &>/dev/null; then
    dig +short "$host" | awk '/^[0-9]+\./ { print }'
  elif command -v nslookup &>/dev/null; then
    nslookup "$host" 2>/dev/null | awk '/^Address: / { print $2 }'
  else
    return 1
  fi
}

check_host() {
  host="$1"
  ips=$(resolve_ips "$host" || true)
  for ip in $ips; do
    if [[ "$ip" == "$EXPECTED_IP" ]]; then
      return 0
    fi
  done
  return 1
}

ALL_OK=true
for prefix in "" "app." "dev."; do
  host="${prefix}${DOMAIN}"
  if check_host "$host"; then
    log "DNS OK: $host -> $EXPECTED_IP"
  else
    resolved=$(resolve_ips "$host" 2>/dev/null | tr '\n' ',' || true)
    log "DNS MISMATCH: $host does not resolve to $EXPECTED_IP (resolved: ${resolved})"
    ALL_OK=false
  fi
done

if [[ "$ALL_OK" == true ]]; then
  log "All hostnames resolve to expected IP. Initiating TLS setup."
  # Run setup-ssl.sh which performs certbot and enables certbot.timer
  if /opt/site3/scripts/setup-ssl.sh; then
    log "TLS setup completed successfully"
    date +%s > "$MARKER"
    # On success, disable the polling timer and enable certbot renewal
    systemctl disable --now site3-tls-poll.timer || true
    systemctl enable --now certbot.timer || true
    log "Polling timer disabled and certbot.timer enabled"
  else
    log "TLS setup failed; will retry on next timer cycle"
  fi
else
  log "Not all hostnames resolved yet; will retry (elapsed ${ELAPSED}s)"
fi

exit 0
