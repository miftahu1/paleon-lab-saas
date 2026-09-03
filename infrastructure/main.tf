terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Additional provider for us-east-1 (required for Route 53 DNSSEC KMS key)
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

# Lookup latest Ubuntu 24.04 AMD64 AMI
data "aws_ami" "ubuntu_2404" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# Security group
resource "aws_security_group" "site3" {
  name        = "paleon-site3-sg"
  description = "Security group for Paleon Test Site 3"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "SSH from admin IP only"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.admin_ip_cidr]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "paleon-site3-sg"
  }
}

# Get default VPC
data "aws_vpc" "default" {
  default = true
}

# Elastic IP
resource "aws_eip" "site3" {
  domain = "vpc"
  tags = {
    Name = "paleon-site3-eip"
  }
}

# EC2 instance
resource "aws_instance" "site3" {
  ami                         = data.aws_ami.ubuntu_2404.id
  instance_type               = "t3.micro"
  key_name                    = var.ssh_key_name
  vpc_security_group_ids      = [aws_security_group.site3.id]
  associate_public_ip_address = false # Use Elastic IP instead

  user_data = templatefile("${path.module}/user_data.sh", {
    repo_url    = var.repo_url
    expected_ip = aws_eip.site3.public_ip
  })

  tags = {
    Name = "paleon-site3-instance"
  }

  # Depend on EIP so it can associate
  depends_on = [aws_eip.site3]
}

# Associate Elastic IP with instance
resource "aws_eip_association" "site3" {
  instance_id   = aws_instance.site3.id
  allocation_id = aws_eip.site3.id
}

# Get current AWS account ID and partition
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

# Customer-managed KMS key for Route 53 DNSSEC (MUST be in us-east-1)
resource "aws_kms_key" "dnssec" {
  provider = aws.us_east_1

  customer_master_key_spec = "ECC_NIST_P256"
  key_usage                = "SIGN_VERIFY"
  deletion_window_in_days  = 7

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "Enable IAM User Permissions"
        Effect = "Allow"
        Principal = {
          AWS = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action   = "kms:*"
        Resource = "*"
      },
      {
        Sid    = "Allow Route 53 DNSSEC Service"
        Effect = "Allow"
        Principal = {
          Service = "dnssec-route53.amazonaws.com"
        }
        Action = [
          "kms:DescribeKey",
          "kms:GetPublicKey",
          "kms:Sign"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.current.account_id
          }
        }
      },
      {
        Sid    = "Allow Route 53 DNSSEC Service to CreateGrant"
        Effect = "Allow"
        Principal = {
          Service = "dnssec-route53.amazonaws.com"
        }
        Action   = "kms:CreateGrant"
        Resource = "*"
        Condition = {
          Bool = {
            "kms:GrantIsForAWSResource" = "true"
          }
        }
      }
    ]
  })

  tags = {
    Name = "paleon-site3-dnssec-ksk"
  }
}

# KMS key alias for easier identification
resource "aws_kms_alias" "dnssec" {
  provider = aws.us_east_1

  name          = "alias/paleon-site3-dnssec"
  target_key_id = aws_kms_key.dnssec.key_id
}

# Route53 Hosted Zone
resource "aws_route53_zone" "site3" {
  name = var.domain_name

  tags = {
    Name = "paleon-site3-zone"
  }
}

# DNSSEC Key Signing Key using customer-managed KMS key
# Creating this resource enables DNSSEC for the hosted zone
resource "aws_route53_key_signing_key" "site3" {
  hosted_zone_id             = aws_route53_zone.site3.zone_id
  key_management_service_arn = aws_kms_key.dnssec.arn
  name                       = "site3-ksk"
}

# Activate DNSSEC signing for the hosted zone
resource "aws_route53_hosted_zone_dnssec" "site3" {
  hosted_zone_id = aws_route53_key_signing_key.site3.hosted_zone_id
}

# A records
resource "aws_route53_record" "main" {
  zone_id = aws_route53_zone.site3.zone_id
  name    = var.domain_name
  type    = "A"
  ttl     = 300
  records = [aws_eip.site3.public_ip]
}

resource "aws_route53_record" "app" {
  zone_id = aws_route53_zone.site3.zone_id
  name    = "app.${var.domain_name}"
  type    = "A"
  ttl     = 300
  records = [aws_eip.site3.public_ip]
}

resource "aws_route53_record" "dev" {
  zone_id = aws_route53_zone.site3.zone_id
  name    = "dev.${var.domain_name}"
  type    = "A"
  ttl     = 300
  records = [aws_eip.site3.public_ip]
}

# CNAME for legacy subdomain takeover indicator
# Using a safe, non-claimable target pattern
resource "aws_route53_record" "legacy" {
  zone_id = aws_route53_zone.site3.zone_id
  name    = "legacy.${var.domain_name}"
  type    = "CNAME"
  ttl     = 300
  records = ["legacy-placeholder.example.invalid"]
}

# CAA record for Let's Encrypt
resource "aws_route53_record" "caa" {
  zone_id = aws_route53_zone.site3.zone_id
  name    = var.domain_name
  type    = "CAA"
  ttl     = 300
  records = [
    "0 issue \"letsencrypt.org\"",
    "0 issuewild \"letsencrypt.org\"",
    "0 iodef \"mailto:admin@${var.domain_name}\""
  ]
}

# SPF record (no-mail posture)
resource "aws_route53_record" "spf" {
  zone_id = aws_route53_zone.site3.zone_id
  name    = var.domain_name
  type    = "TXT"
  ttl     = 300
  records = ["v=spf1 -all"]
}

# DMARC record
resource "aws_route53_record" "dmarc" {
  zone_id = aws_route53_zone.site3.zone_id
  name    = "_dmarc.${var.domain_name}"
  type    = "TXT"
  ttl     = 300
  records = ["v=DMARC1; p=reject;"]
}
