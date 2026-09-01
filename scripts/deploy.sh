#!/bin/bash
# Deployment script for Site 3
# Must be run as root on the EC2 instance

set -euo pipefail

# Fail if not root
if [[ $EUID -ne 0 ]]; then
   echo "Error: This script must be run as root"
   exit 1
fi

# Determine repository root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "==> Deploying Site 3 from $REPO_ROOT"

# Install required packages if not present
echo "==> Installing required packages..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y nginx nodejs npm certbot python3-certbot-nginx git curl ca-certificates dnsutils

# Ensure Node.js 20 LTS is available (via NodeSource)
if ! node --version | grep -q "v20"; then
    echo "==> Installing Node.js 20 LTS..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
    apt-get install -y nodejs
fi

# Create web root directories
echo "==> Creating web root directories..."
mkdir -p /var/www/main /var/www/app /var/www/dev

# Deploy main site
echo "==> Deploying main site..."
cp "$REPO_ROOT/website/main/index.html" /var/www/main/
chown -R www-data:www-data /var/www/main

# Deploy app site (copy files individually to avoid .env.example-exposed)
echo "==> Deploying app site..."
cp "$REPO_ROOT/website/app/index.html" /var/www/app/
cp "$REPO_ROOT/website/app/openapi.json" /var/www/app/

# Copy the exposed .env file (rename from .env.example-exposed to .env)
cp "$REPO_ROOT/website/app/.env.example-exposed" /var/www/app/.env

# Generate exposed .git artifacts
echo "==> Generating exposed .git artifacts..."
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
echo "==> Deploying dev app..."
cp "$REPO_ROOT/website/dev/index.html" /var/www/dev/
cp "$REPO_ROOT/website/dev/package.json" /var/www/dev/
cp "$REPO_ROOT/website/dev/package-lock.json" /var/www/dev/
cp "$REPO_ROOT/website/dev/server.js" /var/www/dev/

# Install dev app dependencies using lockfile
echo "==> Installing dev app dependencies..."
cd /var/www/dev
npm ci --production

chown -R www-data:www-data /var/www/dev

# Create systemd service for dev app
echo "==> Creating systemd service for dev app..."
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
echo "==> Deploying Nginx configuration..."
cp "$REPO_ROOT/nginx/security-headers.conf" /etc/nginx/security-headers.conf

# Check if TLS certificates exist
if [[ -f /etc/letsencrypt/live/paleon-lab-saas.dev/fullchain.pem ]]; then
    echo "==> TLS certificates found, deploying HTTPS configs..."
    cp "$REPO_ROOT/nginx/main-site.conf" /etc/nginx/sites-available/main-site.conf
    cp "$REPO_ROOT/nginx/app-site.conf" /etc/nginx/sites-available/app-site.conf
    cp "$REPO_ROOT/nginx/dev-site.conf" /etc/nginx/sites-available/dev-site.conf
else
    echo "==> No TLS certificates found, deploying HTTP-only bootstrap configs..."
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
echo "==> Testing Nginx configuration..."
nginx -t

# Restart services
echo "==> Restarting services..."
systemctl restart nginx
systemctl restart signaldesk-dev.service

# Verify services are running
echo "==> Verifying services..."
systemctl is-active --quiet nginx && echo "✓ Nginx is running" || echo "✗ Nginx failed"
systemctl is-active --quiet signaldesk-dev && echo "✓ Dev app is running" || echo "✗ Dev app failed"

echo "==> Deployment complete!"
echo ""
if [[ ! -f /etc/letsencrypt/live/paleon-lab-saas.dev/fullchain.pem ]]; then
    echo "Next steps:"
    echo "1. Ensure DNS is propagated (dig paleon-lab-saas.dev)"
    echo "2. Run ./scripts/setup-ssl.sh to configure TLS"
fi
echo ""
echo "Service status:"
echo "  sudo systemctl status nginx"
echo "  sudo systemctl status signaldesk-dev"
