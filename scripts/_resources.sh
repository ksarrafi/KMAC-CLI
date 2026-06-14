#!/bin/bash
# _resources.sh — disk + swap snapshot for menu alerts and resource-watch
# Expects _ui.sh colors when printing (sourced from toolkit.sh).

kmac_resources_disk_pct() {
    local line pct mount
    # shellcheck source=scripts/_platform.sh
    [[ -z "${KMAC_PLATFORM_LOADED:-}" ]] && source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_platform.sh"
    mount=$(platform_disk_mount)
    line=$(df -k "$mount" 2>/dev/null | tail -1)
    pct=$(echo "$line" | awk '{gsub(/%/,"",$5); print 0+$5}')
    echo "${pct:-0}"
}

kmac_resources_load_swap_mb() {
    KMAC_RES_SWAP_USED_MB=0
    KMAC_RES_SWAP_TOTAL_MB=0
    case "$(uname -s 2>/dev/null)" in
        Darwin)
            local line
            line=$(sysctl -n vm.swapusage 2>/dev/null) || return 0
            KMAC_RES_SWAP_TOTAL_MB=$(echo "$line" | sed -E 's/.*total = ([0-9.]+)M.*/\1/' | head -1)
            KMAC_RES_SWAP_USED_MB=$(echo "$line" | sed -E 's/.*used = ([0-9.]+)M.*/\1/' | head -1)
            ;;
        Linux)
            [[ -r /proc/meminfo ]] || return 0
            local st sf
            st=$(awk '/^SwapTotal:/ {print $2+0}' /proc/meminfo)
            sf=$(awk '/^SwapFree:/ {print $2+0}' /proc/meminfo)
            st=${st:-0}
            sf=${sf:-0}
            KMAC_RES_SWAP_TOTAL_MB=$(( st / 1024 ))
            KMAC_RES_SWAP_USED_MB=$(( (st - sf) / 1024 ))
            ;;
    esac
    [[ "$KMAC_RES_SWAP_TOTAL_MB" =~ ^[0-9.]+$ ]] || KMAC_RES_SWAP_TOTAL_MB=0
    [[ "$KMAC_RES_SWAP_USED_MB" =~ ^[0-9.]+$ ]] || KMAC_RES_SWAP_USED_MB=0
}

# Sets KMAC_RES_MEM_LEVEL: ok | warn | crit
kmac_resources_mem_level() {
    kmac_resources_load_swap_mb
    local u t
    u=${KMAC_RES_SWAP_USED_MB%%.*}
    t=${KMAC_RES_SWAP_TOTAL_MB%%.*}
    u=${u:-0}
    t=${t:-0}
    KMAC_RES_MEM_LEVEL="ok"
    (( t <= 0 )) && return 0
    if (( u >= 2048 )) || (( u * 2 >= t )); then
        KMAC_RES_MEM_LEVEL="crit"
    elif (( u >= 256 )) && (( u * 10 >= t )); then
        KMAC_RES_MEM_LEVEL="warn"
    fi
}

# Print extra lines inside the menu box (caller draws borders).
kmac_resources_print_menu_alerts() {
    local disk_pct="${1:-0}"
    local vb="${KMAC_VAULT_BACKEND:-docker}"

    kmac_resources_mem_level
    local mem="$KMAC_RES_MEM_LEVEL"

    if (( disk_pct >= 90 )); then
        echo -e "  ${DIM}│${NC}  ${RED}${BOLD}!${NC} ${RED}Disk critically low (${disk_pct}%)${NC}${DIM} —${NC} ${BOLD}S${NC} Storage  ${DIM}·${NC} ${BOLD}kmac docker clean${NC}  ${DIM}│${NC}"
        if [[ "$vb" == "docker" ]]; then
            echo -e "  ${DIM}│${NC}  ${YELLOW}Docker vault can block startup — ${BOLD}KMAC_VAULT_BACKEND=keychain${NC}${YELLOW} if stuck${NC} ${DIM}│${NC}"
        fi
    elif (( disk_pct >= 80 )); then
        echo -e "  ${DIM}│${NC}  ${YELLOW}Disk filling (${disk_pct}%)${NC}${DIM} — use${NC} ${BOLD}S${NC}${DIM} before Docker/tools fail${NC}                    ${DIM}│${NC}"
    fi

    if [[ "$mem" == "crit" ]]; then
        echo -e "  ${DIM}│${NC}  ${RED}Heavy swap (${KMAC_RES_SWAP_USED_MB}M)${NC}${DIM} — free RAM; Docker needs memory${NC}              ${DIM}│${NC}"
    elif [[ "$mem" == "warn" ]]; then
        echo -e "  ${DIM}│${NC}  ${YELLOW}Swap use ${KMAC_RES_SWAP_USED_MB}M / ${KMAC_RES_SWAP_TOTAL_MB}M${NC}${DIM} — memory pressure${NC}                    ${DIM}│${NC}"
    fi
}
