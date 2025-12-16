# GitHub Actions Workflows

Placeholder directory for GitHub Actions workflows.

## Generate Your Workflows

Use AI to generate workflows specific to your organization. Provide:

1. **Your org context** - naming conventions, AWS accounts, regions
2. **The patterns from** `docs/pipeline-rules.md`
3. **Your specific tools** - Terraform version, Ansible collections, etc.

## Trigger Rules

Workflows should ONLY trigger on:

| Event                      | Triggers Pipeline | Why                          |
| -------------------------- | ----------------- | ---------------------------- |
| Feature branch push        | **NO**            | Wasteful - no value until PR |
| PR opened/updated          | YES               | Ready for review and testing |
| Push to main               | YES               | Merged code ready for deploy |
| Manual (workflow_dispatch) | YES               | Explicit user action         |

## Example Prompt for AI

```
Generate a GitHub Actions workflow for Terraform with:
- Org: <your-org>
- AWS accounts: dev (111111111111), prod (222222222222)
- Regions: ca-central-1 (primary), ca-west-1 (DR)
- State bucket: <org>-tfstate-<account>-<region>
- Role chaining: cicd-oidc-role -> cicd-admin-role

Follow the trigger and deployment rules from docs/pipeline-rules.md:
- Only trigger on PR, main branch, or workflow_dispatch
- Never trigger on feature branch pushes
- Dev deployable from PR, other envs main only
- Prod requires change_request input
```

## Files to Generate

| File                 | Purpose                         |
| -------------------- | ------------------------------- |
| `terraform.yml`      | Terraform validate, plan, apply |
| `ansible.yml`        | Ansible lint, check, deploy     |
| `cloudformation.yml` | CFN lint, deploy                |
