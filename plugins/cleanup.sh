#!/bin/bash
# TOOLKIT_NAME: System Cleanup
# TOOLKIT_DESC: Free up disk space (safe targets — matches disk-cleanup playbook)
# TOOLKIT_KEY: 1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)"
# shellcheck source=../scripts/_ui.sh
source "$SCRIPT_DIR/_ui.sh" 2>/dev/null
# shellcheck source=../scripts/_platform.sh
source "$SCRIPT_DIR/_platform.sh" 2>/dev/null

bytes_to_human() {
    local bytes=$1
    if (( bytes >= 1073741824 )); then
        printf "%.1f GB" "$(echo "scale=1; $bytes / 1073741824" | bc)"
    elif (( bytes >= 1048576 )); then
        printf "%.0f MB" "$(echo "scale=0; $bytes / 1048576" | bc)"
    elif (( bytes >= 1024 )); then
        printf "%.0f KB" "$(echo "scale=0; $bytes / 1024" | bc)"
    else
        printf "%d B" "$bytes"
    fi
}

dir_size() {
    du -sk "$1" 2>/dev/null | awk '{print $1 * 1024}'
}

title_box "System Cleanup" "🧹"
echo -e "  ${DIM}Safe targets only — use ${BOLD}S${NC}${DIM} Storage or ${BOLD}kmac docker clean${NC}${DIM} for more.${NC}"
echo ""

local_mount=$(platform_disk_mount)
local_free=$(df -k "$local_mount" | awk 'NR==2 {print $4 * 1024}')
echo -e "  Free space: ${BOLD}$(bytes_to_human "$local_free")${NC}  ${DIM}on ${local_mount}${NC}"
echo ""

echo -e "  ${DIM}Scanning...${NC}"
echo ""

derived_size=$(dir_size "$HOME/Library/Developer/Xcode/DerivedData")
brew_cache="$(brew --cache 2>/dev/null || echo "$HOME/Library/Caches/Homebrew")"
brew_size=$(dir_size "$brew_cache")
trash_size=$(dir_size "$HOME/.Trash")
pip_size=$(dir_size "$HOME/Library/Caches/pip")
npm_size=$(dir_size "$HOME/.npm/_cacache")

echo -e "  ${GREEN}1${NC}  Xcode DerivedData   ${DIM}~/Library/Developer/Xcode/DerivedData${NC}  $(bytes_to_human "$derived_size")"
echo -e "  ${GREEN}2${NC}  Homebrew cache      ${DIM}brew cleanup --prune=all${NC}"
echo -e "  ${GREEN}3${NC}  Trash               ${DIM}~/.Trash${NC}               $(bytes_to_human "$trash_size")"
echo -e "  ${GREEN}4${NC}  pip cache           ${DIM}~/Library/Caches/pip${NC}     $(bytes_to_human "$pip_size")"
echo -e "  ${GREEN}5${NC}  npm cache           ${DIM}~/.npm/_cacache${NC}          $(bytes_to_human "$npm_size")"
echo -e "  ${GREEN}d${NC}  Docker prune        ${DIM}opens kmac docker clean${NC}"
echo -e "  ${GREEN}a${NC}  ${BOLD}All safe targets (1–5)${NC}"
echo -e "  ${GREEN}m${NC}  Back"
echo ""
read -r -n1 -p "  > " choice; echo ""

run_cleanup() {
    local did_something=false

    if [[ "$1" == "1" || "$1" == "a" ]]; then
        local dd="$HOME/Library/Developer/Xcode/DerivedData"
        if [[ -d "$dd" ]]; then
            echo -e "  ${DIM}Clearing DerivedData...${NC}"
            rm -rf "${dd:?}/"* 2>/dev/null
            echo -e "  ${GREEN}✓${NC} DerivedData cleared"
            did_something=true
        fi
    fi

    if [[ "$1" == "2" || "$1" == "a" ]]; then
        echo -e "  ${DIM}Running brew cleanup...${NC}"
        brew cleanup --prune=all 2>/dev/null
        echo -e "  ${GREEN}✓${NC} Homebrew cache cleaned"
        did_something=true
    fi

    if [[ "$1" == "3" || "$1" == "a" ]]; then
        echo -e "  ${DIM}Emptying Trash...${NC}"
        rm -rf "$HOME/.Trash/"* 2>/dev/null
        echo -e "  ${GREEN}✓${NC} Trash emptied"
        did_something=true
    fi

    if [[ "$1" == "4" || "$1" == "a" ]]; then
        echo -e "  ${DIM}Clearing pip cache...${NC}"
        pip cache purge 2>/dev/null
        echo -e "  ${GREEN}✓${NC} pip cache cleared"
        did_something=true
    fi

    if [[ "$1" == "5" || "$1" == "a" ]]; then
        echo -e "  ${DIM}Clearing npm cache...${NC}"
        npm cache clean --force 2>/dev/null
        echo -e "  ${GREEN}✓${NC} npm cache cleared"
        did_something=true
    fi

    if $did_something; then
        echo ""
        local new_free reclaimed
        new_free=$(df -k "$local_mount" | awk 'NR==2 {print $4 * 1024}')
        reclaimed=$(( new_free - local_free ))
        if (( reclaimed > 0 )); then
            echo -e "  ${GREEN}✓${NC} Reclaimed ${BOLD}$(bytes_to_human "$reclaimed")${NC}"
        fi
        echo -e "  Free space now: ${BOLD}$(bytes_to_human "$new_free")${NC}"
    fi
}

case "$choice" in
    1|2|3|4|5) echo ""; run_cleanup "$choice" ;;
    a|A) echo ""; run_cleanup "a" ;;
    d|D)
        echo ""
        echo -e "  ${DIM}Launching Docker cleanup menu...${NC}"
        bash "$SCRIPT_DIR/docker" clean
        ;;
    m|M|*) ;;
esac
