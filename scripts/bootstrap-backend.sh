#!/usr/bin/env bash
# Idempotent bootstrap for the Site 3 Terraform S3 state backend.
#
# S3 backends must exist BEFORE `terraform init`, so this bucket is created out
# of band by this script rather than by Terraform itself. Running it repeatedly
# is safe: every step checks current state before acting.
#
# The bucket is private, blocks public access, uses default server-side
# encryption, and has versioning enabled. No DynamoDB lock table or bucket
# policy is created. The bucket therefore relies solely on account/IAM
# permissions and has no public access path.
#
# Credentials are taken from the standard AWS SDK chain (environment variables,
# shared config, or instance profile). Nothing secret is written to the repo.
#
# Usage:
#   ./scripts/bootstrap-backend.sh
#   BUCKET=my-bucket REGION=us-east-1 ./scripts/bootstrap-backend.sh

set -euo pipefail

# These defaults MUST match infrastructure/backend.tf.
BUCKET="${BUCKET:-paleon-site3-terraform-state}"
REGION="${REGION:-us-east-1}"

echo "==> Bootstrapping Terraform state backend"
echo "    bucket: $BUCKET"
echo "    region: $REGION"

if ! command -v aws >/dev/null 2>&1; then
  echo "ERROR: aws CLI not found on PATH" >&2
  exit 1
fi

if ! aws sts get-caller-identity >/dev/null; then
  echo "ERROR: unable to authenticate to AWS with the configured credentials" >&2
  exit 1
fi

# 1. Create the bucket if it does not already exist.
if aws s3api head-bucket --bucket "$BUCKET" >/dev/null 2>&1; then
  echo "-> Bucket already exists, skipping creation"
else
  echo "-> Creating bucket"
  # us-east-1 must NOT be passed a LocationConstraint; every other region must.
  if [[ "$REGION" == "us-east-1" ]]; then
    aws s3api create-bucket --bucket "$BUCKET" --region "$REGION"
  else
    aws s3api create-bucket \
      --bucket "$BUCKET" \
      --region "$REGION" \
      --create-bucket-configuration "LocationConstraint=$REGION"
  fi
fi

# Fail safely if an accessible bucket with this name is in another region.
BUCKET_REGION="$(aws s3api get-bucket-location --bucket "$BUCKET" --query 'LocationConstraint' --output text)"
if [[ "$BUCKET_REGION" == "None" || "$BUCKET_REGION" == "null" ]]; then
  BUCKET_REGION="us-east-1"
fi
if [[ "$BUCKET_REGION" != "$REGION" ]]; then
  echo "ERROR: bucket $BUCKET is in $BUCKET_REGION, expected $REGION" >&2
  exit 1
fi

# 2. Block all public access (idempotent — always re-asserted).
echo "-> Enforcing public access block"
aws s3api put-public-access-block \
  --bucket "$BUCKET" \
  --public-access-block-configuration \
  "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"

# 3. Enforce bucket ownership (disables ACLs — bucket owner owns all objects).
echo "-> Enforcing bucket owner ownership"
aws s3api put-bucket-ownership-controls \
  --bucket "$BUCKET" \
  --ownership-controls "Rules=[{ObjectOwnership=BucketOwnerEnforced}]"

# 4. Enable default server-side encryption (SSE-S3 / AES256).
echo "-> Enabling default encryption (AES256)"
aws s3api put-bucket-encryption \
  --bucket "$BUCKET" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

# 5. Enable versioning so prior state revisions are recoverable.
echo "-> Enabling versioning"
aws s3api put-bucket-versioning \
  --bucket "$BUCKET" \
  --versioning-configuration "Status=Enabled"

echo "==> Backend bucket ready: s3://$BUCKET (region $REGION)"
echo "    Next: cd infrastructure && terraform init -migrate-state"