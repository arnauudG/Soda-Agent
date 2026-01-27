output "load_balancer_id" {
  description = "The ID of the load balancer"
  value       = module.alb.load_balancer_id
}

output "load_balancer_arn" {
  description = "The ARN of the load balancer"
  value       = module.alb.load_balancer_arn
}

output "load_balancer_dns_name" {
  description = "The DNS name of the load balancer"
  value       = module.alb.load_balancer_dns_name
}

output "load_balancer_zone_id" {
  description = "The canonical hosted zone ID of the load balancer"
  value       = module.alb.load_balancer_zone_id
}

output "target_group_arns" {
  description = "ARNs of the target groups"
  value       = module.alb.target_group_arns
}

output "target_group_arn_suffixes" {
  description = "ARN suffixes of the target groups"
  value       = module.alb.target_group_arn_suffixes
}

output "listener_arns" {
  description = "ARNs of the listeners"
  value       = module.alb.listener_arns
}
