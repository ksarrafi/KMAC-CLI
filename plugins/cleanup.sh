#!/bin/bash
# TOOLKIT_NAME: System Cleanup
# TOOLKIT_DESC: Free up disk space (caches, logs, trash, Docker)
# TOOLKIT_KEY: 1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)"
# shellcheck source=../scripts/_ui.sh
source "$SCRIPT_DIR/_ui.sh" 2>/dev/null

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

# Calculate size of a directory safely
dir_size() {
    du -sk "$1" 2>/dev/null | awk '{print $1 * 1024}'
}

title_box "System Cleanup" "🧹"

# Show current free space
local_free=$(df -k / | awk 'NR==2 {print $4 * 1024}')
echo -e "  Free space: ${BOLD}$(bytes_to_human "$local_free")${NC}"
echo ""

# Scan what can be cleaned
echo -e "  ${DIM}Scanning...${NC}"
echo ""

cache_size=$(dir_size ~/Library/Caches)
log_size=$(du -sk /var/log/*.gz /var/log/*.bz2 /var/log/*.old 2>/dev/null | awk '{s+=$1} END {print (s ? s : 0) * 1024}')
trash_size=$(dir_size ~/.Trash)
# Docker — only check if running
docker_size=0
docker_label="not running"
if timeout 2 docker info &>/dev/null 2>&1; then
    docker_size=$(docker system df 2>/dev/null | awk 'NR>1 {gsub(/[A-Za-z]/,"",$4); s+=$4} END {print int(s * 1073741824)}')
    docker_label="$(bytes_to_human "${docker_size:-0}") reclaimable"
fi

echo -e "  ${GREEN}1${NC}  User Caches        ${DIM}~/Library/Caches${NC}        $(bytes_to_human "$cache_size")"
echo -e "  ${GREEN}2${NC}  Old Log Files      ${DIM}/var/log (compressed)${NC}   $(bytes_to_human "$log_size")"
echo -e "  ${GREEN}3${NC}  Trash              ${DIM}~/.Trash${NC}               $(bytes_to_human "$trash_size")"
echo -e "  ${GREEN}4${NC}  Homebrew Cache      ${DIM}brew cleanup${NC}"
echo -e "  ${GREEN}5${NC}  Docker             ${DIM}${docker_label}${NC}"
echo -e "  ${GREEN}a${NC}  ${BOLD}All of the above${NC}"
echo -e "  ${GREEN}m${NC}  Back"
echo ""
read -r -n1 -p "  > " choice; echo ""

run_cleanup() {
    local did_something=false

    if [[ "$1" == "1" || "$1" == "a" ]]; then
        echo -e "  ${DIM}Clearing user caches...${NC}"
        rm -rf ~/Library/Caches/* 2>/dev/null
        echo -e "  ${GREEN}✓${NC} User caches cleared"
        did_something=true
    fi

    if [[ "$1" == "2" || "$1" == "a" ]]; then
        echo -e "  ${DIM}Clearing old log files...${NC}"
        sudo rm -rf /var/log/*.gz /var/log/*.bz2 /var/log/*.old 2>/dev/null
        echo -e "  ${GREEN}✓${NC} Old logs cleared"
        did_something=true
    fi

    if [[ "$1" == "3" || "$1" == "a" ]]; then
        echo -e "  ${DIM}Emptying Trash...${NC}"
        rm -rf ~/.Trash/* 2>/dev/null
        echo -e "  ${GREEN}✓${NC} Trash emptied"
        did_something=true
    fi

    if [[ "$1" == "4" || "$1" == "a" ]]; then
        echo -e "  ${DIM}Running brew cleanup...${NC}"
        brew cleanup 2>/dev/null
        echo -e "  ${GREEN}✓${NC} Homebrew cache cleaned"
        did_something=true
    fi

    if [[ "$1" == "5" || "$1" == "a" ]]; then
        if timeout 2 docker info &>/dev/null 2>&1; then
            echo -e "  ${DIM}Running Docker system prune...${NC}"
            docker system prune -af 2>/dev/null
            echo -e "  ${GREEN}✓${NC} Docker cleaned up"
        else
            echo -e "  ${YELLOW}⚠${NC}  Docker not running, skipping"
        fi
        did_something=true
    fi

    if $did_something; then
        echo ""
        local new_free
        new_free=$(df -k / | awk 'NR==2 {print $4 * 1024}')
        local reclaimed=$(( new_free - local_free ))
        if (( reclaimed > 0 )); then
            echo -e "  ${GREEN}✓${NC} Reclaimed ${BOLD}$(bytes_to_human "$reclaimed")${NC}"
        fi
        echo -e "  Free space now: ${BOLD}$(bytes_to_human "$new_free")${NC}"
    fi
}

case "$choice" in
    1|2|3|4|5) echo ""; run_cleanup "$choice" ;;
    a|A) echo ""; run_cleanup "a" ;;
    m|M|*) ;;
esac
