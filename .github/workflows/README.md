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

## Caching Strategy

Use `actions/cache@v4` to dramatically reduce pipeline time:

### Terraform Cache

```yaml
- name: Cache Terraform providers
  uses: actions/cache@v4
  with:
    path: ~/.terraform.d/plugin-cache
    key: terraform-${{ runner.os }}-${{ hashFiles('**/.terraform.lock.hcl') }}
    restore-keys: terraform-${{ runner.os }}-

- name: Terraform Init
  run: terraform init
  env:
    TF_PLUGIN_CACHE_DIR: ~/.terraform.d/plugin-cache
```

### Ansible Cache

```yaml
- name: Cache Ansible collections
  uses: actions/cache@v4
  with:
    path: ~/.ansible/collections
    key: ansible-${{ hashFiles('**/requirements.yml') }}
    restore-keys: ansible-

- name: Install collections
  run: ansible-galaxy collection install -r requirements.yml
  env:
    ANSIBLE_COLLECTIONS_PATH: ~/.ansible/collections
```

### S3 Backend Cache (Cross-Runner)

For persistent caching across all runners:

```yaml
env:
  ARTIFACT_BUCKET: ${{ vars.ARTIFACT_BUCKET }}

steps:
  - name: Download cache from S3
    run: |
      CACHE_KEY="terraform-$(sha256sum .terraform.lock.hcl | cut -d' ' -f1)"
      aws s3 cp "s3://${ARTIFACT_BUCKET}/${CACHE_KEY}.tar.gz" /tmp/cache.tar.gz || true
      if [[ -f /tmp/cache.tar.gz ]]; then
        mkdir -p ~/.terraform.d/plugin-cache
        tar -xzf /tmp/cache.tar.gz -C ~/.terraform.d/
      fi

  - name: Upload cache to S3
    if: always()
    run: |
      CACHE_KEY="terraform-$(sha256sum .terraform.lock.hcl | cut -d' ' -f1)"
      tar -czf /tmp/cache.tar.gz -C ~/.terraform.d/ plugin-cache/ 2>/dev/null || true
      aws s3 cp /tmp/cache.tar.gz "s3://${ARTIFACT_BUCKET}/${CACHE_KEY}.tar.gz" || true
```

See [docs/caching.md](../docs/caching.md) for complete details.

## Files to Generate

| File                 | Purpose                         |
| -------------------- | ------------------------------- |
| `terraform.yml`      | Terraform validate, plan, apply |
| `ansible.yml`        | Ansible lint, check, deploy     |
| `cloudformation.yml` | CFN lint, deploy                |
