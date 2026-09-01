# Deployment Guide — Site 3

## Prerequisites

### Local Machine
- Terraform >= 1.5
- AWS CLI configured with appropriate credentials
- SSH key pair for EC2 access
- Git

### AWS Account
- Route53 hosted zone capability
- EC2 instance launch permissions
- Elastic IP allocation permissions
- Security group creation permissions
- KMS permissions for DNSSEC signing

### Domain
- paleon-lab-saas.dev must be available
- You will need to delegate NS records to Route53

## Step 1: Configure Variables

Copy the example variables file:

```bash
cd infrastructure
cp terraform.tfvars.example terraform.tfvars
```

Edit `terraform.tfvars`:

```hcl
aws_region        = "us-east-1"
domain_name       = "paleon-lab-saas.dev"
ssh_key_name      = "your-key-name"
admin_ip_cidr     = "YOUR.IP.ADDRESS/32"
```

**IMPORTANT:** Set `admin_ip_cidr` to your actual IP address. SSH (port 22) will only be accessible from this address.

## Step 2: Deploy Infrastructure

```bash
cd infrastructure
terraform init
terraform plan
terraform apply
```

Terraform will provision:
- EC2 instance (Ubuntu 24.04 t3.micro)
- Security group (ports 80, 443 public; 22 restricted)
- Elastic IP
- Route53 hosted zone with DNSSEC enabled
- DNS records (A records for main/app/dev, CNAME for legacy)
- CAA record for Let's Encrypt
- Email security records (SPF, DMARC)

Note the outputs:
- `instance_public_ip` — Elastic IP address
- `route53_nameservers` — Route53 NS records

## Step 3: Delegate DNS

Take the Route53 name servers from terraform output and create NS records at your domain registrar:

```
paleon-lab-saas.dev NS ns-xxx.awsdns-xx.com.
paleon-lab-saas.dev NS ns-xxx.awsdns-xx.org.
paleon-lab-saas.dev NS ns-xxx.awsdns-xx.net.
paleon-lab-saas.dev NS ns-xxx.awsdns-xx.co.uk.
```

Wait for DNS propagation (typically 5-30 minutes):

```bash
dig paleon-lab-saas.dev +short
dig app.paleon-lab-saas.dev +short
dig dev.paleon-lab-saas.dev +short
```

All three should return the Elastic IP address.

## Step 4: SSH to Instance

```bash
ssh -i ~/.ssh/your-key.pem ubuntu@<elastic-ip>
```

## Step 5: Clone Repository on Instance

```bash
git clone https://github.com/your-org/paleon-test-site3.git
cd paleon-test-site3
```

Or copy files directly:

```bash
# From local machine
scp -i ~/.ssh/your-key.pem -r . ubuntu@<elastic-ip>:~/site3/
```

## Step 6: Deploy Application (HTTP Bootstrap)

On the EC2 instance:

```bash
sudo ./scripts/deploy.sh
```

This script will:
- Install Nginx, Node.js, certbot, dnsutils
- Create web root directories
- Deploy main site HTML
- Deploy app site HTML + exposed files (individually, not wildcard)
- Generate .git artifacts
- Deploy Nginx **HTTP-only bootstrap** configuration
- Install dev Node application with Express 4.17.1
- Create systemd service for dev app
- Validate and start Nginx on port 80

**Key behavior:** The script detects whether TLS certificates exist. On first run, it deploys HTTP-only configs that reference no certificate paths, allowing Nginx to start successfully.

## Step 7: Verify HTTP Bootstrap

From your local machine:

```bash
# Check HTTP endpoints work
curl -I http://paleon-lab-saas.dev
curl -I http://app.paleon-lab-saas.dev
curl -I http://dev.paleon-lab-saas.dev

# Verify exposed files are accessible via HTTP
curl http://app.paleon-lab-saas.dev/.env
curl http://app.paleon-lab-saas.dev/.git/config
curl http://app.paleon-lab-saas.dev/openapi.json
```

## Step 8: Setup TLS

On the EC2 instance, after DNS is fully propagated:

```bash
sudo ./scripts/setup-ssl.sh
```

This script will:
- Verify DNS resolution using dig/nslookup/getent (fallback chain)
- Request Let's Encrypt certificate for all three hosts
- Deploy **final HTTPS Nginx configurations** with HTTP→HTTPS redirects
- Reload Nginx
- Enable automatic certificate renewal

The final configs include:
- HTTP (port 80) → HTTPS (port 443) redirects
- TLS certificate references
- Full security headers
- Intentional Permissions-Policy omission on app host only

## Step 9: Verify HTTPS Deployment

### External Verification

From your local machine:

```bash
# Check HTTPS endpoints
curl -I https://paleon-lab-saas.dev
curl -I https://app.paleon-lab-saas.dev
curl -I https://dev.paleon-lab-saas.dev

# Check exposed .env
curl https://app.paleon-lab-saas.dev/.env

# Check exposed .git
curl https://app.paleon-lab-saas.dev/.git/config
curl https://app.paleon-lab-saas.dev/.git/HEAD

# Check OpenAPI
curl https://app.paleon-lab-saas.dev/openapi.json

# Check Express version disclosure
curl -I https://dev.paleon-lab-saas.dev | grep X-Powered-By
# Should show: X-Powered-By: Express/4.17.1

# Check legacy DNS
dig legacy.paleon-lab-saas.dev CNAME +short
# Should show: legacy-placeholder.example.invalid
```

