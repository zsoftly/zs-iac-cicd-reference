# Deploy Foundation (One-Time)

Deploy foundational CloudFormation StackSets from the management account.

## Prerequisites

- AWS CLI configured with management account credentials
- CloudFormation templates generated in `cloudformation/stacksets/`

## Deployment Order

Deploy in numbered order (dependencies):

```
00-oidc-provider-github.yaml  → 10-iam-cicd-roles.yaml  → 20-terraform-state-backend.yaml
```

## Commands

### 1. Create StackSet

```bash
aws cloudformation create-stack-set \
  --stack-set-name foundation-oidc-github \
  --template-body file://cloudformation/stacksets/00-oidc-provider-github.yaml \
  --parameters ParameterKey=GitHubOrganization,ParameterValue=<your-org> \
  --capabilities CAPABILITY_NAMED_IAM \
  --permission-model SERVICE_MANAGED \
  --auto-deployment Enabled=true,RetainStacksOnAccountRemoval=true
```

### 2. Deploy to Accounts

```bash
# Get root OU
ROOT_OU=$(aws organizations list-roots --query 'Roots[0].Id' --output text)

# Create stack instances in Canadian regions
aws cloudformation create-stack-instances \
  --stack-set-name foundation-oidc-github \
  --deployment-targets OrganizationalUnitIds=$ROOT_OU \
  --regions ca-central-1 ca-west-1
```

### 3. Check Status

```bash
aws cloudformation list-stack-set-operations \
  --stack-set-name foundation-oidc-github \
  --query 'Summaries[0].Status'
```

## Repeat for Each StackSet

| StackSet Name                | Template                          |
| ---------------------------- | --------------------------------- |
| `foundation-oidc-github`     | `00-oidc-provider-github.yaml`    |
| `foundation-cicd-roles`      | `10-iam-cicd-roles.yaml`          |
| `foundation-terraform-state` | `20-terraform-state-backend.yaml` |

## Self-Managed (No Organizations)

If not using AWS Organizations:

```bash
aws cloudformation create-stack-set \
  --stack-set-name foundation-oidc-github \
  --template-body file://cloudformation/stacksets/00-oidc-provider-github.yaml \
  --parameters ParameterKey=GitHubOrganization,ParameterValue=<your-org> \
  --capabilities CAPABILITY_NAMED_IAM \
  --permission-model SELF_MANAGED

aws cloudformation create-stack-instances \
  --stack-set-name foundation-oidc-github \
  --accounts 111111111111 222222222222 \
  --regions ca-central-1 ca-west-1
```
