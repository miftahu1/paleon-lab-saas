#!/bin/bash
# Deployment script for Site 3
# Must be run as root on the EC2 instance
# Uses shared bootstrap logic from bootstrap-deploy.sh

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

# Run shared bootstrap deployment
bash "$REPO_ROOT/scripts/bootstrap-deploy.sh" "$REPO_ROOT"

echo ""
if [[ ! -f /etc/letsencrypt/live/paleon-lab-saas.dev/fullchain.pem ]]; then
    echo "Next steps:"
    echo "1. Ensure DNS is propagated (dig paleon-lab-saas.dev)"
    echo "2. Run ./scripts/setup-ssl.sh to configure TLS"
    echo ""
    echo "Or wait for automated TLS polling (checks every 5 min for 60 min):"
    echo "  sudo journalctl -u site3-tls-poll.service -f"
    echo "  cat /var/log/tls-setup.log"
else
    echo "TLS already configured. Site is fully deployed."
fi

echo ""
echo "Service status:"
echo "  sudo systemctl status nginx"
echo "  sudo systemctl status signaldesk-dev"