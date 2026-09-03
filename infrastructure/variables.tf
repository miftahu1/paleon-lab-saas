variable "aws_region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

variable "domain_name" {
  description = "Domain name for the test site"
  type        = string
  default     = "paleon-lab-saas.dev"
}

variable "ssh_key_name" {
  description = "Name of the SSH key pair for EC2 access"
  type        = string
}

variable "admin_ip_cidr" {
  description = "CIDR block for admin SSH access (your IP address)"
  type        = string
}

variable "repo_url" {
  description = "Public Git repository URL for site code (cloned by user_data)"
  type        = string
  default     = "https://github.com/miftahu1/paleon-lab-saas.git"
}