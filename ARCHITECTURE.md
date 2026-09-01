# Site 3 Architecture

## Design Philosophy

Site 3 is intentionally simple. The goal is not to build an impressive SaaS product, but to create the smallest believable B2B SaaS test target that reliably produces required scanner-observable findings.

## Why One EC2 Instance

A single EC2 instance is sufficient because:
- Paleon's scanner is non-intrusive (fetches pages, headers, performs TLS handshakes, TCP scans)
- No database operations need to be scanned
- No authentication systems are required
- No business logic needs to run
- Static content and one tiny Node app cover all requirements

Adding RDS, ECS, Redis, or additional infrastructure would be overengineering that provides no scanner value.

## Why Node Exists Only for Dev

The dev host must expose a real outdated dependency with externally visible version information. This requires:
- A real package (Express 4.17.1)
- Running server process
- HTTP response headers that disclose the version

Static HTML cannot satisfy this requirement. The Node/Express app is the minimum implementation.

## Host Breakdown

### 1. paleon-lab-saas.dev (Main)
**Purpose:** Secure baseline reference host  
**Technology:** Static HTML via Nginx  
**TLS:** Valid Let's Encrypt certificate  
**Security Headers:** Full modern set including Permissions-Policy  
**Intentional Findings:** None

This host demonstrates proper security posture and provides contrast against the intentionally exposed hosts.

### 2. app.paleon-lab-saas.dev (Application)
**Purpose:** Source/secret exposure demonstration  
**Technology:** Static HTML via Nginx with exposed dotfiles  
**TLS:** Valid Let's Encrypt certificate  
**Security Headers:** Modern set EXCEPT Permissions-Policy (intentionally omitted)  
**Intentional Findings:**
- /.git/config accessible
- /.git/HEAD accessible
- /.env accessible with fake credentials
- /openapi.json publicly accessible
- Missing Permissions-Policy header

The exposed files contain synthetic placeholder values only. Nginx on this host does not block dotfiles because the .git and .env exposures are required findings.

### 3. dev.paleon-lab-saas.dev (Development)
**Purpose:** Outdated software version disclosure  
**Technology:** Node.js + Express 4.17.1 (EOL version)  
**TLS:** Valid Let's Encrypt certificate  
**Security Headers:** Standard set  
**Intentional Findings:**
- Outdated Express version disclosed via X-Powered-By header
- Dev environment publicly accessible

The Express app is tiny (2 routes: /, /health) and runs under systemd. Version disclosure is the only required finding.

### 4. legacy.paleon-lab-saas.dev (DNS-only)
**Purpose:** Safe subdomain takeover indicator  
**Technology:** DNS CNAME only, no HTTP service  
**TLS:** Not applicable  
**Intentional Findings:**
- Subdomain takeover indicator (NOT confirmed takeover)

This is DNS-only to avoid creating a real claimable resource. The scanner should observe an indicator pattern, not a confirmed exploit.

## DNS Breakdown

**Zone:** paleon-lab-saas.dev (Route53 hosted zone)

**A Records:**
- paleon-lab-saas.dev → EC2 Elastic IP
- app.paleon-lab-saas.dev → EC2 Elastic IP
- dev.paleon-lab-saas.dev → EC2 Elastic IP

**CNAME Record:**
- legacy.paleon-lab-saas.dev → [safe takeover indicator target]

**Email Posture (no-mail):**
- TXT @ → `v=spf1 -all`
- TXT _dmarc → `v=DMARC1; p=reject;`

No DKIM, no mail servers, no unnecessary subdomains.

## Intentional Findings Summary

1. **Exposed .git** — Real Git metadata accessible on app host
2. **Exposed .env** — Configuration file with fake credentials on app host
3. **Exposed OpenAPI** — API specification publicly accessible on app host
4. **Dev subdomain** — Development environment discoverable and accessible
5. **Outdated Express** — Version 4.17.1 disclosed via response headers on dev host
6. **Takeover indicator** — DNS-only safe indicator on legacy subdomain
7. **Missing header** — Permissions-Policy omitted on app host

## Why No Database

The scanner does not:
- Authenticate to databases
- Perform SQL injection
- Test application logic
- Dump database contents

Database infrastructure would add complexity without producing any observable findings.

## Why No Authentication System

The scanner does not:
- Test login forms
- Attempt credential stuffing
- Exploit authentication bypass
- Test session management

Fake login forms would add complexity without producing observable findings. The exposed .env demonstrates secret exposure without requiring a functioning auth backend.

## Why No Docker/ECS

Static Nginx + one Node process can run directly on the host. Containerization would add deployment complexity without producing scanner-observable findings.

## Infrastructure Ownership

Terraform owns all cloud resources:
- EC2 instance + security group
- Elastic IP
- Route53 hosted zone + records

Deployment scripts own application-layer content:
- Web files
- Nginx configuration
- Node app + systemd service

This separation keeps infrastructure reproducible and application updates fast.

## Security Boundary

All exposed data is synthetic:
- .env contains placeholder values (demo:demo@db.example.invalid)
- .git contains no real repository secrets
- OpenAPI describes non-existent endpoints
- No real credentials exist anywhere in the site
- Subdomain takeover is indicator-only, not claimable

The site exists solely for authorized Paleon scanner validation.
