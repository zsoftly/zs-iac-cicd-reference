#!/usr/bin/env bash
# =============================================================================
# 00-deploy-foundation.sh
#
# Deploy foundational CloudFormation StackSets from the management account.
# These are ONE-TIME resources that never need Terraform state management.
#
# Resources deployed:
#   1. GitHub OIDC Provider
#   2. CI/CD IAM Roles (Terraform + Ansible)
#   3. Terraform State Backend (S3 + DynamoDB)
#
# Target Regions: ca-central-1 (Montreal), ca-west-1 (Calgary)
#
# Usage:
#   ./00-deploy-foundation.sh --org zsoftly --github-org zsoftly
#   ./00-deploy-foundation.sh --org acme --github-org acme-corp --accounts 111111111111,222222222222
#
# Prerequisites:
#   - AWS CLI v2 configured with management account credentials
#   - StackSets service-linked role or self-managed role
#   - Organizations enabled (for service-managed StackSets)
# =============================================================================

set -euo pipefail

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly STACKSET_DIR="${SCRIPT_DIR}/../stacksets"

# Canada regions only
readonly REGIONS=("ca-central-1" "ca-west-1")

# StackSet names
readonly OIDC_STACKSET="foundation-oidc-github"
readonly ROLES_STACKSET="foundation-cicd-roles"
readonly STATE_STACKSET="foundation-terraform-state"

# Defaults
ORG_PREFIX=""
GITHUB_ORG=""
GITHUB_REPOS="*"
TARGET_ACCOUNTS=""
TARGET_OUS=""
DEPLOYMENT_TYPE="SERVICE_MANAGED"  # or SELF_MANAGED
DRY_RUN=false
MANAGEMENT_ACCOUNT_ID=""

# -----------------------------------------------------------------------------
# Usage
# -----------------------------------------------------------------------------
usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Deploy foundational CloudFormation StackSets to target accounts.

Required:
  --org PREFIX              Organization prefix for naming (e.g., zsoftly)
  --github-org ORG          GitHub organization name

Optional:
  --github-repos PATTERN    Repository pattern (default: *)
  --accounts IDS            Comma-separated account IDs (for self-managed)
  --ous IDS                 Comma-separated OU IDs (for service-managed)
  --self-managed            Use self-managed StackSets (default: service-managed)
  --dry-run                 Show what would be deployed without executing
  -h, --help                Show this help message

Examples:
  # Deploy to all accounts in organization
  $(basename "$0") --org zsoftly --github-org zsoftly

  # Deploy to specific accounts
  $(basename "$0") --org zsoftly --github-org zsoftly --accounts 111111111111,222222222222

  # Deploy to specific OUs
  $(basename "$0") --org zsoftly --github-org zsoftly --ous ou-xxxx-yyyyyyyy

  # Dry run
  $(basename "$0") --org zsoftly --github-org zsoftly --dry-run
EOF
}

# -----------------------------------------------------------------------------
# Logging
# -----------------------------------------------------------------------------
log_info() { echo "[INFO] $*"; }
log_warn() { echo "[WARN] $*" >&2; }
log_error() { echo "[ERROR] $*" >&2; }
log_success() { echo "[OK] $*"; }

# -----------------------------------------------------------------------------
# Parse Arguments
# -----------------------------------------------------------------------------
parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --org)
                ORG_PREFIX="$2"
                shift 2
                ;;
            --github-org)
                GITHUB_ORG="$2"
                shift 2
                ;;
            --github-repos)
                GITHUB_REPOS="$2"
                shift 2
                ;;
            --accounts)
                TARGET_ACCOUNTS="$2"
                DEPLOYMENT_TYPE="SELF_MANAGED"
                shift 2
                ;;
            --ous)
                TARGET_OUS="$2"
                shift 2
                ;;
            --self-managed)
                DEPLOYMENT_TYPE="SELF_MANAGED"
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                usage
                exit 1
                ;;
        esac
    done

    # Validate required args
    if [[ -z "$ORG_PREFIX" ]]; then
        log_error "Missing required: --org"
        usage
        exit 1
    fi

    if [[ -z "$GITHUB_ORG" ]]; then
        log_error "Missing required: --github-org"
        usage
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# Pre-flight Checks
# -----------------------------------------------------------------------------
preflight_checks() {
    log_info "Running pre-flight checks..."

    # Check AWS CLI
    if ! command -v aws &>/dev/null; then
        log_error "AWS CLI not found. Please install it first."
        exit 1
    fi

    # Check credentials
    if ! aws sts get-caller-identity &>/dev/null; then
        log_error "AWS credentials not configured or expired."
        exit 1
    fi

    # Get management account ID
    MANAGEMENT_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    log_info "Management Account: ${MANAGEMENT_ACCOUNT_ID}"

    # Check if running from management account (for Organizations)
    if [[ "$DEPLOYMENT_TYPE" == "SERVICE_MANAGED" ]]; then
        if ! aws organizations describe-organization &>/dev/null; then
            log_warn "Organizations not accessible. Switching to SELF_MANAGED mode."
            DEPLOYMENT_TYPE="SELF_MANAGED"
        fi
    fi

    # Verify StackSet templates exist
    for template in "00-oidc-provider-github.yaml" "10-iam-cicd-roles.yaml" "20-terraform-state-backend.yaml"; do
        if [[ ! -f "${STACKSET_DIR}/${template}" ]]; then
            log_error "Template not found: ${STACKSET_DIR}/${template}"
            exit 1
        fi
    done

    log_success "Pre-flight checks passed"
}

