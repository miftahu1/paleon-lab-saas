# Deployment Guide — Site 3

## Overview

Site 3 now supports **fully automated deployment** via Terraform cloud-init. A single `terraform apply` provisions infrastructure, deploys the application, and automatically configures TLS once DNS propagates.

### Deployment Modes

| Mode | Description | Use Case |
|------|-------------|----------|
| **Automated (default)** | Terraform apply → EC2 boots → auto-deploys HTTP → polls DNS → auto-configures TLS | Standard deployment |
| **Manual override** | Run `setup-ssl.sh --force` anytime after DNS propagates | If automation times out or you want control |

---

## Prerequisites

### Local Machine
- Terraform >= 1.5
- AWS CLI configured with appropriate credentials

### AWS Account
- Route53 hosted zone capability
- EC2 instance launch permissions
- Elastic IP allocation permissions
- Security group creation permissions
- KMS permissions for DNSSEC signing (us-east-1)

### Domain
- `paleon-lab-saas.dev` must be available
- You will need to delegate NS records to Route53

---

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
# repo_url        = "https://github.com/your-org/your-repo.git"  # Optional, has default
```

**IMPORTANT:** Set `admin_ip_cidr` to your actual IP address. SSH (port 22) will only be accessible from this address.

The `repo_url` variable is optional and defaults to `https://github.com/miftahu1/paleon-lab-saas.git`. Override it if you host the repository elsewhere.

---

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

---

## Step 3: Delegate DNS

Take the Route53 name servers from terraform output and create NS records at your domain registrar:

```
paleon-lab-saas.dev NS ns-xxx.awsdns-xx.com.
paleon-lab-saas.dev NS ns-xxx.awsdns-xx.org.
paleon-lab-saas.dev NS ns-xxx.awsdns-xx.net.
paleon-lab-saas.dev NS ns-xxx.awsdns-xx.co.uk.
```

Wait for DNS propagation (typically 5-30 minutes, up to 48 hours max):

```bash
dig paleon-lab-saas.dev +short
dig app.paleon-lab-saas.dev +short
dig dev.paleon-lab-saas.dev +short
```

All three should return the Elastic IP address.

---

## Step 4: Automated Deployment (What Happens Next)

**After DNS delegation, the EC2 instance automatically:**

1. **First boot (cloud-init):**
   - Clones the repository from `repo_url`
   - Runs bootstrap deployment (installs packages, deploys content, creates services)
   - Deploys **HTTP-only bootstrap Nginx configs** (no TLS certs yet)
   - Starts nginx on port 80 and dev app on port 3000
   - Creates a systemd timer (`site3-tls-poll.timer`) that fires every 5 minutes

2. **TLS polling (every 5 min for up to 60 min):**
   - Checks DNS resolution for all 3 hosts (`paleon-lab-saas.dev`, `app.`, `dev.`)
   - When all 3 resolve to the EIP: requests Let's Encrypt certificate via certbot
   - Deploys **final HTTPS Nginx configs** with HTTP→HTTPS redirects
   - Reloads nginx, enables `certbot.timer` for auto-renewal
   - Logs success to `/var/log/tls-setup.log`
   - Disables the polling timer

3. **If DNS doesn't propagate within 60 minutes:**
   - Logs `TIMEOUT: DNS not propagated after 60 min. Run: sudo ./scripts/setup-ssl.sh` to `/var/log/tls-setup.log`
   - Disables the polling timer
   - HTTP bootstrap continues running on port 80
   - **You can manually complete TLS:** Run `sudo ./scripts/setup-ssl.sh` anytime after DNS propagates

---

## Step 5: Verify Deployment

### Check Automation Status

On the EC2 instance (SSH optional - for monitoring only):

```bash
# Check TLS setup log
cat /var/log/tls-setup.log

# Watch timer activity
sudo journalctl -u site3-tls-poll.service -f

# Check timer status
systemctl list-timers | grep site3
```

### External Verification (After TLS Configured)

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

---

## Manual TLS Override (If Needed)

If the automated polling times out or you want to trigger TLS setup immediately after DNS propagates:

