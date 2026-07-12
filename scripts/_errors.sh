#!/bin/bash
# _errors.sh — Contextual error messages with recovery hints
# Source: source "$SCRIPT_DIR/_errors.sh"
# Usage: error_msg CODE "message" [hint]

source "${BASH_SOURCE%/*}/_ui.sh" 2>/dev/null

# Error codes with solutions
declare -A ERROR_HINTS=(
    # API/Auth errors
    ["API_KEY_MISSING"]="Set your Claude API key: kmac vault set anthropic sk-ant-..."
    ["API_TIMEOUT"]="Claude API is slow or unreachable. Try again or check https://status.anthropic.com"
    ["AUTH_FAILED"]="API key is invalid or expired. Get new one: https://console.anthropic.com"

    # Dependencies
    ["DOCKER_NOT_RUNNING"]="Start Docker: open -a Docker (waits ~30s)"
    ["FZF_NOT_FOUND"]="Install fzf: brew install fzf (for faster help search)"
    ["PYTHON_NOT_FOUND"]="Install Python: brew install python@3.11"
    ["GIT_NOT_FOUND"]="Install Git: brew install git"

    # File/Path errors
    ["FILE_NOT_FOUND"]="File doesn't exist. Check path: ls path/to/file"
    ["PERMISSION_DENIED"]="Don't have permission. Try: sudo or check chmod"
    ["PATH_INVALID"]="Path contains invalid characters or is malformed"

    # Command errors
    ["COMMAND_FAILED"]="Command exited with error. Check logs: tail ~/.config/kmac/logs/*.log"
    ["INVALID_ARGS"]="Arguments are wrong. Run: kmac COMMAND --help"
    ["NOT_A_GIT_REPO"]="Not in a git repository. Run: git init (if starting new)"

    # Network errors
    ["NETWORK_OFFLINE"]="Internet connection lost. Check: kmac network"
    ["TUNNEL_DOWN"]="Remote tunnel is down. Restart: kmac server restart"

    # System errors
    ["DISK_FULL"]="Low disk space. Clean up: kmac houseclean run"
    ["MEMORY_LOW"]="System memory is low. Try again later or restart"
)

# ─── Show contextual error with recovery hint ───
error_msg() {
    local code="$1"
    local message="$2"
    local hint="${3:-${ERROR_HINTS[$code]:-}}"

    echo ""
    echo -e "  ${RED}${BOLD}✗ Error${NC}"
    echo -e "  ${DIM}Code: ${code}${NC}"
    echo ""
    echo -e "  ${message}"
    echo ""

    if [[ -n "$hint" ]]; then
        echo -e "  ${YELLOW}${BOLD}How to fix:${NC}"
        echo -e "  ${hint}"
    fi

    echo ""
    echo -e "  ${DIM}For help: kmac doctor${NC}"
    echo -e "  ${DIM}Search: kmac ask \"${message}\"${NC}"
    echo ""
}

# ─── API key specific error ───
error_api_key() {
    error_msg "API_KEY_MISSING" \
        "Claude API key not configured. This is required for AI features." \
        "Get free key at: https://console.anthropic.com/dashboard/keys
        Store it: kmac vault set anthropic sk-ant-your-key-here"
}

# ─── Dependency-specific error ───
error_dependency() {
    local dep="$1"
    local hint="${ERROR_HINTS["${dep}_NOT_FOUND"]:-}"

    error_msg "DEPENDENCY_MISSING" \
        "Required tool '$dep' not found." \
        "$hint"
}

# ─── Command-failed wrapper ───
error_cmd_failed() {
    local cmd="$1"
    local exit_code="$2"
    local hint="${3:-}"

    error_msg "COMMAND_FAILED" \
        "Command '$cmd' failed with exit code $exit_code." \
        "${hint:-Run 'kmac doctor' to check system health}"
}

# ─── Network error wrapper ───
error_network() {
    local endpoint="${1:-Claude API}"
    error_msg "NETWORK_ERROR" \
        "Cannot reach $endpoint. Check your internet connection." \
        "Test connectivity: kmac network"
}

# ─── Git error wrapper ───
error_git() {
    local message="${1:-Git error}"
    error_msg "GIT_ERROR" \
        "$message" \
        "Check you're in a git repo: git status"
}

export -f error_msg error_api_key error_dependency error_cmd_failed error_network error_git
export ERROR_HINTS
