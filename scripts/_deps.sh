#!/bin/bash
# _deps.sh — Dependency checker and validator
# Source: source "$SCRIPT_DIR/_deps.sh"
# Usage: check_deps [quiet]  → returns exit code, prints warnings
#        list_deps            → show all required + optional deps

source "${BASH_SOURCE%/*}/_ui.sh" 2>/dev/null

# Dependency registry: name | type (required/optional) | description | fix_hint
declare -a DEPS_REGISTRY=(
    # Core system
    "bash|required|Shell interpreter|Usually pre-installed"
    "git|required|Version control|brew install git"
    "curl|required|HTTP client|brew install curl"

    # Optional but recommended
    "fzf|optional|Fuzzy finder (for menu/search)|brew install fzf"
    "jq|optional|JSON processor (for API parsing)|brew install jq"
    "bat|optional|Better cat (for code display)|brew install bat"

    # Optional: AI & tooling
    "docker|optional|Container runtime (for docker commands)|brew install docker"
    "python3|optional|Python (for server/PDAC)|brew install python@3.11"
    "node|optional|Node.js (for web UI/PDAC)|brew install node"

    # Optional: Terminal & remote
    "ttyd|optional|Terminal sharing (for remote access)|brew install ttyd"
    "tmux|optional|Terminal multiplexer (for sessions)|brew install tmux"
    "ngrok|optional|Tunneling (for remote access)|brew install ngrok"

    # Optional: Git & code
    "gh|optional|GitHub CLI (for gh commands)|brew install gh"

    # macOS-specific
    "brew|optional|Homebrew package manager (for installs)|https://brew.sh"
)

# ─── Check if dependency is installed ───
check_dep() {
    local dep="$1"
    command -v "$dep" &>/dev/null
}

# ─── Get version string ───
get_version() {
    local dep="$1"
    local ver
    ver=$("$dep" --version 2>/dev/null || "$dep" -v 2>/dev/null || echo "unknown" | head -1)
    echo "${ver:0:50}"  # Truncate to 50 chars
}

# ─── List all dependencies ───
list_deps() {
    clear
    title_box "Dependencies" "📦"
    echo ""
    echo -e "  ${BOLD}Required:${NC}"
    for entry in "${DEPS_REGISTRY[@]}"; do
        IFS='|' read -r name type desc hint <<< "$entry"
        [[ "$type" != "required" ]] && continue
        if check_dep "$name"; then
            printf "    ${GREEN}✓${NC}  %-12s  %s\n" "$name" "$desc"
        else
            printf "    ${RED}✗${NC}  %-12s  %s\n" "$name" "$desc"
        fi
    done

    echo ""
    echo -e "  ${BOLD}Optional:${NC}"
    local opt_total=0 opt_installed=0
    for entry in "${DEPS_REGISTRY[@]}"; do
        IFS='|' read -r name type desc hint <<< "$entry"
        [[ "$type" != "optional" ]] && continue
        ((opt_total++))
        if check_dep "$name"; then
            printf "    ${GREEN}✓${NC}  %-12s  %s\n" "$name" "$desc"
            ((opt_installed++))
        else
            printf "    ${DIM}○${NC}  %-12s  %s\n" "$name" "$desc"
        fi
    done

    echo ""
    echo -e "  ${BOLD}Installed: ${opt_installed}/${opt_total}${NC}"
    echo ""
    pause
}

# ─── Check all deps, return exit code ───
check_deps() {
    local quiet="${1:-}"
    local missing_required=0
    local missing_optional=()

    for entry in "${DEPS_REGISTRY[@]}"; do
        IFS='|' read -r name type desc hint <<< "$entry"

        if ! check_dep "$name"; then
            if [[ "$type" == "required" ]]; then
                ((missing_required++))
                [[ -z "$quiet" ]] && echo -e "  ${RED}✗${NC} $name (required) — $hint" >&2
            else
                missing_optional+=("$name")
            fi
        fi
    done

    if (( missing_required > 0 )); then
        [[ -z "$quiet" ]] && echo -e "  ${RED}${missing_required} required dep(s) missing${NC}" >&2
        return 1
    fi

    if (( ${#missing_optional[@]} > 0 )); then
        [[ -z "$quiet" ]] && echo -e "  ${YELLOW}${#missing_optional[@]} optional dep(s) missing — features limited${NC}" >&2
        return 2
    fi

    [[ -z "$quiet" ]] && echo -e "  ${GREEN}All dependencies installed${NC}" >&2
    return 0
}

# ─── Validator for critical commands ───
validate_for_command() {
    local cmd="$1"
    local deps_needed=()

    # Define deps per command
    case "$cmd" in
        docker|docker-health)
            deps_needed=("docker")
            ;;
        ask|review|aicommit)
            deps_needed=()  # Claude API key checked separately
            ;;
        project)
            deps_needed=("fzf")
            ;;
        pdac)
            deps_needed=("python3" "node")
            ;;
        server)
            deps_needed=("python3" "docker")
            ;;
        remote-access)
            deps_needed=("ttyd" "ngrok")
            ;;
    esac

    for dep in "${deps_needed[@]}"; do
        if ! check_dep "$dep"; then
            return 1
        fi
    done
    return 0
}

# ─── Quick check on startup (silent) ───
startup_check() {
    local missing_req=0
    for entry in "${DEPS_REGISTRY[@]}"; do
        IFS='|' read -r name type desc hint <<< "$entry"
        [[ "$type" != "required" ]] && continue
        if ! check_dep "$name"; then
            ((missing_req++))
        fi
    done

    # Return silently; main() decides whether to warn
    return "$missing_req"
}

export -f check_dep get_version list_deps check_deps validate_for_command startup_check
export DEPS_REGISTRY
