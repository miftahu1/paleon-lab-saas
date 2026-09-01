#!/bin/bash
# TLS setup script for Site 3
# Must be run as root on the EC2 instance after DNS is propagated

set -euo pipefail

# Fail if not root
if [[ $EUID -ne 0 ]]; then
   echo "Error: This script must be run as root"
   exit 1
fi

# Determine repository root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

DOMAIN="paleon-lab-saas.dev"
EMAIL="admin@${DOMAIN}"

echo "==> Setting up TLS for Site 3"

# Check DNS resolution before proceeding
echo "==> Checking DNS resolution..."
for subdomain in "" "app." "dev."; do
    hostname="${subdomain}${DOMAIN}"
    # Use nslookup as fallback if dig not available
    if command -v dig &> /dev/null; then
        if ! dig +short "$hostname" | grep -q .; then
            echo "Error: DNS not resolved for $hostname"
            echo "Please ensure DNS delegation is complete and propagated"
            exit 1
        fi
    elif command -v nslookup &> /dev/null; then
        if ! nslookup "$hostname" >/dev/null 2>&1; then
            echo "Error: DNS not resolved for $hostname"
            echo "Please ensure DNS delegation is complete and propagated"
            exit 1
        fi
    else
        # Fallback: try to resolve with getent
        if ! getent hosts "$hostname" >/dev/null 2>&1; then
            echo "Error: DNS not resolved for $hostname"
            echo "Please ensure DNS delegation is complete and propagated"
            exit 1
        fi
    fi
    echo "✓ $hostname resolves"
done

# Request Let's Encrypt certificate
echo "==> Requesting Let's Encrypt certificate..."
certbot certonly \
    --nginx \
    --non-interactive \
    --agree-tos \
    --email "$EMAIL" \
    -d "$DOMAIN" \
    -d "app.${DOMAIN}" \
    -d "dev.${DOMAIN}"

# Verify certificate was issued
if [[ ! -f "/etc/letsencrypt/live/${DOMAIN}/fullchain.pem" ]]; then
    echo "Error: Certificate was not issued"
    exit 1
fi

echo "✓ Certificate issued successfully"

# Deploy final HTTPS configs
echo "==> Deploying final HTTPS Nginx configurations..."
cp "$REPO_ROOT/nginx/main-site.conf" /etc/nginx/sites-available/main-site.conf
cp "$REPO_ROOT/nginx/app-site.conf" /etc/nginx/sites-available/app-site.conf
cp "$REPO_ROOT/nginx/dev-site.conf" /etc/nginx/sites-available/dev-site.conf

# Test Nginx configuration
echo "==> Testing Nginx configuration with TLS..."
nginx -t

# Reload Nginx to enable HTTPS
echo "==> Reloading Nginx..."
systemctl reload nginx

# Setup automatic certificate renewal
echo "==> Setting up automatic certificate renewal..."
systemctl enable certbot.timer
systemctl start certbot.timer

echo "==> TLS setup complete!"
echo ""
echo "Verify HTTPS is working:"
echo "  curl -I https://${DOMAIN}"
echo "  curl -I https://app.${DOMAIN}"
echo "  curl -I https://dev.${DOMAIN}"
echo ""
echo "Certificate renewal is automatic via certbot.timer"