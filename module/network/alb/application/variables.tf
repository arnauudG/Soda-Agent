variable "name" {
  description = "Name of the load balancer"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the load balancer will be created"
  type        = string
}

variable "subnets" {
  description = "List of subnet IDs for the load balancer"
  type        = list(string)
}

variable "internal" {
  description = "Whether the load balancer is internal (private) or internet-facing"
  type        = bool
  default     = false
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection"
  type        = bool
  default     = false
}

variable "enable_http2" {
  description = "Enable HTTP/2"
  type        = bool
  default     = true
}

variable "enable_cross_zone_load_balancing" {
  description = "Enable cross-zone load balancing"
  type        = bool
  default     = true
}

variable "security_groups" {
  description = "List of security group IDs for the load balancer"
  type        = list(string)
}

variable "enable_logging" {
  description = "Enable access logging"
  type        = bool
  default     = false
}

variable "log_bucket_name" {
  description = "S3 bucket name for access logs"
  type        = string
  default     = ""
}

variable "listeners" {
  description = "List of listener configurations"
  type = map(object({
    port            = number
    protocol        = string
    certificate_arn = optional(string)
    ssl_policy      = optional(string)
    default_action = object({
      type             = string
      target_group_key = optional(string)
      redirect         = optional(object({
        port        = string
        protocol    = string
        status_code = string
      }))
    })
  }))
  default = {}
}

variable "target_groups" {
  description = "List of target group configurations"
  type = map(object({
    name                 = string
    backend_protocol     = string
    backend_port         = number
    target_type          = string
    deregistration_delay = optional(number)
    health_check = object({
      enabled             = bool
      healthy_threshold   = number
      interval            = number
      matcher             = string
      path                = string
      port                = string
      protocol            = string
      timeout             = number
      unhealthy_threshold = number
    })
    targets = list(object({
      id   = string
      port = number
    }))
  }))
  default = {}
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
