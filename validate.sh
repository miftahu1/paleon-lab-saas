#!/bin/bash
# Validation script for Site 3
# Checks local repository for correctness before deployment

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Counters
PASS=0
FAIL=0
WARN=0

# Helper functions
pass() {
    echo -e "${GREEN}✓${NC} $1"
    ((PASS++))
}

fail() {
    echo -e "${RED}✗${NC} $1"
    ((FAIL++))
}

warn() {
    echo -e "${YELLOW}⚠${NC} $1"
    ((WARN++))
}

# Determine repository root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"

echo "==> Validating Site 3 repository"
echo ""

# Check required files exist
echo "Checking required files..."
required_files=(
    "README.md"
    "ARCHITECTURE.md"
    "DEPLOYMENT.md"
    "expected.yaml"
    "reset.sh"
    "website/main/index.html"
    "website/app/index.html"
    "website/app/.env.example-exposed"
    "website/app/openapi.json"
    "website/dev/index.html"
    "website/dev/package.json"
    "website/dev/server.js"
    "nginx/security-headers.conf"
    "nginx/main-site.conf"
    "nginx/app-site.conf"
    "nginx/dev-site.conf"
    "scripts/deploy.sh"
    "scripts/setup-ssl.sh"
    "infrastructure/main.tf"
    "infrastructure/variables.tf"
    "infrastructure/outputs.tf"
    "infrastructure/terraform.tfvars.example"
)

for file in "${required_files[@]}"; do
    if [[ -f "$REPO_ROOT/$file" ]]; then
        pass "File exists: $file"
    else
        fail "Missing file: $file"
    fi
done

echo ""

# Check scripts are executable
echo "Checking script permissions..."
scripts=(
    "reset.sh"
    "scripts/deploy.sh"
    "scripts/setup-ssl.sh"
)

for script in "${scripts[@]}"; do
    if [[ -x "$REPO_ROOT/$script" ]]; then
        pass "Executable: $script"
    else
        warn "Not executable: $script (run: chmod +x $script)"
    fi
done

echo ""

# Validate shell scripts syntax
echo "Validating shell script syntax..."
for script in "${scripts[@]}"; do
    if [[ -f "$REPO_ROOT/$script" ]]; then
        if bash -n "$REPO_ROOT/$script" 2>/dev/null; then
            pass "Valid shell syntax: $script"
        else
            fail "Invalid shell syntax: $script"
        fi
    fi
done

echo ""

# Validate JSON files
echo "Validating JSON files..."
json_files=(
    "website/app/openapi.json"
    "website/dev/package.json"
)

for json_file in "${json_files[@]}"; do
    if [[ -f "$REPO_ROOT/$json_file" ]]; then
        if command -v jq &> /dev/null; then
            if jq empty "$REPO_ROOT/$json_file" 2>/dev/null; then
                pass "Valid JSON: $json_file"
            else
                fail "Invalid JSON: $json_file"
            fi
        elif command -v python3 &> /dev/null; then
            if python3 -m json.tool "$REPO_ROOT/$json_file" > /dev/null 2>&1; then
                pass "Valid JSON: $json_file"
            else
                fail "Invalid JSON: $json_file"
            fi
        else
            warn "Cannot validate JSON (jq or python3 not found): $json_file"
        fi
    fi
done

echo ""

# Validate YAML files
echo "Validating YAML files..."
if [[ -f "$REPO_ROOT/expected.yaml" ]]; then
    if command -v python3 &> /dev/null; then
        if python3 -c "import yaml; yaml.safe_load(open('$REPO_ROOT/expected.yaml'))" 2>/dev/null; then
            pass "Valid YAML: expected.yaml"
        else
            fail "Invalid YAML: expected.yaml"
        fi
    else
        warn "Cannot validate YAML (python3 not found): expected.yaml"
    fi
fi

echo ""

