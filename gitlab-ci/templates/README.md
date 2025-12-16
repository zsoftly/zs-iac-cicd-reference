# GitLab CI Templates

Placeholder directory for reusable GitLab CI templates.

## Generate Your Templates

Use AI to generate templates specific to your organization. Provide:

1. **Your org context** - AWS accounts, role ARNs, naming conventions
2. **The patterns from** `docs/authentication.md` and `docs/pipeline-rules.md`
3. **Your specific requirements** - Terraform version, state backend config

## GitLab Limitation

**Important:** Rules cannot be inherited from included templates and combined with job-specific
rules.

This means:

- Templates can define base configuration (image, scripts, variables)
- Rules must be defined at the job level in the main `.gitlab-ci.yml`
- Follow the patterns in `docs/pipeline-rules.md` for rule definitions

## Suggested Templates

| Template             | Purpose                      |
| -------------------- | ---------------------------- |
| `aws-auth.yml`       | Role chaining authentication |
| `terraform-base.yml` | Terraform init, plan, apply  |
| `ansible-base.yml`   | Ansible lint, check, deploy  |

## Example Prompt for AI

```
Generate a GitLab CI template for Terraform with:
- Role chaining pattern: OIDC role -> admin role
- Variables: OIDC_ROLE_ARN, ADMIN_ROLE_ARN, TF_STATE_BUCKET
- State key pattern: $CI_PROJECT_PATH/<env>/terraform.tfstate
- Image: hashicorp/terraform:1.6.0

Do NOT include rules in the template - rules will be defined at job level
following the patterns in docs/pipeline-rules.md
```

## Usage

```yaml
# .gitlab-ci.yml
include:
  - local: "gitlab-ci/templates/terraform-base.yml"

my-plan-job:
  extends: .terraform-plan-template
  variables:
    ENVIRONMENT: "10-dev"
  rules: # Rules at job level, not inherited
    - if: '$CI_PIPELINE_SOURCE == "merge_request_event"'
    - if: '$CI_COMMIT_BRANCH == "main"'
```
