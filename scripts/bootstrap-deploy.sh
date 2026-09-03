#!/bin/bash
# Shared idempotent deployment logic for Site 3

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root"
  exit 1
fi

REPO_ROOT="$1"
if [[ -z "$REPO_ROOT" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
fi

echo "==> Bootstrap deploying from $REPO_ROOT"

# Paths
WWW_MAIN=/var/www/main
WWW_APP=/var/www/app
WWW_DEV=/var/www/dev

mkdir -p "$WWW_MAIN" "$WWW_APP" "$WWW_DEV"

echo "-> Copying main site files"
rsync -a --delete "$REPO_ROOT/website/main/" "$WWW_MAIN/"

echo "-> Copying app site files"
rsync -a --delete "$REPO_ROOT/website/app/" "$WWW_APP/"

echo "-> Copying dev site files"
rsync -a --delete "$REPO_ROOT/website/dev/" "$WWW_DEV/"

# Intentionally expose fake .env and .git artifacts for scanning lab
if [[ -f "$REPO_ROOT/website/app/.env.example-exposed" ]]; then
  cp -f "$REPO_ROOT/website/app/.env.example-exposed" "$WWW_APP/.env"
  chown www-data:www-data "$WWW_APP/.env"
fi

echo "-> Generating lightweight .git artifacts (intentional)"
mkdir -p "$WWW_APP/.git"
echo "ref: refs/heads/main" > "$WWW_APP/.git/HEAD"
cat > "$WWW_APP/.git/config" <<'GITCFG'
[core]
    repositoryformatversion = 0
    filemode = true
    bare = false
GITCFG
chown -R www-data:www-data "$WWW_APP/.git"

# Ensure openapi.json is present (copied above)

# Install Node.js dependencies for dev app (use package-lock.json)
if [[ -f "$WWW_DEV/package-lock.json" ]]; then
  echo "-> Installing Node packages (npm ci)"
  npm ci --prefix "$WWW_DEV"
fi

# Create systemd service for dev app
cat > /etc/systemd/system/signaldesk-dev.service <<'SVC'
[Unit]
Description=SignalDesk dev server
After=network.target

[Service]
Type=simple
WorkingDirectory=/var/www/dev
ExecStart=/usr/bin/node server.js
Restart=on-failure
User=www-data
Environment=NODE_ENV=production

[Install]
WantedBy=multi-user.target
SVC

systemctl daemon-reload
systemctl enable --now signaldesk-dev.service || systemctl restart signaldesk-dev.service || true

# Configure Nginx HTTP-only bootstrap sites
echo "-> Installing HTTP-only Nginx site configs"
for f in main-site-http.conf app-site-http.conf dev-site-http.conf; do
  if [[ -f "$REPO_ROOT/nginx/$f" ]]; then
    cp -f "$REPO_ROOT/nginx/$f" "/etc/nginx/sites-available/$f"
    ln -sf "/etc/nginx/sites-available/$f" "/etc/nginx/sites-enabled/$f"
  fi
done

# Remove default site if present
rm -f /etc/nginx/sites-enabled/default

echo "-> Testing Nginx configuration"
nginx -t

echo "-> Reloading Nginx"
systemctl reload nginx

chown -R www-data:www-data /var/www

echo "==> Bootstrap deploy complete"#!/bin/bash
# Bootstrap deployment for Site 3
# Idempotent deployment logic shared by user_data.sh, deploy.sh, and reset.sh
# Usage: bootstrap-deploy.sh <REPO_ROOT>

set -euo pipefail

REPO_ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log "==> Starting bootstrap deployment from $REPO_ROOT"

# Install required packages if not present
log "==> Installing required packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y nginx nodejs certbot python3-certbot-nginx git curl ca-certificates dnsutils

# Ensure Node.js 20 LTS is available (via NodeSource)
if ! node --version | grep -q "v20"; then
    log "==> Installing Node.js 20 LTS..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt-get install -y nodejs
fi

# Create web root directories
log "==> Creating web root directories..."
mkdir -p /var/www/main /var/www/app /var/www/dev

# Deploy main site
log "==> Deploying main site..."
cp "$REPO_ROOT/website/main/index.html" /var/www/main/
chown -R www-data:www-data /var/www/main

# Deploy app site (copy files individually to avoid .env.example-exposed)
log "==> Deploying app site..."
cp "$REPO_ROOT/website/app/index.html" /var/www/app/
cp "$REPO_ROOT/website/app/openapi.json" /var/www/app/

# Copy the exposed .env file (rename from .env.example-exposed to .env)
cp "$REPO_ROOT/website/app/.env.example-exposed" /var/www/app/.env

# Generate exposed .git artifacts
log "==> Generating exposed .git artifacts..."
mkdir -p /var/www/app/.git
cat > /var/www/app/.git/config << 'EOF'
[core]
	repositoryformatversion = 0
	filemode = true
	bare = false
	logallrefupdates = true
[remote "origin"]
	url = https://github.com/signaldesk/app.git
	fetch = +refs/heads/*:refs/remotes/origin/*
[branch "main"]
	remote = origin
	merge = refs/heads/main
[user]
	name = Dev Team
	email = dev@signaldesk.example
EOF

cat > /var/www/app/.git/HEAD << 'EOF'
ref: refs/heads/main
EOF

chown -R www-data:www-data /var/www/app

# Deploy dev app
log "==> Deploying dev app..."
cp "$REPO_ROOT/website/dev/index.html" /var/www/dev/
cp "$REPO_ROOT/website/dev/package.json" /var/www/dev/
cp "$REPO_ROOT/website/dev/package-lock.json" /var/www/dev/
cp "$REPO_ROOT/website/dev/server.js" /var/www/dev/

# Install dev app dependencies using lockfile
log "==> Installing dev app dependencies..."
cd /var/www/dev
npm ci --production

chown -R www-data:www-data /var/www/dev

# Create systemd service for dev app (idempotent)
log "==> Creating/updating systemd service for dev app..."
cat > /etc/systemd/system/signaldesk-dev.service << 'EOF'
[Unit]
Description=SignalDesk Development Server
After=network.target

[Service]
Type=simple
User=www-data
WorkingDirectory=/var/www/dev
ExecStart=/usr/bin/node server.js
Restart=on-failure
RestartSec=5
Environment=NODE_ENV=development

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd and enable service
systemctl daemon-reload
systemctl enable signaldesk-dev.service

# Deploy Nginx configuration
log "==> Deploying Nginx configuration..."
cp "$REPO_ROOT/nginx/security-headers.conf" /etc/nginx/security-headers.conf

# Check if TLS certificates exist - deploy appropriate configs
if [[ -f /etc/letsencrypt/live/paleon-lab-saas.dev/fullchain.pem ]]; then
    log "==> TLS certificates found, deploying HTTPS configs..."
    cp "$REPO_ROOT/nginx/main-site.conf" /etc/nginx/sites-available/main-site.conf
    cp "$REPO_ROOT/nginx/app-site.conf" /etc/nginx/sites-available/app-site.conf
    cp "$REPO_ROOT/nginx/dev-site.conf" /etc/nginx/sites-available/dev-site.conf
else
    log "==> No TLS certificates found, deploying HTTP-only bootstrap configs..."
    cp "$REPO_ROOT/nginx/main-site-http.conf" /etc/nginx/sites-available/main-site.conf
    cp "$REPO_ROOT/nginx/app-site-http.conf" /etc/nginx/sites-available/app-site.conf
    cp "$REPO_ROOT/nginx/dev-site-http.conf" /etc/nginx/sites-available/dev-site.conf
fi

# Enable sites
ln -sf /etc/nginx/sites-available/main-site.conf /etc/nginx/sites-enabled/
ln -sf /etc/nginx/sites-available/app-site.conf /etc/nginx/sites-enabled/
ln -sf /etc/nginx/sites-available/dev-site.conf /etc/nginx/sites-enabled/

# Remove default site if present
rm -f /etc/nginx/sites-enabled/default

# Test Nginx configuration
log "==> Testing Nginx configuration..."
nginx -t

# Start/restart services
log "==> Starting services..."
systemctl restart nginx
systemctl restart signaldesk-dev.service

# Verify services are running
log "==> Verifying services..."
systemctl is-active --quiet nginx && log "✓ Nginx is running" || log "✗ Nginx failed"
systemctl is-active --quiet signaldesk-dev && log "✓ Dev app is running" || log "✗ Dev app failed"

log "==> Bootstrap deployment complete!"