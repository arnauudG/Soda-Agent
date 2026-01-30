# Security Group Modules Overview

This directory contains security group modules used by the stacks (ops, RDS, add-ons).

## Module Structure

```
security-group/
├── ops/      # Generic security group (used for multiple purposes)
├── rds/      # RDS-specific security group
└── README.md # This file
```

## Module Descriptions

### `ops/` - Generic Security Group

A flexible security group module that can be used for various purposes:
- Ops EC2 instances
- Collibra DQ instances
- ALB security groups
- Any component requiring custom ingress/egress rules

**Key Features:**
- Configurable ingress rules (CIDR or security group source)
- Configurable egress rules
- Supports both predefined rules and custom rules

### `rds/` - RDS Security Group

A specialized security group for RDS PostgreSQL instances:
- Pre-configured for PostgreSQL port (5432)
- Supports security group references (preferred for internal access)
- Supports CIDR blocks (for VPN or specific IPs)

## Security Group Relationships

```
┌─────────────────────────────────────────────────────────────────────┐
│                           INTERNET                                   │
└─────────────────────────────────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────┐
│                        ALB Security Group                            │
│  Ingress: 80/443 from 0.0.0.0/0                                     │
│  Egress: 9000 to Collibra DQ SG                                     │
└─────────────────────────────────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    Collibra DQ Security Group                        │
│  Ingress: 9000 from ALB SG, 8080-8081/9101 from VPC CIDR           │
│  Egress: 5432 to VPC CIDR, 443/80 to 0.0.0.0/0 (updates)           │
└─────────────────────────────────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────┐
│                       RDS Security Group                             │
│  Ingress: 5432 from Collibra DQ SG                                  │
│  Egress: None                                                        │
└─────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────┐
│                       Ops Security Group                             │
│  Ingress: None (SSM only)                                           │
│  Egress: 443 to VPC CIDR (endpoints), 53 DNS, 123 NTP               │
└─────────────────────────────────────────────────────────────────────┘
                                 │
                                 ▼
┌─────────────────────────────────────────────────────────────────────┐
│                    EKS Cluster Security Group                        │
│  Ingress: 443 from Ops SG                                           │
│  Egress: (managed by EKS module)                                    │
└─────────────────────────────────────────────────────────────────────┘
```

## Best Practices

### 1. Use Security Group References Over CIDRs
```hcl
# Good - Security group reference
ingress_with_source_security_group_id = [
  {
    source_security_group_id = dependency.sg_alb.outputs.security_group_id
    ...
  }
]

# Avoid - CIDR block for internal traffic
ingress_with_cidr_blocks = [
  {
    cidr_blocks = "10.10.0.0/16"  # Less specific
    ...
  }
]
```

### 2. Follow Least Privilege
- Only open required ports
- Restrict source to minimum necessary scope
- Use VPC CIDR instead of `0.0.0.0/0` for internal services

### 3. Document All Rules
```hcl
{
  description = "Allow HTTPS from ALB for web traffic"  # Clear purpose
  ...
}
```

### 4. No Ingress for SSM-Only Access
```hcl
# Instance accessed via SSM Session Manager
ingress_rules            = []
ingress_with_cidr_blocks = []
```

## Environment Differences

| Aspect | Dev | Prod |
|--------|-----|------|
| Collibra DQ CIDR | VPC CIDR (secure) | VPC CIDR |
| ALB Access | HTTP allowed | HTTPS required |
| Deletion Protection | Disabled | Enabled |

## Troubleshooting

### Connection Refused
1. Check security group allows the port
2. Verify source (CIDR or SG) is correct
3. Check NACL rules (VPC level)

### Cannot Reach Internet
1. Verify egress rules allow 443/80
2. Check NAT Gateway is working
3. Verify route tables

### SSM Session Manager Not Working
1. Verify VPC endpoints exist (ssm, ssmmessages, ec2messages)
2. Check instance IAM role has SSM policy
3. Verify egress to VPC CIDR on port 443

## Related Documentation

- [AWS Security Group Best Practices](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_SecurityGroups.html)
- [VPC Endpoints](../../../network/vpc-endpoints/README.md)
- [EKS Security](../../../compute/eks/cluster/README.md)
