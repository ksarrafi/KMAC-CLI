#!/bin/bash
# _ui.sh — shared UI helpers for toolkit scripts
# Source this in any script: source "$SCRIPT_DIR/_ui.sh"

# Colors (safe to re-declare — no-ops if already set)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# 256-color palette for gradients
C_BLUE='\033[38;5;33m'
C_CYAN='\033[38;5;39m'
C_TEAL='\033[38;5;45m'
C_GREEN='\033[38;5;49m'
C_MINT='\033[38;5;84m'

# title_box — styled header for sub-features
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

# pause — standard "press any key" prompt
pause() {
    echo ""
    echo -e -n "${DIM}Press any key to continue...${NC}"
    read -r -n1
}
