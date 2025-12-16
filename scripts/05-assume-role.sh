#!/bin/bash
#
# assume-role.sh - Cross-account role assumption helper
#
# This script assumes an IAM role in another AWS account and exports
# the temporary credentials as environment variables.
#
# Usage:
#   # Source to export credentials
#   source ./assume-role.sh arn:aws:iam::123456789012:role/terraform-deployer
#
#   # Or use in subshell
#   eval $(./assume-role.sh arn:aws:iam::123456789012:role/terraform-deployer --export)
#
# Options:
#   --session-name NAME    Custom session name (default: cicd-session-TIMESTAMP)
#   --duration SECONDS     Session duration (default: 3600, max: 43200)
#   --external-id ID       External ID for role assumption
#   --export               Output export commands instead of sourcing
#   --profile PROFILE      AWS profile to use for assuming

set -euo pipefail

# Source shared utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/_utils.sh"

# ==============================================================================
# Configuration
# ==============================================================================

ROLE_ARN=""
SESSION_NAME="cicd-session-$(date +%s)"
DURATION=3600
EXTERNAL_ID=""
EXPORT_MODE=false
AWS_PROFILE=""

# ==============================================================================
# Parse Arguments
# ==============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        --session-name)
            SESSION_NAME="$2"
            shift 2
            ;;
        --duration)
            DURATION="$2"
            shift 2
            ;;
        --external-id)
            EXTERNAL_ID="$2"
            shift 2
            ;;
        --export)
            EXPORT_MODE=true
            shift
            ;;
        --profile)
            AWS_PROFILE="$2"
            shift 2
            ;;
        --help|-h)
            cat <<EOF
Usage: $0 ROLE_ARN [OPTIONS]

Assume an IAM role and export temporary credentials.

Arguments:
  ROLE_ARN                IAM role ARN to assume

Options:
  --session-name NAME     Custom session name (default: cicd-session-TIMESTAMP)
  --duration SECONDS      Session duration in seconds (default: 3600)
  --external-id ID        External ID for role assumption
  --export                Output export commands for eval
  --profile PROFILE       AWS profile to use
  --help, -h              Show this help message

Examples:
  # Source credentials
  source $0 arn:aws:iam::123456789012:role/terraform-deployer

  # Export mode (for scripts)
  eval \$($0 arn:aws:iam::123456789012:role/terraform-deployer --export)

  # With external ID
  source $0 arn:aws:iam::123456789012:role/terraform-deployer --external-id my-id
EOF
            exit 0
            ;;
        -*)
            log_error "Unknown option: $1"
            exit 1
            ;;
        *)
            if [ -z "$ROLE_ARN" ]; then
                ROLE_ARN="$1"
            else
                log_error "Unexpected argument: $1"
                exit 1
            fi
            shift
            ;;
    esac
done

# ==============================================================================
# Validation
# ==============================================================================

if [ -z "$ROLE_ARN" ]; then
    log_error "ROLE_ARN is required"
    echo "Usage: $0 ROLE_ARN [OPTIONS]" >&2
    echo "Run '$0 --help' for more information" >&2
    exit 1
fi

if ! [[ "$ROLE_ARN" =~ ^arn:aws:iam::[0-9]{12}:role/.+ ]]; then
    log_error "Invalid role ARN format: $ROLE_ARN"
    exit 1
fi

if [ "$DURATION" -lt 900 ] || [ "$DURATION" -gt 43200 ]; then
    log_error "Duration must be between 900 and 43200 seconds"
    exit 1
fi

# ==============================================================================
# Assume Role
# ==============================================================================

log_info "Assuming role: $ROLE_ARN"
log_info "Session name: $SESSION_NAME"
log_info "Duration: ${DURATION}s"

# Build assume-role command
ASSUME_CMD="aws sts assume-role"
ASSUME_CMD+=" --role-arn $ROLE_ARN"
ASSUME_CMD+=" --role-session-name $SESSION_NAME"
ASSUME_CMD+=" --duration-seconds $DURATION"

if [ -n "$EXTERNAL_ID" ]; then
    ASSUME_CMD+=" --external-id $EXTERNAL_ID"
    log_info "External ID: [provided]"
fi

if [ -n "$AWS_PROFILE" ]; then
    ASSUME_CMD+=" --profile $AWS_PROFILE"
    log_info "Using profile: $AWS_PROFILE"
fi

# Execute and parse response
CREDS_JSON=$($ASSUME_CMD --output json)

if [ $? -ne 0 ]; then
    log_error "Failed to assume role"
    exit 1
fi

# Extract credentials
ACCESS_KEY=$(echo "$CREDS_JSON" | jq -r '.Credentials.AccessKeyId')
SECRET_KEY=$(echo "$CREDS_JSON" | jq -r '.Credentials.SecretAccessKey')
SESSION_TOKEN=$(echo "$CREDS_JSON" | jq -r '.Credentials.SessionToken')
EXPIRATION=$(echo "$CREDS_JSON" | jq -r '.Credentials.Expiration')

if [ -z "$ACCESS_KEY" ] || [ "$ACCESS_KEY" == "null" ]; then
    log_error "Failed to parse credentials"
    exit 1
fi

log_info "Credentials obtained, expires: $EXPIRATION"

# ==============================================================================
# Output
# ==============================================================================

if [ "$EXPORT_MODE" = true ]; then
    # Output export commands for eval
    echo "export AWS_ACCESS_KEY_ID='$ACCESS_KEY'"
    echo "export AWS_SECRET_ACCESS_KEY='$SECRET_KEY'"
    echo "export AWS_SESSION_TOKEN='$SESSION_TOKEN'"
    echo "export AWS_ROLE_ARN='$ROLE_ARN'"
    echo "export AWS_SESSION_EXPIRATION='$EXPIRATION'"
else
    # Export directly (when sourced)
    export AWS_ACCESS_KEY_ID="$ACCESS_KEY"
    export AWS_SECRET_ACCESS_KEY="$SECRET_KEY"
    export AWS_SESSION_TOKEN="$SESSION_TOKEN"
    export AWS_ROLE_ARN="$ROLE_ARN"
    export AWS_SESSION_EXPIRATION="$EXPIRATION"

    log_info "Credentials exported to environment"

    # Verify
    log_info "Verifying credentials..."
    aws sts get-caller-identity
fi
