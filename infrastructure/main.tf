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

# Lookup latest Ubuntu 24.04 AMD64 AMI
data "aws_ami" "ubuntu_2404" {
  most_recent = true
  owners      = ["099720109477"]  # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-noble-24.04-amd64-server-*"]
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
  ami                    = data.aws_ami.ubuntu_2404.id
  instance_type          = "t3.micro"
  key_name               = var.ssh_key_name
  vpc_security_group_ids = [aws_security_group.site3.id]
  associate_public_ip_address = false  # Use Elastic IP instead

  user_data = filebase64("${path.module}/user_data.sh")

  tags = {
    Name = "paleon-site3-instance"
  }

  # Depend on EIP so it can associate
  depends_on = [aws_eip.site3]
}

# Associate Elastic IP with instance
resource "aws_eip_association" "site3" {
  instance_id = aws_instance.site3.id
  allocation_id = aws_eip.site3.id
}

# Route53 Hosted Zone
resource "aws_route53_zone" "site3" {
  name = var.domain_name

  tags = {
    Name = "paleon-site3-zone"
  }
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

# SPF record (no-mail posture)
resource "aws_route53_record" "spf" {
  zone_id = aws_route53_zone.site3.zone_id
  name    = var.domain_name
  type    = "TXT"
  ttl     = 300
  records = ["\"v=spf1 -all\""]
}

# DMARC record
resource "aws_route53_record" "dmarc" {
  zone_id = aws_route53_zone.site3.zone_id
  name    = "_dmarc.${var.domain_name}"
  type    = "TXT"
  ttl     = 300
  records = ["\"v=DMARC1; p=reject;\""]
}