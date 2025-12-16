#!/bin/bash
#
# _utils.sh - Shared utility functions for CI/CD scripts
#
# Source this file to get consistent colors, logging, and utilities.
#
# Usage:
#   source "$(dirname "${BASH_SOURCE[0]}")/_utils.sh"
#
# Colors:
#   RED, GREEN, YELLOW, BLUE, CYAN, MAGENTA, BOLD, NC (no color)
#
# Logging:
#   log_info "message"     - Green [INFO]
#   log_warn "message"     - Yellow [WARN]
#   log_error "message"    - Red [ERROR]
#   log_success "message"  - Green [OK]
#   log_debug "message"    - Cyan [DEBUG] (only if DEBUG=1)
#
# Utilities:
#   require_cmd <cmd>      - Exit if command not found
#   require_var <var>      - Exit if variable not set
#   confirm "prompt"       - Y/n confirmation, returns 0/1

# ==============================================================================
# Colors (only if terminal supports colors)
# ==============================================================================

if [[ -t 1 ]] && [[ -n "${TERM:-}" ]] && [[ "${TERM}" != "dumb" ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    MAGENTA='\033[0;35m'
    BOLD='\033[1m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    CYAN=''
    MAGENTA=''
    BOLD=''
    NC=''
fi

# ==============================================================================
# Logging Functions
# ==============================================================================

log_info() {
    echo -e "${GREEN}[INFO]${NC} $*" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

log_success() {
    echo -e "${GREEN}[OK]${NC} $*" >&2
}

log_debug() {
    if [[ "${DEBUG:-0}" == "1" ]]; then
        echo -e "${CYAN}[DEBUG]${NC} $*" >&2
    fi
}

# ==============================================================================
# Utility Functions
# ==============================================================================

# Exit if command not found
require_cmd() {
    local cmd="$1"
    if ! command -v "$cmd" &>/dev/null; then
        log_error "Required command not found: $cmd"
        exit 1
    fi
}

# Exit if variable not set or empty
require_var() {
    local var_name="$1"
    local var_value="${!var_name:-}"
    if [[ -z "$var_value" ]]; then
        log_error "Required variable not set: $var_name"
        exit 1
    fi
}

# Y/n confirmation prompt
confirm() {
    local prompt="${1:-Continue?}"
    local response
    read -r -p "$prompt [Y/n] " response
    case "$response" in
        [nN][oO]|[nN])
            return 1
            ;;
        *)
            return 0
            ;;
    esac
}

# Print a separator line
separator() {
    echo "============================================================"
}

# Print header with title
header() {
    local title="$1"
    echo ""
    separator
    echo "  $title"
    separator
    echo ""
}
