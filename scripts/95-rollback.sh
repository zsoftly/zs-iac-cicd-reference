#!/bin/bash
#
# rollback.sh - Emergency Terraform State Rollback
#
# This script rolls back Terraform state to a previous version.
# Use with caution - this can cause infrastructure drift.
#
# Prerequisites:
#   - AWS CLI configured
#   - S3 bucket versioning enabled
#   - Proper IAM permissions
#
# Usage:
#   ./rollback.sh --bucket my-state-bucket --key prod/terraform.tfstate
#   ./rollback.sh --bucket my-state-bucket --key prod/terraform.tfstate --version-id abc123
#   ./rollback.sh --bucket my-state-bucket --key prod/terraform.tfstate --list

set -euo pipefail

# Source shared utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_utils.sh"

# ==============================================================================
# Configuration
# ==============================================================================

BUCKET=""
STATE_KEY=""
VERSION_ID=""
LIST_ONLY=false
DRY_RUN=false
LOCK_TABLE="terraform-locks"
AWS_REGION="${AWS_REGION:-us-east-1}"

# ==============================================================================
# Parse Arguments
# ==============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        --bucket|-b)
            BUCKET="$2"
            shift 2
            ;;
        --key|-k)
            STATE_KEY="$2"
            shift 2
            ;;
        --version-id|-v)
            VERSION_ID="$2"
            shift 2
            ;;
        --list|-l)
            LIST_ONLY=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --lock-table)
            LOCK_TABLE="$2"
            shift 2
            ;;
        --region)
            AWS_REGION="$2"
            shift 2
            ;;
        --help|-h)
            cat <<EOF
Usage: $0 --bucket BUCKET --key STATE_KEY [OPTIONS]

Emergency Terraform state rollback utility.

Required:
  --bucket, -b BUCKET      S3 bucket containing state
  --key, -k STATE_KEY      State file key (e.g., prod/terraform.tfstate)

Options:
  --version-id, -v ID      Specific version to restore (default: previous)
  --list, -l               List available versions and exit
  --dry-run                Show what would be done without making changes
  --lock-table TABLE       DynamoDB lock table (default: terraform-locks)
  --region REGION          AWS region (default: us-east-1)
  --help, -h               Show this help message

Examples:
  # List available versions
  $0 --bucket my-state --key prod/terraform.tfstate --list

  # Rollback to previous version
  $0 --bucket my-state --key prod/terraform.tfstate

  # Rollback to specific version
  $0 --bucket my-state --key prod/terraform.tfstate --version-id abc123

  # Dry run
  $0 --bucket my-state --key prod/terraform.tfstate --dry-run
EOF
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# ==============================================================================
# Validation
# ==============================================================================

if [ -z "$BUCKET" ] || [ -z "$STATE_KEY" ]; then
    log_error "Both --bucket and --key are required"
    exit 1
fi

# ==============================================================================
# Functions
# ==============================================================================

list_versions() {
    log_info "Listing versions for s3://${BUCKET}/${STATE_KEY}"
    echo ""

    aws s3api list-object-versions \
        --bucket "$BUCKET" \
        --prefix "$STATE_KEY" \
        --query 'Versions[*].{VersionId:VersionId,LastModified:LastModified,Size:Size,IsLatest:IsLatest}' \
        --output table

    echo ""
    log_info "Use --version-id to specify which version to restore"
}

get_previous_version() {
    log_info "Finding previous version..."

    # Get all versions, skip the latest (current)
    VERSIONS=$(aws s3api list-object-versions \
        --bucket "$BUCKET" \
        --prefix "$STATE_KEY" \
        --query 'Versions[?IsLatest==`false`].VersionId' \
        --output text)

    if [ -z "$VERSIONS" ]; then
        log_error "No previous versions found"
        exit 1
    fi

    # Get the most recent non-current version
    VERSION_ID=$(echo "$VERSIONS" | awk '{print $1}')
    log_info "Found previous version: $VERSION_ID"
}

