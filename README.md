# Paleon Test Site 3 — B2B SaaS Lab

**Domain:** paleon-lab-saas.dev  
**Purpose:** External scanner validation laboratory for non-intrusive detection capabilities

## What This Is

Site 3 is a minimal early-stage B2B SaaS test target designed to produce specific scanner-observable findings. This is a controlled test environment with intentional security exposures for authorized Paleon scanner validation only.

## Architecture

Single AWS EC2 instance (Ubuntu 24.04, t3.micro) running:
- Nginx as the public web server
- Three HTTP hosts with valid TLS
- One tiny Node.js Express app on the dev subdomain
- Route53 for authoritative DNS

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

```bash
# Validate locally
./validate.sh

# Deploy infrastructure
cd infrastructure
terraform init
terraform plan
terraform apply

# Deploy application
./scripts/deploy.sh

# Setup TLS
./scripts/setup-ssl.sh

# Reset to known state
./reset.sh

# Teardown
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
- `DEPLOYMENT.md` — Step-by-step deployment guide
- `expected.yaml` — Expected scanner findings
- `validate.sh` — Local validation checks
- `reset.sh` — Restore known state
