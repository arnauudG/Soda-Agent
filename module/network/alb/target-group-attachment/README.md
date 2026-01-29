# Target Group Attachment Module

Registers EC2 instances with an ALB target group.

## Description

This module creates a target group attachment to register an EC2 instance (or other target) with an Application Load Balancer target group.

## Usage

```hcl
module "tg_attachment" {
  source = "../../../module/network/alb/target-group-attachment"

  target_group_arn = dependency.alb.outputs.target_groups["dq-web"].arn
  target_id        = dependency.collibra_dq.outputs.instance_id
  port             = 9000
}
```

## Required Inputs

| Name | Description | Type |
|------|-------------|------|
| `target_group_arn` | ARN of the target group | `string` |
| `target_id` | ID of the target (EC2 instance ID) | `string` |

## Optional Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| `port` | Port on which targets receive traffic | `number` | `9000` |

## Outputs

| Name | Description |
|------|-------------|
| `id` | Target group attachment ID |

## Dependencies

- `network/alb/application` - ALB with target groups
- EC2 instance to register

## Related Modules

- `network/alb/application` - Creates the ALB and target groups
