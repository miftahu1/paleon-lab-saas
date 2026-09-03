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
# TLS polling script for Site 3
# Called by systemd timer to check DNS and provision Let's Encrypt certificates
# Runs every 5 minutes for up to 60 minutes (12 attempts max)

set -euo pipefail

REPO_ROOT="/opt/site3"
DOMAIN="paleon-lab-saas.dev"
EMAIL="admin@${DOMAIN}"
TLS_POLL_START="/var/lib/site3/tls-poll-start"
TLS_LOG="/var/log/tls-setup.log"
MAX_DURATION=3600  # 60 minutes in seconds

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$TLS_LOG"
}

log "==> TLS poll check started"

# Check if timer has expired (60 minutes)
if [[ -f "$TLS_POLL_START" ]]; then
    START_TIME=$(cat "$TLS_POLL_START")
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - START_TIME))
    if [[ $ELAPSED -ge $MAX_DURATION ]]; then
        log "TIMEOUT: DNS not propagated after 60 minutes (elapsed: ${ELAPSED}s)."
        log "Run manually: sudo ./scripts/setup-ssl.sh"
        systemctl disable --now site3-tls-poll.timer 2>/dev/null || true
        exit 0
    fi
    log "Poll attempt (elapsed: ${ELAPSED}s / ${MAX_DURATION}s)"
else
    log "WARNING: No timer start marker found"
fi

# Check if certificates already exist (another process may have completed)
if [[ -f "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" ]]; then
    log "TLS certificates already exist - disabling timer"
    systemctl disable --now site3-tls-poll.timer 2>/dev/null || true
    # Ensure certbot renewal is active
    systemctl enable certbot.timer
    systemctl start certbot.timer
    exit 0
fi

# Check DNS resolution for all three hosts
log "==> Checking DNS resolution..."
ALL_RESOLVED=true

for subdomain in "" "app." "dev."; do
    hostname="${subdomain}${DOMAIN}"
    RESOLVED=false

    # Use dig if available
    if command -v dig &> /dev/null; then
        if dig +short "$hostname" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
            RESOLVED=true
        fi
    fi

    # Fallback to nslookup
    if [[ "$RESOLVED" == "false" ]] && command -v nslookup &> /dev/null; then
        if nslookup "$hostname" >/dev/null 2>&1; then
            RESOLVED=true
        fi
    fi

    # Fallback to getent
    if [[ "$RESOLVED" == "false" ]]; then
        if getent hosts "$hostname" >/dev/null 2>&1; then
            RESOLVED=true
        fi
    fi

    if [[ "$RESOLVED" == "true" ]]; then
        log "✓ $hostname resolves"
    else
        log "✗ $hostname does not resolve yet"
        ALL_RESOLVED=false
    fi
done

# If not all resolved, exit quietly (timer will retry)
if [[ "$ALL_RESOLVED" == "false" ]]; then
    log "DNS not fully propagated - will retry on next timer fire"
    exit 0
fi

# All hosts resolve - proceed with certificate request
log "==> All hosts resolve. Requesting Let's Encrypt certificate..."

certbot certonly \
    --nginx \
    --non-interactive \
    --agree-tos \
    --email "$EMAIL" \
    -d "$DOMAIN" \
    -d "app.${DOMAIN}" \
    -d "dev.${DOMAIN}" 2>&1 | tee -a "$TLS_LOG"

# Verify certificate was issued
if [[ ! -f "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" ]]; then
    log "ERROR: Certificate was not issued"
    exit 1
fi

log "✓ Certificate issued successfully"

# Deploy final HTTPS configs
log "==> Deploying final HTTPS Nginx configurations..."
cp "$REPO_ROOT/nginx/main-site.conf" /etc/nginx/sites-available/main-site.conf
cp "$REPO_ROOT/nginx/app-site.conf" /etc/nginx/sites-available/app-site.conf
cp "$REPO_ROOT/nginx/dev-site.conf" /etc/nginx/sites-available/dev-site.conf

# Test Nginx configuration
log "==> Testing Nginx configuration with TLS..."
nginx -t 2>&1 | tee -a "$TLS_LOG"

# Reload Nginx to enable HTTPS
log "==> Reloading Nginx..."
systemctl reload nginx

# Setup automatic certificate renewal
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