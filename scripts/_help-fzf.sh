#!/bin/bash
# _help-fzf.sh — Fast fzf-powered help search
# Source: source "$SCRIPT_DIR/_help-fzf.sh"
# Usage: search_help_with_fzf [query]

source "${BASH_SOURCE%/*}/_ui.sh" 2>/dev/null
source "${BASH_SOURCE%/*}/_help.sh" 2>/dev/null

# ─── fzf-powered help search ───
search_help_with_fzf() {
    local query="${1:-}"

    if ! command -v fzf &>/dev/null; then
        # Fallback to interactive menu if fzf not available
        show_help_menu "$query"
        return
    fi

    clear
    title_box "KMac Help — fzf Search" "🔍"
    echo ""
    echo -e "  ${DIM}Type to search. Press Enter to select. Esc to exit.${NC}"
    echo ""

    # Build searchable list from HELP_REGISTRY
    local -a help_list=()
    for entry in "${HELP_REGISTRY[@]}"; do
        IFS='|' read -r cat key cmd desc <<< "$entry"
        # Format: "key) cmd — description [category]"
        help_list+=("${key}${NC})  ${cmd}  ${DIM}—${NC}  ${desc}  ${DIM}[${cat}]${NC}")
    done

    # Use fzf for fast search
    local selected
    selected=$(printf '%s\n' "${help_list[@]}" | \
        fzf \
            --ansi \
            --no-sort \
            --height 50% \
            --preview 'echo {}' \
            --preview-window 'right:30%:wrap' \
            --bind 'change:top' \
            --query "$query" 2>/dev/null)

    if [[ -n "$selected" ]]; then
        # Extract key from selection
        local key="${selected%%[)]*}"
        key="${key##*[}}"  # Remove ANSI codes
        key="$(echo "$key" | xargs)"  # Trim whitespace

        clear
        title_box "Command Details" "📖"
        echo ""

        # Find matching entry
        for entry in "${HELP_REGISTRY[@]}"; do
            IFS='|' read -r cat cmd_key cmd desc <<< "$entry"
            if [[ "$cmd_key" == "$key" ]]; then
                echo -e "  ${BOLD}${cmd}${NC}  ${DIM}[${cat}]${NC}"
                echo -e "  ${DIM}$(printf '─%.0s' {1..60})${NC}"
                echo ""
                echo -e "  ${desc}"
                echo ""
                echo -e "  ${DIM}Usage:${NC}"
                echo -e "    ${GREEN}kmac ${cmd}${NC} [options]"
                echo -e "    ${GREEN}kmac ${cmd}${NC} --help"
                echo ""
                echo -e "  ${DIM}Press any key to continue...${NC}"
                read -r -n1
                break
            fi
        done
    fi
}

export -f search_help_with_fzf
