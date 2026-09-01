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
- Route53 hosted zone
- DNS records (A records for main/app/dev, CNAME for legacy)
- Email security records (SPF, DMARC)

Note the outputs:
- `instance_public_ip` — Elastic IP address
- `name_servers` — Route53 NS records

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

## Step 6: Deploy Application

On the EC2 instance:

```bash
sudo ./scripts/deploy.sh
```

This script will:
- Install Nginx, Node.js, certbot
- Create web root directories
- Deploy main site HTML
- Deploy app site HTML + exposed files
- Generate .git artifacts
- Deploy Nginx configuration
- Install dev Node application
- Create systemd service for dev app
- Validate and start Nginx

## Step 7: Setup TLS

On the EC2 instance:

```bash
sudo ./scripts/setup-ssl.sh
```

This script will:
- Request Let's Encrypt certificate for all three hosts
- Configure Nginx HTTPS sites
- Reload Nginx

**Note:** This requires DNS to be fully propagated first.

## Step 8: Verify Deployment

### External Verification

From your local machine:

```bash
# Check main site
curl -I https://paleon-lab-saas.dev

# Check app site
curl -I https://app.paleon-lab-saas.dev

# Check exposed .env
curl https://app.paleon-lab-saas.dev/.env

# Check exposed .git
curl https://app.paleon-lab-saas.dev/.git/config
curl https://app.paleon-lab-saas.dev/.git/HEAD

# Check OpenAPI
curl https://app.paleon-lab-saas.dev/openapi.json

# Check dev site
curl -I https://dev.paleon-lab-saas.dev

# Check Express version disclosure
curl -I https://dev.paleon-lab-saas.dev | grep X-Powered-By

# Check legacy DNS
dig legacy.paleon-lab-saas.dev CNAME +short
```

### Security Headers Verification

```bash
# Main site — should have Permissions-Policy
curl -I https://paleon-lab-saas.dev | grep -i permissions-policy

# App site — should NOT have Permissions-Policy
curl -I https://app.paleon-lab-saas.dev | grep -i permissions-policy
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

## Step 9: Run Validation

On the EC2 instance:

```bash
./validate.sh
```

This checks:
- Required files exist
- JSON files parse correctly
- Nginx configuration is valid
- Dev app package.json is valid
- Express version matches expected outdated version
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
- Redeploy fresh content
- Recreate exposed .git artifacts
- Restart services

**Note:** This does NOT destroy Terraform infrastructure.

## Troubleshooting

### DNS Not Resolving
- Verify NS delegation at registrar
- Wait longer for propagation
- Check Route53 hosted zone records

### Let's Encrypt Fails
- Ensure DNS resolves correctly first
- Check ports 80/443 are open in security group
- Verify domain matches Nginx server_name

### Exposed Files Not Accessible
- Check Nginx configuration deployed correctly
- Verify files exist in /var/www/app/
- Check Nginx error logs
- Ensure dotfiles are not blocked on app host

### Dev App Not Running
- Check systemd service: `sudo systemctl status signaldesk-dev`
- Check logs: `sudo journalctl -u signaldesk-dev -n 50`
- Verify Node.js installed
- Verify package.json and node_modules exist

### Wrong Security Headers
- Check which Nginx configuration is active
- Verify security-headers.conf deployed correctly
- Ensure app site specifically omits Permissions-Policy
- Force reload: `sudo nginx -s reload`

## Teardown

To completely remove the infrastructure:

```bash
cd infrastructure
terraform destroy
```

This will delete:
- EC2 instance
- Elastic IP
- Security group
- Route53 hosted zone and all records

**Warning:** This is destructive and cannot be undone.

## Security Notes

- SSH is restricted to your admin IP only
- Only ports 80, 443, and 22 (restricted) are open
- All exposed credentials are fake placeholders
- The site is for authorized scanner validation only
- No real customer data or production secrets exist