# -----------------------------------------------------------------------------
# Get Deployment Targets
# -----------------------------------------------------------------------------
get_deployment_targets() {
    if [[ "$DEPLOYMENT_TYPE" == "SERVICE_MANAGED" ]]; then
        if [[ -n "$TARGET_OUS" ]]; then
            echo "--deployment-targets OrganizationalUnitIds=${TARGET_OUS}"
        else
            # Deploy to root OU (all accounts)
            local root_ou
            root_ou=$(aws organizations list-roots --query 'Roots[0].Id' --output text)
            echo "--deployment-targets OrganizationalUnitIds=${root_ou}"
        fi
    else
        if [[ -n "$TARGET_ACCOUNTS" ]]; then
            echo "--deployment-targets Accounts=${TARGET_ACCOUNTS}"
        else
            log_error "For SELF_MANAGED, you must specify --accounts"
            exit 1
        fi
    fi
}

# -----------------------------------------------------------------------------
# Create or Update StackSet
# -----------------------------------------------------------------------------
deploy_stackset() {
    local name="$1"
    local template="$2"
    local description="$3"
    shift 3
    local parameters=("$@")

    log_info "Deploying StackSet: ${name}"

    local template_body
    template_body=$(cat "${STACKSET_DIR}/${template}")

    # Build parameters JSON
    local params_json="["
    local first=true
    for param in "${parameters[@]}"; do
        if [[ "$first" == true ]]; then
            first=false
        else
            params_json+=","
        fi
        local key="${param%%=*}"
        local value="${param#*=}"
        params_json+="{\"ParameterKey\":\"${key}\",\"ParameterValue\":\"${value}\"}"
    done
    params_json+="]"

    if [[ "$DRY_RUN" == true ]]; then
        log_info "[DRY-RUN] Would create/update StackSet: ${name}"
        log_info "[DRY-RUN] Template: ${template}"
        log_info "[DRY-RUN] Parameters: ${params_json}"
        log_info "[DRY-RUN] Regions: ${REGIONS[*]}"
        return 0
    fi

    # Check if StackSet exists
    if aws cloudformation describe-stack-set --stack-set-name "${name}" &>/dev/null; then
        log_info "Updating existing StackSet: ${name}"
        aws cloudformation update-stack-set \
            --stack-set-name "${name}" \
            --template-body "${template_body}" \
            --parameters "${params_json}" \
            --capabilities CAPABILITY_NAMED_IAM \
            --operation-preferences "RegionConcurrencyType=PARALLEL,MaxConcurrentPercentage=100" \
            || true  # Ignore "No updates" error
    else
        log_info "Creating new StackSet: ${name}"

        local permission_model
        local auto_deployment=""
        if [[ "$DEPLOYMENT_TYPE" == "SERVICE_MANAGED" ]]; then
            permission_model="SERVICE_MANAGED"
            auto_deployment="--auto-deployment Enabled=true,RetainStacksOnAccountRemoval=true"
        else
            permission_model="SELF_MANAGED"
        fi

        # shellcheck disable=SC2086
        aws cloudformation create-stack-set \
            --stack-set-name "${name}" \
            --description "${description}" \
            --template-body "${template_body}" \
            --parameters "${params_json}" \
            --capabilities CAPABILITY_NAMED_IAM \
            --permission-model "${permission_model}" \
            ${auto_deployment}
    fi

    # Create stack instances
    log_info "Creating stack instances in regions: ${REGIONS[*]}"

    local targets
    targets=$(get_deployment_targets)
    local regions_str
    regions_str=$(IFS=,; echo "${REGIONS[*]}")

    # shellcheck disable=SC2086
    aws cloudformation create-stack-instances \
        --stack-set-name "${name}" \
        --regions ${REGIONS[*]} \
        ${targets} \
        --operation-preferences "RegionConcurrencyType=PARALLEL,MaxConcurrentPercentage=100,FailureTolerancePercentage=0" \
        || true  # Ignore if instances already exist

    log_success "StackSet deployed: ${name}"
}

