# Remote state backend for Site 3
#
# State is stored in a dedicated, private, encrypted S3 bucket. This follows
# the Site 5 backend pattern: S3 with server-side encryption and no DynamoDB
# lock table. The bucket must exist before `terraform init` — create it with
# scripts/bootstrap-backend.sh, which is idempotent.
#
# Region matches Site 3's aws_region (us-east-1). The state key is namespaced to
# Site 3 so a shared bucket naming scheme never collides with other sites.
terraform {
  backend "s3" {
    bucket  = "paleon-site3-terraform-state"
    key     = "site3/terraform.tfstate"
    region  = "us-east-1"
    encrypt = true
  }
}