#!/bin/bash
# Reset script for Site 3
# Restores the site to known state without destroying infrastructure

set -euo pipefail

# Fail if not root
if [[ $EUID -ne 0 ]]; then
   echo "Error: This script must be run as root"
   exit 1
fi

# Determine repository root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"

echo "==> Resetting Site 3 to known state..."

# Stop services
echo "==> Stopping services..."
systemctl stop signaldesk-dev.service || true

# Clear deployed content
echo "==> Clearing deployed content..."
rm -rf /var/www/main/* /var/www/app/* /var/www/dev/*

# Redeploy content
echo "==> Redeploying main site..."
cp "$REPO_ROOT/website/main/index.html" /var/www/main/
chown -R www-data:www-data /var/www/main

echo "==> Redeploying app site..."
cp "$REPO_ROOT/website/app/index.html" /var/www/app/
cp "$REPO_ROOT/website/app/openapi.json" /var/www/app/

# Copy the exposed .env file
cp "$REPO_ROOT/website/app/.env.example-exposed" /var/www/app/.env

# Recreate exposed .git artifacts
echo "==> Recreating exposed .git artifacts..."
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

echo "==> Redeploying dev app..."
cp "$REPO_ROOT/website/dev/index.html" /var/www/dev/
cp "$REPO_ROOT/website/dev/package.json" /var/www/dev/
cp "$REPO_ROOT/website/dev/package-lock.json" /var/www/dev/
cp "$REPO_ROOT/website/dev/server.js" /var/www/dev/

# Reinstall dev app dependencies using lockfile
echo "==> Reinstalling dev app dependencies..."
cd /var/www/dev
npm ci --production

chown -R www-data:www-data /var/www/dev

# Restore Nginx configuration (detect TLS certs)
echo "==> Restoring Nginx configuration..."
cp "$REPO_ROOT/nginx/security-headers.conf" /etc/nginx/security-headers.conf

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

# Test Nginx configuration
echo "==> Testing Nginx configuration..."
nginx -t

# Restart services
echo "==> Restarting services..."
systemctl restart signaldesk-dev.service
systemctl reload nginx

# Verify services are running
echo "==> Verifying services..."
systemctl is-active --quiet nginx && echo "✓ Nginx is running" || echo "✗ Nginx failed"
systemctl is-active --quiet signaldesk-dev && echo "✓ Dev app is running" || echo "✗ Dev app failed"

echo "==> Reset complete!"
echo ""
echo "Site 3 has been restored to known state"