# Terraform

Placeholder directory for Terraform configurations.

## Generate Your Terraform

Use AI to generate Terraform specific to your organization. Provide:

1. **Your org context** - naming conventions, AWS accounts, regions
2. **The patterns from** `docs/conventions.md`
3. **Your specific requirements** - modules, providers, backends

## File Naming Convention

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

## Example Prompt for AI

```
Generate Terraform for AWS CI/CD infrastructure with:
- Org: <your-org>
- AWS accounts: non-prod (111111111111), prod (222222222222)
- Regions: ca-central-1 (primary), ca-west-1 (DR)
- State bucket: <org>-tfstate-<account>-<region>

Include:
1. State backend (S3 + DynamoDB)
2. OIDC provider for GitHub Actions
3. Role chaining: cicd-oidc-role -> cicd-admin-role

Follow numbered file naming from docs/conventions.md
```

## Environment Files

Use numbered prefixes for correct sorting:

| File             | Environment | Account  |
| ---------------- | ----------- | -------- |
| `10-dev.tfvars`  | Development | Non-Prod |
| `20-qat.tfvars`  | QA Testing  | Non-Prod |
| `40-stg.tfvars`  | Staging     | Prod     |
| `70-prod.tfvars` | Production  | Prod     |
| `90-dr.tfvars`   | DR          | Prod     |