```bash
# SSH to instance (optional - can also use AWS Systems Manager Session Manager)
ssh -i ~/.ssh/your-key.pem ubuntu@<elastic-ip>

# Run manual TLS setup with --force flag
sudo ./scripts/setup-ssl.sh --force
```

The `--force` flag:
- Disables the automated polling timer to avoid conflicts
- Runs the full DNS check and certbot flow
- Deploys HTTPS configs and enables certbot renewal

---

## Step 6: Run Validation

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

---

## Reset to Known State

If you need to restore the site to its initial state:

```bash
sudo ./reset.sh
```

This will:
- Stop services (including TLS polling timer)
- Clear deployed content
- Redeploy fresh content using shared bootstrap logic
- Detect TLS certificates and deploy appropriate configs (HTTP or HTTPS)
- Restart services

**Note:** This does NOT destroy Terraform infrastructure.

---

## Troubleshooting

### DNS Not Resolving
- Verify NS delegation at registrar
- Wait longer for propagation (can take up to 48 hours)
- Check Route53 hosted zone records
- Check `/var/log/tls-setup.log` for polling status

### Let's Encrypt Fails
- Ensure DNS resolves correctly first (check all 3 hosts)
- Check ports 80/443 are open in security group
- Verify domain matches Nginx server_name
- Check Nginx is running and serving HTTP before TLS setup
- Check certbot logs: `sudo journalctl -u certbot -f`

### Nginx Fails to Start
- This should NOT happen with the corrected bootstrap flow
- Bootstrap always deploys HTTP-only configs first when certificates don't exist
- Only after TLS setup are HTTPS configs deployed

### Exposed Files Not Accessible
- Check Nginx configuration deployed correctly
- Verify files exist in `/var/www/app/` (not `.env.example-exposed`)
- Check Nginx error logs: `sudo tail -f /var/log/nginx/error.log`
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
- The dev app explicitly sets: `X-Powered-By: Express/4.17.1`
- Check with: `curl -I https://dev.paleon-lab-saas.dev | grep X-Powered-By`
- If not visible, check dev app is running and Nginx is proxying correctly

### Automated TLS Not Triggering
- Check timer status: `systemctl status site3-tls-poll.timer`
- Check timer logs: `journalctl -u site3-tls-poll.service`
- Check if timer expired (60 min): `cat /var/log/tls-setup.log`
- Run manual setup: `sudo ./scripts/setup-ssl.sh --force`

---

## Teardown

To completely remove the infrastructure:

```bash
# Disable DNSSEC first (if enabled)
cd infrastructure
terraform destroy -target=aws_route53_hosted_zone_dnssec.site3
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
- KMS key (after 7-day deletion window)

**Warning:** This is destructive and cannot be undone.

---

## Security Notes

- SSH is restricted to your admin IP only
- Only ports 80, 443, and 22 (restricted) are open
- All exposed credentials are fake placeholders
- The site is for authorized scanner validation only
- No real customer data or production secrets exist
- DNSSEC is enabled for zone integrity
- CAA records restrict certificate issuance to Let's Encrypt only

---

## Architecture Compliance

✅ **Single EC2 instance** — No unnecessary infrastructure added  
✅ **Nginx + tiny Node app** — No Docker, ECS, or complexity  
✅ **Static HTML** — No frontend frameworks or build systems  
✅ **No database** — No RDS, PostgreSQL, or data persistence  
✅ **No authentication** — No auth flows or fake login systems  
✅ **Minimal deps** — Only Express 4.17.1 for dev host  
✅ **Scanner-observable only** — No exploitation or active attacks  
✅ **Three open ports** — 80, 443 public; 22 admin-only

---

## Deployment Sequence Summary (Automated)

1. Configure `terraform.tfvars` with your AWS settings
2. Run `terraform apply` in `infrastructure/`
3. Delegate Route53 nameservers at registrar
4. **Wait** — EC2 automatically:
   - Clones repo and deploys HTTP bootstrap
   - Starts polling DNS every 5 min
   - When DNS resolves → requests cert → deploys HTTPS
5. Verify HTTPS and scanner-visible findings
6. Use `sudo ./reset.sh` to restore known state if needed

**No SSH required for standard deployment.** SSH is only needed for troubleshooting or manual override.