# Outputs for Collibra DQ ALB

output "alb_dns_name" {
  description = "DNS name of the ALB - use this to access Collibra DQ Web Interface via HTTPS"
  value       = dependency.alb.outputs.load_balancer_dns_name
}

output "alb_zone_id" {
  description = "Zone ID of the ALB (for Route53 alias records)"
  value       = dependency.alb.outputs.load_balancer_zone_id
}

output "alb_arn" {
  description = "ARN of the ALB"
  value       = dependency.alb.outputs.load_balancer_arn
}

output "dq_web_url" {
  description = "Full URL to access Collibra DQ Web Interface"
  value       = "https://${dependency.alb.outputs.load_balancer_dns_name}"
}