acquire_lock() {
    log_info "Acquiring state lock..."

    LOCK_ID="s3://${BUCKET}/${STATE_KEY}"

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would acquire lock: $LOCK_ID"
        return
    fi

    # Try to acquire lock
    aws dynamodb put-item \
        --table-name "$LOCK_TABLE" \
        --item "{
            \"LockID\": {\"S\": \"${LOCK_ID}\"},
            \"Info\": {\"S\": \"Rollback in progress by $(whoami) at $(date -u +%Y-%m-%dT%H:%M:%SZ)\"}
        }" \
        --condition-expression "attribute_not_exists(LockID)" \
        --region "$AWS_REGION" 2>/dev/null || {
            log_warn "State is locked. Checking lock info..."
            aws dynamodb get-item \
                --table-name "$LOCK_TABLE" \
                --key "{\"LockID\": {\"S\": \"${LOCK_ID}\"}}" \
                --region "$AWS_REGION"
            log_error "Cannot proceed while state is locked"
            exit 1
        }

    log_info "Lock acquired"
}

release_lock() {
    log_info "Releasing state lock..."

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would release lock"
        return
    fi

    LOCK_ID="s3://${BUCKET}/${STATE_KEY}"

    aws dynamodb delete-item \
        --table-name "$LOCK_TABLE" \
        --key "{\"LockID\": {\"S\": \"${LOCK_ID}\"}}" \
        --region "$AWS_REGION" || log_warn "Failed to release lock"

    log_info "Lock released"
}

backup_current() {
    log_info "Backing up current state..."

    BACKUP_KEY="${STATE_KEY}.backup.$(date +%Y%m%d%H%M%S)"

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would backup to s3://${BUCKET}/${BACKUP_KEY}"
        return
    fi

    aws s3 cp \
        "s3://${BUCKET}/${STATE_KEY}" \
        "s3://${BUCKET}/${BACKUP_KEY}"

    log_info "Backed up to s3://${BUCKET}/${BACKUP_KEY}"
}

restore_version() {
    log_info "Restoring version: $VERSION_ID"

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would restore version $VERSION_ID"
        return
    fi

    # Download the old version
    aws s3api get-object \
        --bucket "$BUCKET" \
        --key "$STATE_KEY" \
        --version-id "$VERSION_ID" \
        /tmp/terraform.tfstate.restore

    # Upload as new current version
    aws s3 cp \
        /tmp/terraform.tfstate.restore \
        "s3://${BUCKET}/${STATE_KEY}"

    rm -f /tmp/terraform.tfstate.restore

    log_info "State restored successfully"
}

confirm_rollback() {
    echo ""
    log_warn "=========================================="
    log_warn "  TERRAFORM STATE ROLLBACK"
    log_warn "=========================================="
    echo ""
    echo "  Bucket:     ${BUCKET}"
    echo "  State Key:  ${STATE_KEY}"
    echo "  Version ID: ${VERSION_ID}"
    echo ""
    log_warn "This will replace the current state with an older version."
    log_warn "This may cause infrastructure drift!"
    echo ""

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] No changes will be made"
        return
    fi

    read -p "Type 'ROLLBACK' to confirm: " CONFIRM
    if [ "$CONFIRM" != "ROLLBACK" ]; then
        log_info "Rollback cancelled"
        exit 0
    fi
}

# ==============================================================================
# Main
# ==============================================================================

main() {
    if [ "$LIST_ONLY" = true ]; then
        list_versions
        exit 0
    fi

    if [ -z "$VERSION_ID" ]; then
        get_previous_version
    fi

    confirm_rollback

    # Set trap to release lock on exit
    trap release_lock EXIT

    acquire_lock
    backup_current
    restore_version

    echo ""
    log_info "=========================================="
    log_info "  Rollback Complete"
    log_info "=========================================="
    echo ""
    log_info "Next steps:"
    echo "  1. Run 'terraform plan' to see any drift"
    echo "  2. Run 'terraform apply' to reconcile state"
    echo "  3. Verify infrastructure is correct"
    echo ""
}

main "$@"
