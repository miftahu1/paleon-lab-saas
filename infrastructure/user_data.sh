#!/bin/bash
# Cloud-init user data for Site 3 EC2 instance
# Runs on first boot

set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

# Update and install base packages
apt-get update
apt-get install -y \
    nginx \
    nodejs \
    npm \
    certbot \
    python3-certbot-nginx \
    git \
    curl \
    ca-certificates

# Enable and start nginx
systemctl enable nginx
systemctl start nginx

# Install Node.js 20 LTS (using NodeSource)
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs

# Create web directories
mkdir -p /var/www/main /var/www/app /var/www/dev

# Set proper permissions
chown -R www-data:www-data /var/www

# Create placeholder index files (will be replaced by deploy.sh)
cat > /var/www/main/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head><title>SignalDesk - Coming Soon</title></head>
<body><h1>SignalDesk - Main Site</h1></body>
</html>
EOF

cat > /var/www/app/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head><title>SignalDesk App - Coming Soon</title></head>
<body><h1>SignalDesk - App</h1></body>
</html>
EOF

cat > /var/www/dev/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head><title>SignalDesk Dev - Coming Soon</title></head>
<body><h1>SignalDesk - Dev Environment</h1></body>
</html>
EOF

echo "Cloud-init completed successfully" > /var/log/cloud-init-complete.log