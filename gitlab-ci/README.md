# GitLab CI Configuration

Placeholder directory for GitLab CI configuration.

## Generate Your Pipeline

Use AI to generate pipelines specific to your organization. Provide:

1. **Your org context** - naming conventions, AWS accounts, regions
2. **The patterns from** `docs/pipeline-rules.md`
3. **Your specific tools** - Terraform version, Ansible collections, etc.

## Trigger Rules

Pipelines should ONLY trigger on:

| Event               | Triggers Pipeline | Why                          |
| ------------------- | ----------------- | ---------------------------- |
| Feature branch push | **NO**            | Wasteful - no value until MR |
| MR opened/updated   | YES               | Ready for review and testing |
| Push to main        | YES               | Merged code ready for deploy |
| Manual (web UI)     | YES               | Explicit user action         |

## GitLab Limitation

Rules cannot be inherited from included templates and combined with job-specific rules. Define rules
at the job level, following the patterns in `docs/pipeline-rules.md`.

## Example Prompt for AI

```
Generate a GitLab CI pipeline for Terraform with:
- Org: <your-org>
- AWS accounts: dev (111111111111), prod (222222222222)
- Regions: ca-central-1 (primary), ca-west-1 (DR)
- State bucket: <org>-tfstate-<account>-<region>
- Role chaining: cicd-oidc-role -> cicd-admin-role

Follow the trigger and deployment rules from docs/pipeline-rules.md:
- Only trigger on MR, main branch, or manual
- Never trigger on feature branch pushes
- Dev deployable from MR, other envs main only
- Prod requires $CHANGE_REQUEST variable
```

## Files to Generate

| File             | Purpose                                                |
| ---------------- | ------------------------------------------------------ |
| `.gitlab-ci.yml` | Main pipeline (copy to repo root)                      |
| `templates/`     | Optional reusable templates (auth, terraform, ansible) |

## Workflow Rules Pattern

```yaml
workflow:
  rules:
    # Only run on MR, main, or manual trigger
    - if: '$CI_PIPELINE_SOURCE == "merge_request_event"'
    - if: '$CI_COMMIT_BRANCH == "main"'
    - if: '$CI_PIPELINE_SOURCE == "web"'
    # Block feature branch pushes
    - when: never
```
