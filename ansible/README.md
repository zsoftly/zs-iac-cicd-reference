# Ansible

Placeholder directory for Ansible configurations.

## Generate Your Ansible

Use AI to generate Ansible specific to your organization. Provide:

1. **Your org context** - naming conventions, inventory sources
2. **The patterns from** `docs/conventions.md`
3. **Your specific requirements** - roles, collections, playbooks

## Directory Structure

```
ansible/
├── inventories/
│   ├── 10-dev/
│   ├── 20-qat/
│   ├── 40-stg/
│   ├── 70-prod/
│   └── 90-dr/
├── group_vars/
├── roles/
│   ├── 10-common/
│   ├── 20-security/
│   └── ...
├── playbooks/
└── requirements.yml
```

## Example Prompt for AI

```
Generate Ansible configuration for AWS infrastructure with:
- Org: <your-org>
- AWS accounts: non-prod (111111111111), prod (222222222222)
- Regions: ca-central-1 (primary), ca-west-1 (DR)

Include:
1. Dynamic inventory using aws_ec2 plugin
2. Role for base OS hardening
3. Role for security baseline
4. Playbook for site deployment

Follow numbered naming from docs/conventions.md
Use assume role for cross-account access
```

## Inventory Files

Use numbered prefixes for correct sorting:

| Directory  | Environment | Account  |
| ---------- | ----------- | -------- |
| `10-dev/`  | Development | Non-Prod |
| `20-qat/`  | QA Testing  | Non-Prod |
| `40-stg/`  | Staging     | Prod     |
| `70-prod/` | Production  | Prod     |
| `90-dr/`   | DR          | Prod     |

## Role Naming

| Range | Layer       |
| ----- | ----------- |
| 00-09 | Bootstrap   |
| 10-19 | Common/Base |
| 20-29 | Security    |
| 30-39 | Monitoring  |
| 40-49 | Application |
