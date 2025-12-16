#!/bin/bash
#
# setup-oidc-github.sh - Configure AWS OIDC Provider for GitHub Actions
#
# This script creates the necessary AWS resources for GitHub Actions
# to authenticate using OIDC (no stored credentials).
#
# Prerequisites:
#   - AWS CLI configured with admin permissions
#   - jq installed
#
# Usage:
#   export GITHUB_ORG="my-org"
#   export GITHUB_REPO="my-repo"  # or "*" for all repos
#   export AWS_REGION="us-east-1"
#   ./setup-oidc-github.sh
#
# Environment Variables:
#   GITHUB_ORG      - GitHub organization name (required)
#   GITHUB_REPO     - GitHub repository name, or "*" for all (default: *)
#   AWS_REGION      - AWS region (default: us-east-1)
#   IAM_ROLE_NAME   - Name for the IAM role (default: github-actions-terraform)
#   STATE_BUCKET    - S3 bucket for Terraform state (optional)
#   LOCK_TABLE      - DynamoDB table for locking (optional)

set -euo pipefail

# Source shared utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_utils.sh"

# ==============================================================================
# Configuration
# ==============================================================================

GITHUB_ORG="${GITHUB_ORG:?Error: GITHUB_ORG is required}"
GITHUB_REPO="${GITHUB_REPO:-*}"
AWS_REGION="${AWS_REGION:-us-east-1}"
IAM_ROLE_NAME="${IAM_ROLE_NAME:-github-actions-terraform}"
STATE_BUCKET="${STATE_BUCKET:-}"
LOCK_TABLE="${LOCK_TABLE:-}"

OIDC_URL="token.actions.githubusercontent.com"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# ==============================================================================
# Functions
# ==============================================================================

get_thumbprint() {
    log_info "Fetching GitHub OIDC provider thumbprint..."

    THUMBPRINT=$(openssl s_client \
        -servername "${OIDC_URL}" \
        -connect "${OIDC_URL}:443" \
        -showcerts 2>/dev/null | \
        openssl x509 -fingerprint -sha1 -noout | \
        sed 's/://g' | \
        cut -d'=' -f2)

    if [ -z "$THUMBPRINT" ]; then
        log_error "Failed to get thumbprint"
        exit 1
    fi

    log_info "Thumbprint: ${THUMBPRINT:0:8}..."
}

create_oidc_provider() {
    log_info "Creating OIDC provider in AWS..."

    # Check if provider exists
    EXISTING=$(aws iam list-open-id-connect-providers \
        --query "OpenIDConnectProviderList[?ends_with(Arn, '/${OIDC_URL}')].Arn" \
        --output text 2>/dev/null || true)

    if [ -n "$EXISTING" ]; then
        log_warn "OIDC provider already exists: $EXISTING"
        OIDC_PROVIDER_ARN="$EXISTING"
        return
    fi

    OIDC_PROVIDER_ARN=$(aws iam create-open-id-connect-provider \
        --url "https://${OIDC_URL}" \
        --client-id-list "sts.amazonaws.com" \
        --thumbprint-list "$THUMBPRINT" \
        --query 'OpenIDConnectProviderArn' \
        --output text)

    log_info "Created OIDC provider: $OIDC_PROVIDER_ARN"
}

create_trust_policy() {
    log_info "Creating trust policy..."

    if [ "$GITHUB_REPO" == "*" ]; then
        SUBJECT="repo:${GITHUB_ORG}/*:*"
    else
        # Allow both main branch and pull_request events for PR validation
        SUBJECT="repo:${GITHUB_ORG}/${GITHUB_REPO}:*"
    fi

    TRUST_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "${OIDC_PROVIDER_ARN}"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "${OIDC_URL}:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "${OIDC_URL}:sub": "${SUBJECT}"
        }
      }
    }
  ]
}
EOF
)
}

create_iam_role() {
    log_info "Creating IAM role: $IAM_ROLE_NAME..."

    # Check if role exists
    if aws iam get-role --role-name "$IAM_ROLE_NAME" &>/dev/null; then
        log_warn "Role already exists, updating trust policy..."
        aws iam update-assume-role-policy \
            --role-name "$IAM_ROLE_NAME" \
            --policy-document "$TRUST_POLICY"
    else
        aws iam create-role \
            --role-name "$IAM_ROLE_NAME" \
            --assume-role-policy-document "$TRUST_POLICY" \
            --description "IAM role for GitHub Actions OIDC authentication" \
            --max-session-duration 3600
        log_info "Created role: $IAM_ROLE_NAME"
    fi

    ROLE_ARN="arn:aws:iam::${AWS_ACCOUNT_ID}:role/${IAM_ROLE_NAME}"
}

attach_state_policy() {
    if [ -z "$STATE_BUCKET" ]; then
        log_info "Skipping state management policy (STATE_BUCKET not set)"
        return
    fi

    log_info "Attaching Terraform state management policy..."

    STATE_POLICY=$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "S3StateAccess",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::${STATE_BUCKET}",
        "arn:aws:s3:::${STATE_BUCKET}/*"
      ]
    },
    {
      "Sid": "DynamoDBLocking",
      "Effect": "Allow",
      "Action": [
        "dynamodb:PutItem",
        "dynamodb:GetItem",
        "dynamodb:DeleteItem",
        "dynamodb:DescribeTable"
      ],
      "Resource": "arn:aws:dynamodb:${AWS_REGION}:${AWS_ACCOUNT_ID}:table/${LOCK_TABLE:-terraform-locks}"
    }
  ]
}
EOF
)

    aws iam put-role-policy \
        --role-name "$IAM_ROLE_NAME" \
        --policy-name "terraform-state-access" \
        --policy-document "$STATE_POLICY"

    log_info "Attached state management policy"
}

print_summary() {
    echo ""
    echo "============================================================"
    echo "  GitHub Actions OIDC Setup Complete"
    echo "============================================================"
    echo ""
    echo "  OIDC Provider ARN: ${OIDC_PROVIDER_ARN}"
    echo "  IAM Role ARN:      ${ROLE_ARN}"
    echo "  GitHub Org:        ${GITHUB_ORG}"
    echo "  GitHub Repo:       ${GITHUB_REPO}"
    echo ""
    echo "============================================================"
    echo "  Add to your GitHub Actions workflow:"
    echo "============================================================"
    echo ""
    cat <<EOF
permissions:
  id-token: write
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: aws-actions/configure-aws-credentials@v4
        with:
          aws-region: ${AWS_REGION}
          role-to-assume: ${ROLE_ARN}
          role-session-name: github-actions-\${{ github.run_id }}

      - run: aws sts get-caller-identity
EOF
    echo ""
    echo "============================================================"
}

# ==============================================================================
# Main
# ==============================================================================

main() {
    log_info "Setting up GitHub Actions OIDC for ${GITHUB_ORG}/${GITHUB_REPO}"
    log_info "AWS Account: ${AWS_ACCOUNT_ID}"
    log_info "AWS Region: ${AWS_REGION}"
    echo ""

    get_thumbprint
    create_oidc_provider
    create_trust_policy
    create_iam_role
    attach_state_policy
    print_summary
}

main "$@"
