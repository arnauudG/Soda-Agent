output "instance_id" {
  description = "EC2 instance ID"
  value       = module.ec2.instance_id
}

output "instance_arn" {
  description = "EC2 instance ARN"
  value       = module.ec2.instance_arn
}

output "instance_public_ip" {
  description = "Public IP address of the instance"
  value       = module.ec2.instance_public_ip
}

output "instance_private_ip" {
  description = "Private IP address of the instance"
  value       = module.ec2.instance_private_ip
}

output "instance_dns_name" {
  description = "DNS name of the instance"
  value       = module.ec2.instance_dns_name
}

output "owl_base" {
  description = "Base directory for Collibra DQ installation"
  value       = var.owl_base
}

output "dq_web_url" {
  description = "URL to access DQ Web (port 9000)"
  value       = "http://${module.ec2.instance_public_ip}:9000"
}