# -----------------------------------------------------------------------------
# Wait for StackSet Operation
# -----------------------------------------------------------------------------
wait_for_stackset() {
    local name="$1"
    local timeout=600  # 10 minutes

    log_info "Waiting for StackSet operation to complete: ${name}"

    local start_time
    start_time=$(date +%s)

    while true; do
        local status
        status=$(aws cloudformation list-stack-set-operations \
            --stack-set-name "${name}" \
            --query 'Summaries[0].Status' \
            --output text 2>/dev/null || echo "UNKNOWN")

        case "$status" in
            SUCCEEDED)
                log_success "StackSet operation completed: ${name}"
                return 0
                ;;
            FAILED|STOPPED)
                log_error "StackSet operation failed: ${name}"
                return 1
                ;;
            RUNNING|QUEUED)
                local elapsed=$(($(date +%s) - start_time))
                if [[ $elapsed -gt $timeout ]]; then
                    log_error "Timeout waiting for StackSet: ${name}"
                    return 1
                fi
                log_info "Still running... (${elapsed}s elapsed)"
                sleep 30
                ;;
            *)
                log_info "No active operations for: ${name}"
                return 0
                ;;
        esac
    done
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    echo "============================================================"
    echo "Foundation StackSet Deployment"
    echo "============================================================"
    echo "Target Regions: ${REGIONS[*]}"
    echo "============================================================"
    echo

    parse_args "$@"
    preflight_checks

    # Deploy OIDC Provider
    deploy_stackset \
        "${OIDC_STACKSET}" \
        "00-oidc-provider-github.yaml" \
        "GitHub Actions OIDC Provider - Foundation" \
        "GitHubOrganization=${GITHUB_ORG}" \
        "AllowedRepositories=${GITHUB_REPOS}"

    if [[ "$DRY_RUN" != true ]]; then
        wait_for_stackset "${OIDC_STACKSET}"
    fi

    # Deploy IAM Roles
    deploy_stackset \
        "${ROLES_STACKSET}" \
        "10-iam-cicd-roles.yaml" \
        "CI/CD IAM Roles - Foundation" \
        "GitHubOrganization=${GITHUB_ORG}" \
        "AllowedRepositories=${GITHUB_REPOS}" \
        "AllowedBranches=main" \
        "OIDCProviderStackName=${OIDC_STACKSET}" \
        "ToolingAccountId=${MANAGEMENT_ACCOUNT_ID}"

    if [[ "$DRY_RUN" != true ]]; then
        wait_for_stackset "${ROLES_STACKSET}"
    fi

    # Deploy State Backend (per region)
    deploy_stackset \
        "${STATE_STACKSET}" \
        "20-terraform-state-backend.yaml" \
        "Terraform State Backend - Foundation" \
        "OrganizationPrefix=${ORG_PREFIX}" \
        "EnableCrossRegionReplication=true" \
        "ReplicationDestinationRegion=ca-west-1" \
        "RetentionDays=90" \
        "EnableKMSEncryption=false" \
        "LockTableTTLHours=24"

    if [[ "$DRY_RUN" != true ]]; then
        wait_for_stackset "${STATE_STACKSET}"
    fi

    echo
    echo "============================================================"
    echo "[OK] Foundation deployment complete!"
    echo "============================================================"
    echo
    echo "Next steps:"
    echo "1. Verify stacks in target accounts"
    echo "2. Note the S3 bucket and DynamoDB table names"
    echo "3. Configure Terraform backend in your projects"
    echo
    echo "Terraform backend configuration:"
    echo "  bucket         = \"${ORG_PREFIX}-tfstate-<ACCOUNT_ID>-ca-central-1\""
    echo "  key            = \"<GITHUB_ORG>/<REPO>/<PATH>/terraform.tfstate\""
    echo "  dynamodb_table = \"${ORG_PREFIX}-tfstate-lock\""
    echo
    echo "Example key: ${ORG_PREFIX}/aws-infra/terraform/compute/cac1/jenkins/terraform.tfstate"
    echo
}

main "$@"
