#!/bin/bash
# Terraform template user-data for Site 3 EC2 instance
# This file is processed by Terraform templatefile(), which substitutes
# ${repo_url} and ${expected_ip}. All other shell $${...} tokens are
# left as literal $${...} by using $$$${...} so the shell expands them at runtime.

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# Values substituted by Terraform
REPO_URL="${repo_url}"
EXPECTED_IP="${expected_ip}"

# Local state and log
REPO_DIR="/opt/site3"
DEPLOY_MARKER="/var/lib/site3/deployed"
TLS_POLL_START="/var/lib/site3/tls-poll-start"
TLS_LOG="/var/log/tls-setup.log"
DOMAIN="paleon-lab-saas.dev"
EMAIL="admin@$${DOMAIN}"

# Simple logger
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $$*" | tee -a /var/log/cloud-init.log
}

log "=== Site 3 Cloud-init Starting ==="

# Install base packages
log "Installing base packages..."
apt-get update
apt-get install -y \
    nginx \
    git \
    curl \
    ca-certificates \
    dnsutils \
    rsync \
    certbot \
    python3-certbot-nginx

# Enable and start nginx (HTTP-only bootstrap)
systemctl enable nginx
systemctl start nginx

# Install Node.js 20 LTS (using NodeSource)
log "Installing Node.js 20 LTS..."
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs

# Create web directories and state dir
mkdir -p /var/www/main /var/www/app /var/www/dev
chown -R www-data:www-data /var/www
mkdir -p /var/lib/site3

# Deployment idempotency
if [[ -f "$DEPLOY_MARKER" ]]; then
    log "Deployment marker found - skipping repository clone and content deployment"
else
    log "Cloning repository from $REPO_URL..."
    rm -rf "$REPO_DIR"
    git clone "$REPO_URL" "$REPO_DIR"

    log "Running bootstrap deployment..."
    bash "$REPO_DIR/scripts/bootstrap-deploy.sh" "$REPO_DIR"

    touch "$DEPLOY_MARKER"
    log "Bootstrap deployment complete"
fi

# Persist expected IP for TLS polling script
if [[ -n "$EXPECTED_IP" ]]; then
    echo "$EXPECTED_IP" > /var/lib/site3/expected_ip
    log "Wrote expected IP to /var/lib/site3/expected_ip: $EXPECTED_IP"
fi

# TLS polling: enable timer if no certs exist
if [[ ! -f "/etc/letsencrypt/live/$${DOMAIN}/fullchain.pem" ]]; then
    log "No TLS certificates found - setting up DNS polling timer..."

    # Record timer start time if not already set
    if [[ ! -f "$TLS_POLL_START" ]]; then
        date +%s > "$TLS_POLL_START"
        log "TLS polling started at $(date)"
    fi

    # Create tls-poll service
    cat > /etc/systemd/system/site3-tls-poll.service << 'SVC_EOF'
[Unit]
Description=Site 3 TLS DNS Poll and Certificate Setup
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/opt/site3/scripts/tls-poll.sh
StandardOutput=journal
StandardError=journal
SVC_EOF

    # Create tls-poll timer (every 5 minutes)
    cat > /etc/systemd/system/site3-tls-poll.timer << 'TMR_EOF'
[Unit]
Description=Poll DNS for Site 3 TLS setup every 5 minutes (max ~60 min)

[Timer]
OnBootSec=2min
OnUnitActiveSec=5min
AccuracySec=1min
Persistent=false

[Install]
WantedBy=timers.target
TMR_EOF

    # Enable and start timer
    systemctl daemon-reload
    systemctl enable site3-tls-poll.timer
    systemctl start site3-tls-poll.timer

    log "TLS polling timer enabled (checks every 5 min, bounded attempts)"
else
    log "TLS certificates already exist - skipping timer setup"
    systemctl enable certbot.timer
    systemctl start certbot.timer
fi

log "=== Site 3 Cloud-init Completed ==="