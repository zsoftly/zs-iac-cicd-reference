# Naming Conventions

Numbered prefixes for correct sorting across CI/CD systems.

## AWS Account Model

| Account  | Environments            | Region                       |
| -------- | ----------------------- | ---------------------------- |
| Non-Prod | 10-dev, 20-qat, sandbox | ca-central-1                 |
| Prod     | 40-stg, 70-prod, 100-dr | ca-central-1, ca-west-1 (DR) |

## Why Numbered Prefixes?

Alphabetical sorting breaks logical order:

```
dev, prod, qat, stg  →  Wrong (prod before qat)
10-dev, 20-qat, 40-stg, 70-prod  →  Correct
```

## Environments

| Range | Environment | Account  | Purpose                       |
| ----- | ----------- | -------- | ----------------------------- |
| 00-19 | dev         | Non-Prod | Development, sandbox          |
| 20-39 | qat         | Non-Prod | Testing                       |
| 40-59 | stg         | Prod     | Staging                       |
| 70-89 | prod        | Prod     | Production                    |
| 100+  | dr          | Prod     | Disaster recovery (ca-west-1) |

**Gaps allow future growth** (e.g., 75-prod-canary)

## Files/Modules

| Range | Layer                           |
| ----- | ------------------------------- |
| 00-09 | Foundation (providers, backend) |
| 10-19 | Identity (IAM, OIDC)            |
| 20-29 | Network (VPC, subnets)          |
| 30-39 | Compute (EC2, EKS)              |
| 40-49 | Storage (S3, EBS)               |
| 50-59 | Database (RDS, DynamoDB)        |
| 60-69 | Application (Lambda, ECS)       |
| 70-79 | Monitoring (CloudWatch)         |
| 80-89 | Security (WAF, GuardDuty)       |
| 90-99 | Outputs                         |

## Quick Reference

```
ACCOUNTS         ENVIRONMENTS     FILES
────────         ────────────     ─────
Non-Prod         00-19  dev       00-09  Foundation
                 20-39  qat       10-19  Identity
                                  20-29  Network
Prod             40-59  stg       30-39  Compute
                 70-89  prod      ...
                 100+   dr
```

## Rules

- Always 2+ digits (01, not 1)
- Leave gaps for growth
- Consistent across all tools
