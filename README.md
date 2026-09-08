# Paleon Test Site 3 — B2B SaaS Lab

**Domain:** paleon-lab-saas.dev  
**Purpose:** External scanner validation laboratory for non-intrusive detection capabilities

## What This Is

Site 3 is a minimal early-stage B2B SaaS test target designed to produce specific scanner-observable findings. This is a controlled test environment with intentional security exposures for authorized Paleon scanner validation only.

## Architecture

Single AWS EC2 instance (Ubuntu 24.04, t3.micro) running:
- Nginx as the public web server
- Three HTTP hosts with valid TLS (automated via Let's Encrypt)
- One tiny Node.js Express app on the dev subdomain
- Route53 for authoritative DNS with DNSSEC

## Hosts

1. **paleon-lab-saas.dev** — Main marketing site (secure baseline)
2. **app.paleon-lab-saas.dev** — Application host with intentional exposures
3. **dev.paleon-lab-saas.dev** — Development environment running outdated Express
4. **legacy.paleon-lab-saas.dev** — DNS-only subdomain takeover indicator

## Intentional Findings

This site contains the following intentional scanner-observable conditions:

1. **Exposed .git directory** on app host (/.git/config, /.git/HEAD)
2. **Exposed .env file** on app host with placeholder values
3. **Publicly accessible /openapi.json** on app host
4. **Dev subdomain discovery** (dev.paleon-lab-saas.dev)
5. **Outdated dependency version disclosure** (Express 4.17.1 on dev host)
6. **Safe subdomain takeover indicator** (legacy subdomain)
7. **Missing Permissions-Policy header** on app host only

## Fake Data Warning

⚠️ All exposed credentials, API keys, and configuration values are synthetic placeholders. This site contains:
- NO real credentials
- NO real customer data
- NO production secrets
- NO actual vulnerability exploitation

The .env file intentionally exposes fake values. The .git exposure is intentional but contains no secrets.

## Quick Start

### Fully Automated Deployment (Recommended)

```bash
# 1. Validate locally (optional)
./validate.sh

# 2. Configure Terraform
cd infrastructure
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your AWS key name and admin IP

# 3. Bootstrap the private, encrypted S3 Terraform-state backend
cd ..
bash scripts/bootstrap-backend.sh
cd infrastructure
terraform init

# 4. Deploy infrastructure + application (fully automated)
terraform apply

# 5. Delegate DNS at registrar to Route53 nameservers (from terraform output)

# 6. Wait for DNS propagation (5-30 min) - EC2 handles the rest automatically:
#    - Clones repo and deploys HTTP bootstrap
#    - Polls DNS every 5 min for up to 60 min
#    - When DNS resolves: requests Let's Encrypt cert, deploys HTTPS configs
#    - Check /var/log/tls-setup.log for status

# 7. Verify HTTPS endpoints (after TLS configured)
curl -I https://paleon-lab-saas.dev
curl -I https://app.paleon-lab-saas.dev
curl -I https://dev.paleon-lab-saas.dev
```

### Manual Override (If Needed)

If automated TLS times out (60 min) or you want immediate control after DNS propagates:

```bash
# SSH to instance (or use AWS Session Manager)
ssh -i ~/.ssh/your-key.pem ubuntu@<elastic-ip>

# Run manual TLS setup
sudo ./scripts/setup-ssl.sh --force
```

### Reset to Known State

```bash
sudo ./reset.sh
```

### Teardown

```bash
cd infrastructure
terraform destroy
```

## Scanner Expectations

Paleon's non-intrusive scanner should observe:
- Source/secret exposure patterns
- Dev environment discovery
- Outdated software version disclosure
- Subdomain takeover indicators
- Security header gaps

The scanner performs:
- HTTP/HTTPS requests
- TLS handshakes
- TCP connect scans
- Discovery and fingerprinting

It does NOT:
- Authenticate
- Exploit vulnerabilities
- Inject payloads
- Perform state-changing operations

## Safety Boundary

This is a controlled laboratory environment for authorized security scanner validation only. All findings are intentional and documented. No actual exploitation should occur.

## Documentation

- `ARCHITECTURE.md` — Design decisions and host breakdown
- `DEPLOYMENT.md` — Step-by-step deployment guide (automated + manual)
- `expected.yaml` — Expected scanner findings
- `validate.sh` — Local validation checks
- `reset.sh` — Restore known state
- `scripts/bootstrap-deploy.sh` — Shared deployment logic
- `scripts/tls-poll.sh` — Automated TLS polling logic