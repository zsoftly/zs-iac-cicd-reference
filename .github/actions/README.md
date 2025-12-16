# Reusable Composite Actions

Placeholder directory for GitHub Actions composite actions.

## Generate Your Actions

Use AI to generate actions specific to your organization. Provide:

1. **Your org context** - AWS accounts, role ARNs, naming conventions
2. **The patterns from** `docs/authentication.md` and `docs/pipeline-rules.md`
3. **Your specific requirements** - Terraform version, state backend config

## Suggested Actions

| Action           | Purpose                                           |
| ---------------- | ------------------------------------------------- |
| `aws-auth/`      | Role chaining authentication (OIDC -> admin role) |
| `terraform-run/` | Terraform init, plan, apply with state backend    |
| `ansible-run/`   | Ansible playbook execution with vault             |

## Example Prompt for AI

```
Generate a GitHub composite action for AWS authentication with:
- Role chaining pattern: OIDC role -> admin role
- OIDC role ARN from secrets.OIDC_ROLE_ARN
- Admin role ARN from secrets.ADMIN_ROLE_ARN
- Support for ca-central-1 and ca-west-1 regions

Follow the authentication pattern from docs/authentication.md
```

## Why Composite Actions?

- **DRY** - Reuse across multiple workflows
- **Encapsulation** - Hide complexity of role chaining
- **Versioning** - Pin to specific versions
- **Testing** - Test actions independently
