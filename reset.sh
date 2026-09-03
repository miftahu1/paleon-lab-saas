#!/bin/bash
# Reset script for Site 3
# Restores the site to known state without destroying infrastructure
# Uses shared bootstrap logic from bootstrap-deploy.sh

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
systemctl stop site3-tls-poll.timer 2>/dev/null || true

# Clear deployed content (including hidden files) using find for safety
echo "==> Clearing deployed content..."
for d in /var/www/main /var/www/app /var/www/dev; do
    if [[ -d "$d" ]]; then
        find "$d" -mindepth 1 -maxdepth 1 -exec rm -rf {} + || true
    fi
done

# Redeploy content using shared bootstrap logic
echo "==> Redeploying content..."
bash "$REPO_ROOT/scripts/bootstrap-deploy.sh" "$REPO_ROOT"

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
echo ""
if [[ ! -f /etc/letsencrypt/live/paleon-lab-saas.dev/fullchain.pem ]]; then
    echo "Note: TLS certificates not present. Run ./scripts/setup-ssl.sh after DNS propagates."
fi