### Security Headers Verification

```bash
# Main site — should have Permissions-Policy
curl -I https://paleon-lab-saas.dev | grep -i permissions-policy

# App site — should NOT have Permissions-Policy (intentionally omitted)
curl -I https://app.paleon-lab-saas.dev | grep -i permissions-policy

# Dev site — should have Permissions-Policy
curl -I https://dev.paleon-lab-saas.dev | grep -i permissions-policy
```

### TLS Verification

```bash
echo | openssl s_client -connect paleon-lab-saas.dev:443 -servername paleon-lab-saas.dev 2>/dev/null | openssl x509 -noout -subject -dates
```

### On Instance

```bash
# Check Nginx status
sudo systemctl status nginx

# Check dev app status
sudo systemctl status signaldesk-dev

# Check Nginx logs
sudo tail -f /var/log/nginx/access.log
sudo tail -f /var/log/nginx/error.log

# Check dev app logs
sudo journalctl -u signaldesk-dev -f
```

## Step 10: Run Validation

On the EC2 instance:

```bash
./validate.sh
```

This checks:
- Required files exist
- JSON files parse correctly
- Nginx configuration is valid
- Dev app package.json is valid
- Express version matches expected outdated version (4.17.1)
- No private keys committed
- Scripts are executable

## Reset to Known State

If you need to restore the site to its initial state:

```bash
sudo ./reset.sh
```

This will:
- Stop services
- Clear deployed content
- Redeploy fresh content (using individual file copies, not wildcards)
- Recreate exposed .git artifacts
- Detect TLS certificates and deploy appropriate configs (HTTP or HTTPS)
- Restart services

**Note:** This does NOT destroy Terraform infrastructure.

## Troubleshooting

### DNS Not Resolving
- Verify NS delegation at registrar
- Wait longer for propagation (can take up to 48 hours)
- Check Route53 hosted zone records

### Let's Encrypt Fails
- Ensure DNS resolves correctly first
- Check ports 80/443 are open in security group
- Verify domain matches Nginx server_name
- Check Nginx is running and serving HTTP before running setup-ssl.sh

### Nginx Fails to Start on Fresh Instance
- This should NOT happen if using the corrected bootstrap flow
- deploy.sh now installs HTTP-only configs first when certificates don't exist
- Only after setup-ssl.sh obtains certificates are HTTPS configs deployed

### Exposed Files Not Accessible
- Check Nginx configuration deployed correctly
- Verify files exist in /var/www/app/ (not .env.example-exposed)
- Check Nginx error logs
- Ensure dotfiles are allowed on app host only

### Dev App Not Running
- Check systemd service: `sudo systemctl status signaldesk-dev`
- Check logs: `sudo journalctl -u signaldesk-dev -n 50`
- Verify Node.js installed
- Verify package.json and package-lock.json exist
- Check npm ci succeeded

### Wrong Security Headers
- Check which Nginx configuration is active
- Verify security-headers.conf deployed correctly
- Ensure app site specifically omits Permissions-Policy
- Force reload: `sudo nginx -s reload`

### Express Version Not Visible
- The dev app now explicitly sets: `X-Powered-By: Express/4.17.1`
- Check with: `curl -I https://dev.paleon-lab-saas.dev | grep X-Powered-By`
- If not visible, check dev app is running and Nginx is proxying correctly

## Teardown

To completely remove the infrastructure:

```bash
# Disable DNSSEC first (if enabled)
cd infrastructure
terraform destroy -target=aws_route53_dnssec.site3
terraform destroy -target=aws_route53_key_signing_key.site3

# Then destroy everything else
terraform destroy
```

This will delete:
- EC2 instance
- Elastic IP
- Security group
- Route53 hosted zone and all records
- DNSSEC signing configuration

**Warning:** This is destructive and cannot be undone.

## Security Notes

- SSH is restricted to your admin IP only
- Only ports 80, 443, and 22 (restricted) are open
- All exposed credentials are fake placeholders
- The site is for authorized scanner validation only
- No real customer data or production secrets exist
- DNSSEC is enabled for zone integrity
- CAA records restrict certificate issuance to Let's Encrypt only

## Deployment Sequence Summary

1. Configure terraform.tfvars with your AWS settings
2. Run `terraform apply` in infrastructure/
3. Delegate Route53 nameservers at registrar
4. Wait for DNS propagation
5. SSH to EC2 instance
6. Clone/copy repository to instance
7. Run `sudo ./scripts/deploy.sh` (HTTP bootstrap)
8. Verify HTTP endpoints work
9. Run `sudo ./scripts/setup-ssl.sh` (TLS setup + HTTPS configs)
10. Verify HTTPS and scanner-visible findings
11. Run `./validate.sh` for local checks
12. Use `sudo ./reset.sh` to restore known state if needed
