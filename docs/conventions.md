# Naming Conventions

Numbered prefixes for correct sorting across CI/CD systems.

## OU Hierarchy

| OU Code     | Full Name         | Purpose                          |
| ----------- | ----------------- | -------------------------------- |
| **PLT**     | Platform          | CI/CD runners and shared tooling |
| **WKL**     | Workloads         | Application environments         |
| **WKL-NPD** | Workloads-NonProd | Development and testing          |
| **WKL-PRD** | Workloads-Prod    | Production and DR                |

```
Root
├── PLT OU
│   └── PLT-Runner Account
│
└── WKL OU
    ├── WKL-NPD OU
    │   ├── SBX, DEV, QAT
    │
    └── WKL-PRD OU
        └── STG, PRD, DR
```

## Environments

| Prefix | Environment | OU      | Account | Region       |
| ------ | ----------- | ------- | ------- | ------------ |
| 00     | runner      | PLT     | PLT     | ca-central-1 |
| 05     | sbx         | WKL-NPD | SBX     | ca-central-1 |
| 10     | dev         | WKL-NPD | DEV     | ca-central-1 |
| 20     | qat         | WKL-NPD | QAT     | ca-central-1 |
| 40     | stg         | WKL-PRD | STG     | ca-central-1 |
| 70     | prod        | WKL-PRD | PRD     | ca-central-1 |
| 90     | dr          | WKL-PRD | DR      | ca-west-1    |

## Why Numbered Prefixes?

Alphabetical sorting breaks logical order:

```
dev, prod, qat, sbx, stg  →  Wrong (prod before qat)
05-sbx, 10-dev, 20-qat, 40-stg, 70-prod, 90-dr  →  Correct
```

**Gaps allow future growth** (e.g., 75-prod-canary, 95-dr-warm)

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
OUs              ENVIRONMENTS        FILES
───              ────────────        ─────
PLT              00  runner          00-09  Foundation
                                     10-19  Identity
WKL-NPD          05  sbx             20-29  Network
                 10  dev             30-39  Compute
                 20  qat             ...

WKL-PRD          40  stg
                 70  prod
                 90  dr
```

## Rules

- Always 2+ digits (01, not 1)
- Leave gaps for growth
- Consistent across all tools
- Use OU codes (PLT, WKL, WKL-NPD, WKL-PRD) in documentation
