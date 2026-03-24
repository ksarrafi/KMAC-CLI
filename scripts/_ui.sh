#!/bin/bash
# _ui.sh — shared UI helpers for toolkit scripts
# Source this in any script: source "$SCRIPT_DIR/_ui.sh"

# ─── Colors ──────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
export BLUE='\033[0;34m'
export MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
export WHITE='\033[1;37m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# 256-color palette for gradients (exported for toolkit scripts that only read these)
export C_BLUE='\033[38;5;33m'
export C_CYAN='\033[38;5;39m'
export C_TEAL='\033[38;5;45m'
export C_GREEN='\033[38;5;49m'
export C_MINT='\033[38;5;84m'
export C_ORANGE='\033[38;5;208m'

# ─── title_box — styled header for sub-features ─────────────────────────
# Usage: title_box "Title" [emoji]
title_box() {
    local title="$1" icon="${2:-}"
    local display="${icon:+$icon }$title"
    local len=${#display}
    [[ -n "$icon" ]] && (( len = len + 1 ))
    local pad=$(( 40 - len ))
    (( pad < 2 )) && pad=2
    local line="" i
    for (( i = 0; i < len + pad + 2; i++ )); do line+="─"; done
    echo ""
    echo -e "  ${CYAN}╭─${line}─╮${NC}"
    printf "  ${CYAN}│${NC}  ${BOLD}%s${NC}%*s${CYAN}│${NC}\n" "$display" $(( pad + 1 )) ""
    echo -e "  ${CYAN}╰─${line}─╯${NC}"
    echo ""
}

# ─── section — lightweight section divider ───────────────────────────────
# Usage: section "Section Name"
section() {
    echo ""
    echo -e "  ${BOLD}$1${NC}"
    echo -e "  ${DIM}$(printf '─%.0s' {1..48})${NC}"
}

# ─── info / success / warn / fail — consistent one-liners ───────────────
ui_info()    { echo -e "  ${CYAN}▸${NC} $*"; }
ui_success() { echo -e "  ${GREEN}✓${NC} $*"; }
ui_warn()    { echo -e "  ${YELLOW}!${NC} $*"; }
ui_fail()    { echo -e "  ${RED}✗${NC} $*"; }
ui_dim()     { echo -e "  ${DIM}$*${NC}"; }

# ─── pause — standard "press any key" prompt ─────────────────────────────
pause() {
    echo ""
    echo -e -n "  ${DIM}Press any key to continue...${NC}"
    read -r -n1
    echo ""
}

# ─── confirm — y/N prompt, returns 0 on yes ──────────────────────────────
# Usage: confirm "Delete everything?" && do_it
confirm() {
    local msg="${1:-Are you sure?}"
    echo ""
    echo -e "  ${YELLOW}${msg}${NC}"
    read -r -n1 -p "  (y/N) > " yn; echo ""
    [[ "$yn" == [yY] ]]
}

# ─── spinner — run a command with an animated spinner ────────────────────
# Usage: spinner "Loading data" long_running_command arg1 arg2
# The label is shown while the command runs; ✓/✗ on completion.
spinner() {
    local label="$1"; shift
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local frame_count=${#frames[@]}
    local i=0
    local pid

    "$@" &>/dev/null &
    pid=$!

    tput civis 2>/dev/null
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r  ${CYAN}${frames[$i]}${NC} %s " "$label"
        i=$(( (i + 1) % frame_count ))
        sleep 0.08
    done

    wait "$pid"
    local rc=$?
    tput cnorm 2>/dev/null

    if (( rc == 0 )); then
        printf "\r  ${GREEN}✓${NC} %s\033[K\n" "$label"
    else
        printf "\r  ${RED}✗${NC} %s\033[K\n" "$label"
    fi
    return $rc
}

# ─── spin_while — show a spinner while a background PID is alive ─────────
# Usage: long_cmd & spin_while $! "Processing..."
spin_while() {
    local pid="$1" label="$2"
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local frame_count=${#frames[@]}
    local i=0
    local elapsed=0

    tput civis 2>/dev/null
    while kill -0 "$pid" 2>/dev/null; do
        if (( elapsed > 30 )); then
            printf "\r  ${CYAN}${frames[$i]}${NC} %s ${DIM}(%ds)${NC} " "$label" "$elapsed"
        else
            printf "\r  ${CYAN}${frames[$i]}${NC} %s " "$label"
        fi
        i=$(( (i + 1) % frame_count ))
        sleep 0.1
        elapsed=$(( elapsed + 1 ))
        (( elapsed % 10 == 0 )) || true
    done
    tput cnorm 2>/dev/null

    wait "$pid" 2>/dev/null
    local rc=$?
    if (( rc == 0 )); then
        printf "\r  ${GREEN}✓${NC} %s\033[K\n" "$label"
    else
        printf "\r  ${RED}✗${NC} %s\033[K\n" "$label"
    fi
    return $rc
}

# ─── progress_dots — simple inline progress for multi-step operations ────
# Usage: progress_dots "Step 1 of 3: Scanning"
progress_dots() {
    printf "\r  ${CYAN}▸${NC} %s..." "$1"
}
progress_done() {
    printf "\r  ${GREEN}✓${NC} %s\033[K\n" "$1"
}

# ─── menu_option — consistent menu item formatting ──────────────────────
# Usage: menu_option "a" "Ask Claude" ["dim description"]
menu_option() {
    local key="$1" label="$2" desc="${3:-}"
    if [[ -n "$desc" ]]; then
        printf "   ${GREEN}%s${NC})  %-24s ${DIM}%s${NC}\n" "$key" "$label" "$desc"
    else
        printf "   ${GREEN}%s${NC})  %s\n" "$key" "$label"
    fi
}

# ─── menu_back — standard back/quit option ───────────────────────────────
menu_back() {
    local key="${1:-m}" label="${2:-Back}"
    echo ""
    echo -e "  ${DIM}─────────────────────────────────────────────────────${NC}"
    printf "   ${DIM}%s${NC})  ${DIM}%s${NC}\n" "$key" "$label"
    echo ""
}

# ─── first_run_check — detect if this is the user's first time ───────────
_KMAC_STATE_DIR="${HOME}/.config/kmac"
_KMAC_STATE_FILE="${_KMAC_STATE_DIR}/state"

is_first_run() {
    [[ ! -f "$_KMAC_STATE_FILE" ]]
}

mark_first_run_done() {
    mkdir -p "$_KMAC_STATE_DIR"
    echo "first_run=$(date +%s)" > "$_KMAC_STATE_FILE"
}

# ─── tip — random helpful tip shown below the menu ──────────────────────
random_tip() {
    local -a tips=(
        "Type ${GREEN}kmac help${NC} to see all CLI commands"
        "Use ${GREEN}kmac ask${NC} to chat with Claude from anywhere"
        "Press ${GREEN}?${NC} to run a health check on your setup"
        "Use ${GREEN}kmac make${NC} to build custom tools with AI"
        "Press ${GREEN}.${NC} to manage API keys and secrets"
        "Use ${GREEN}kmac review${NC} before every commit for AI code review"
        "Press ${GREEN}S${NC} to find what's eating your disk space"
        "Run ${GREEN}kmac secrets export${NC} to load all API keys into your shell"
        "The ${GREEN}+${NC} key lets you build new tools with natural language"
        "Use ${GREEN}kmac pilot start${NC} to control your Mac from Telegram"
    )
    local idx=$(( RANDOM % ${#tips[@]} ))
    echo -e "  ${DIM}Tip:${NC} ${tips[$idx]}"
}
