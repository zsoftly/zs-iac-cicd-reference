# CloudFormation

Placeholder directory for CloudFormation templates.

## Generate Your CloudFormation

Use AI to generate CloudFormation specific to your organization. Provide:

1. **Your org context** - naming conventions, AWS accounts, regions
2. **The patterns from** `docs/conventions.md`
3. **Your specific requirements** - StackSets, nested stacks

## StackSets for Foundation

CloudFormation StackSets deploy foundation resources across accounts:

```
stacksets/
├── 00-oidc-provider-github.yaml   # OIDC for GitHub Actions
├── 10-iam-cicd-roles.yaml         # cicd-oidc-role, cicd-admin-role
└── 20-terraform-state-backend.yaml # S3 + DynamoDB for TF state
```

## Example Prompt for AI

```
Generate CloudFormation StackSets for CI/CD foundation with:
- Org: <your-org>
- AWS accounts: non-prod (111111111111), prod (222222222222)
- Regions: ca-central-1 (primary), ca-west-1 (DR)
- GitHub org: <github-org>

Include:
1. OIDC provider for GitHub Actions
2. Role chaining: cicd-oidc-role -> cicd-admin-role
3. Terraform state backend (S3 + DynamoDB)

Follow numbered file naming from docs/conventions.md
Deploy via StackSets from management account
```

## File Naming Convention

| Range | Layer              |
| ----- | ------------------ |
| 00-09 | Identity providers |
| 10-19 | IAM roles/policies |
| 20-29 | State management   |
| 30-39 | Network foundation |
| 40-49 | Security baseline  |

## Deployment Order

StackSets should be deployed in numbered order:

1. `00-*` - OIDC providers (prerequisite for role assumption)
2. `10-*` - IAM roles (depends on OIDC)
3. `20-*` - State backends (can use roles)