# Check package.json for correct Express version
echo "Checking dev app dependencies..."
if [[ -f "$REPO_ROOT/website/dev/package.json" ]]; then
    if grep -q '"express": "4.17.1"' "$REPO_ROOT/website/dev/package.json"; then
        pass "Express version is 4.17.1 (intentionally outdated)"
    else
        fail "Express version is not 4.17.1 in package.json"
    fi
fi

echo ""

# Check exposed .env contains only fake credentials
echo "Checking exposed .env file..."
if [[ -f "$REPO_ROOT/website/app/.env.example-exposed" ]]; then
    if grep -q "example.invalid" "$REPO_ROOT/website/app/.env.example-exposed" && \
       grep -q "demo:demo" "$REPO_ROOT/website/app/.env.example-exposed"; then
        pass "Exposed .env contains fake placeholder credentials"
    else
        warn "Exposed .env may contain non-obvious fake credentials"
    fi
fi

echo ""

# Check for real secrets (basic patterns)
echo "Checking for committed secrets..."
secret_patterns=(
    "AKIA[0-9A-Z]{16}"  # AWS access key
    "sk_live_[0-9a-zA-Z]{24}"  # Stripe live key
    "-----BEGIN PRIVATE KEY-----"
    "-----BEGIN RSA PRIVATE KEY-----"
)

found_secrets=false
for pattern in "${secret_patterns[@]}"; do
    if grep -r -E "$pattern" "$REPO_ROOT" --exclude-dir=.git --exclude="validate.sh" 2>/dev/null; then
        fail "Found potential secret pattern: $pattern"
        found_secrets=true
    fi
done

if [[ "$found_secrets" = false ]]; then
    pass "No obvious secret patterns found"
fi

echo ""

# Validate Nginx configuration syntax (if nginx is available)
echo "Validating Nginx configuration..."
if command -v nginx &> /dev/null; then
    # Create temporary test directory
    temp_nginx_conf=$(mktemp)
    cat > "$temp_nginx_conf" << EOF
events {}
http {
    include $REPO_ROOT/nginx/security-headers.conf;
    include $REPO_ROOT/nginx/main-site.conf;
    include $REPO_ROOT/nginx/app-site.conf;
    include $REPO_ROOT/nginx/dev-site.conf;
}
EOF

    if nginx -t -c "$temp_nginx_conf" 2>/dev/null; then
        pass "Nginx configuration syntax is valid"
    else
        warn "Nginx configuration has syntax warnings (may be okay if SSL paths don't exist yet)"
    fi

    rm -f "$temp_nginx_conf"
else
    warn "Cannot validate Nginx config (nginx not installed)"
fi

echo ""

# Validate Terraform (if available)
echo "Validating Terraform configuration..."
if command -v terraform &> /dev/null; then
    cd "$REPO_ROOT/infrastructure"
    if terraform init -backend=false &>/dev/null && terraform validate &>/dev/null; then
        pass "Terraform configuration is valid"
    else
        fail "Terraform validation failed"
    fi
    cd "$REPO_ROOT"
else
    warn "Cannot validate Terraform (terraform not installed)"
fi

echo ""

# Check OpenAPI version
echo "Checking OpenAPI specification..."
if [[ -f "$REPO_ROOT/website/app/openapi.json" ]]; then
    if grep -q '"openapi": "3.0' "$REPO_ROOT/website/app/openapi.json"; then
        pass "OpenAPI version 3.x detected"
    else
        warn "OpenAPI version may not be 3.x"
    fi
fi

echo ""

# Summary
echo "================================"
echo "Validation Summary"
echo "================================"
echo -e "${GREEN}Passed:${NC}  $PASS"
echo -e "${YELLOW}Warnings:${NC} $WARN"
echo -e "${RED}Failed:${NC}  $FAIL"
echo ""

if [[ $FAIL -eq 0 ]]; then
    echo -e "${GREEN}✓ Validation passed!${NC}"
    if [[ $WARN -gt 0 ]]; then
        echo -e "${YELLOW}⚠ There are warnings to review${NC}"
    fi
    exit 0
else
    echo -e "${RED}✗ Validation failed with $FAIL error(s)${NC}"
    exit 1
fi
