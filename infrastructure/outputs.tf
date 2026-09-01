output "instance_public_ip" {
  description = "Public IP address of the EC2 instance"
  value       = aws_eip.site3.public_ip
}

output "instance_public_dns" {
  description = "Public DNS name of the EC2 instance"
  value       = aws_instance.site3.public_dns
}

output "route53_nameservers" {
  description = "Route53 name servers for DNS delegation"
  value       = aws_route53_zone.site3.name_servers
}

output "dnssec_kms_key_arn" {
  description = "ARN of the customer-managed KMS key for DNSSEC"
  value       = aws_kms_key.dnssec.arn
}

output "dnssec_status" {
  description = "DNSSEC signing status"
  value       = "enabled"
}

output "main_url" {
  description = "Main site URL"
  value       = "https://${var.domain_name}"
}

output "app_url" {
  description = "App site URL"
  value       = "https://app.${var.domain_name}"
}

output "dev_url" {
  description = "Dev site URL"
  value       = "https://dev.${var.domain_name}"
}

output "legacy_dns_target" {
  description = "Legacy subdomain CNAME target"
  value       = "legacy.${var.domain_name} -> legacy-placeholder.example.invalid"
}

output "ssh_command" {
  description = "SSH command to connect to instance"
  value       = "ssh -i ~/.ssh/${var.ssh_key_name}.pem ubuntu@${aws_eip.site3.public_ip}"
}
