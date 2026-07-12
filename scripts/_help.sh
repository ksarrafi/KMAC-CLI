#!/bin/bash
# _help.sh — Interactive, searchable help system
# Source: source "$SCRIPT_DIR/_help.sh"
# Usage: show_help_menu [filter]

source "${BASH_SOURCE%/*}/_ui.sh" 2>/dev/null

# Command registry: category | key | command | description
declare -a HELP_REGISTRY=(
    # AI & Research
    "AI & Research|a|ask|Ask Claude anything (questions, analysis, coding advice)"
    "AI & Research|+|make|AI Tool Maker — describe what you want, AI builds it"
    "AI & Research|o|ollama|Local AI setup — install and manage Ollama models"
    "AI & Research|R|research|Autonomous experiment runner with AI iteration"
    "AI & Research|A|assistant|Claude AI Assistant gateway (multi-turn sessions)"

    # Dev
    "Dev|p|project|Project launcher with fzf search"
    "Dev|e|claude-code|Launch Claude Code (via claudeme)"
    "Dev|x|cursor-agent|Cursor Agent task runner (type task description)"
    "Dev|v|review|AI code review (--staged, --strict, HEAD~3..HEAD)"
    "Dev|c|aicommit|Generate conventional commit message from diff"
    "Dev|G|skill-opt|Skill Optimizer — improve your personal Claude config"

    # Infra
    "Infra|d|docker|Docker Manager (health, crashes, cleanup, compose, mcp)"
    "Infra|r|remote-terminal|Remote access via ngrok tunnel + ttyd terminal"
    "Infra|P|pilot|Telegram remote agent for your Mac (start/stop)"
    "Infra|n|network|Show local/public IP, Wi-Fi, gateway, listening ports"
    "Infra|k|killport|Find and kill process on a port (e.g., killport 3000)"

    # System
    "System|S|storage|Disk usage analyzer + iCloud file migration"
    "System|V|vault|Project-scoped key manager (set/get/delete per project)"
    "System|.|secrets|Credential manager and integration hub (list/add/export)"
    "System|I|software|Developer tools and AI CLI installer"
    "System|b|dotbackup|Backup/restore/diff dotfiles to iCloud"
    "System|u|update|Check for KMac updates"
    "System|i|install|Bootstrap wizard (Brewfile, prefs, toolkit)"
    "System|/|aliases|Show available aliases and shell functions"
    "System|?|health|System health check (dependencies, vault, paths)"

    # Server & Services (optional)
    "Services|server|server|Pilot API server (start/stop/status/logs/install)"
    "Services|pdac|pdac|Database query tool with web UI (start/stop/open)"
    "Services|monitor|monitor|Background disk/memory watchdog (daemon/status)"
)

# Build category list
declare -a HELP_CATEGORIES=(
    "AI & Research"
    "Dev"
    "Infra"
    "System"
    "Services"
)

show_help_menu() {
    local filter="${1:-}"
    local selected_category=""

    # If fzf available, offer fast search first
    if command -v fzf &>/dev/null; then
        clear
        title_box "KMac Help" "❓"
        echo ""
        echo -e "  ${BOLD}Choose mode:${NC}"
        echo ""
        echo -e "    ${GREEN}f${NC})  ${BOLD}Fast search${NC} with fzf (recommended)"
        echo -e "    ${GREEN}b${NC})  ${BOLD}Browse${NC} by category"
        echo -e "    ${GREEN}a${NC})  ${BOLD}All commands${NC} (list view)"
        echo -e "    ${GREEN}q${NC})  Quit"
        echo ""
        read -r -n1 -p "  Choose (f/b/a/q): " mode_choice; echo ""

        case "$mode_choice" in
            f|F)
                source "${BASH_SOURCE%/*}/_help-fzf.sh" 2>/dev/null
                search_help_with_fzf "$filter"
                return
                ;;
            a|A)
                selected_category="all"
                ;;
            q|Q) return ;;
            b|B|*) ;;  # Fall through to category browse
        esac
    fi

    while true; do
        clear
        title_box "KMac Help" "❓"

        if [[ -z "$selected_category" ]]; then
            # ─── Category menu ───
            echo -e "  ${BOLD}Browse by category:${NC}"
            echo ""
            local cat_num=1
            for cat in "${HELP_CATEGORIES[@]}"; do
                local count=0
                for entry in "${HELP_REGISTRY[@]}"; do
                    [[ "$entry" == "$cat|"* ]] && ((count++))
                done
                printf "    ${GREEN}%d${NC})  ${BOLD}%-20s${NC}  ${DIM}(%d commands)${NC}\n" "$cat_num" "$cat" "$count"
                ((cat_num++))
            done

            echo ""
            echo -e "  ${GREEN}s${NC})  Search keywords"
            echo -e "  ${GREEN}a${NC})  All commands"
            echo -e "  ${GREEN}q${NC})  Quit"
            echo ""
            read -r -n1 -p "  Choose (1-${#HELP_CATEGORIES[@]}/s/a/q): " choice; echo ""

            case "$choice" in
                q|Q) return ;;
                s|S)
                    echo ""
                    read -r -p "  Search for: " search_term
                    selected_category="search:$search_term"
                    ;;
                a|A)
                    selected_category="all"
                    ;;
                *)
                    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#HELP_CATEGORIES[@]} )); then
                        selected_category="${HELP_CATEGORIES[$((choice-1))]}"
                    else
                        continue
                    fi
                    ;;
            esac
        fi

        # ─── Show commands in category ───
        if [[ "$selected_category" == "search:"* ]]; then
            search_term="${selected_category#search:}"
            clear
            title_box "Search Results" "🔍"
            echo -e "  ${DIM}Searching for: ${BOLD}${search_term}${NC}"
            echo ""

            local found=0
            for entry in "${HELP_REGISTRY[@]}"; do
                IFS='|' read -r cat key cmd desc <<< "$entry"
                if [[ "$cmd" == *"$search_term"* ]] || [[ "$desc" == *"$search_term"* ]] || [[ "$key" == "$search_term" ]]; then
                    printf "  ${GREEN}${key}${NC})  ${BOLD}%-20s${NC}  ${desc}\n" "$cmd"
                    ((found++))
                fi
            done

            if (( found == 0 )); then
                echo -e "  ${YELLOW}No commands match '${search_term}'${NC}"
            fi

            echo ""
            echo -e "  ${GREEN}b${NC})  Back to menu  ${GREEN}q${NC})  Quit  ${GREEN}s${NC})  New search"
            echo ""
            read -r -n1 -p "  > " back_choice; echo ""

            case "$back_choice" in
                b|B) selected_category="" ;;
                q|Q) return ;;
                s|S) selected_category="" ;;
                *) continue ;;
            esac
        else
            # Show full category
            clear
            title_box "$selected_category Commands" "📋"
            echo ""

            local cmd_count=0
            for entry in "${HELP_REGISTRY[@]}"; do
                IFS='|' read -r cat key cmd desc <<< "$entry"
                if [[ "$selected_category" == "all" ]] || [[ "$cat" == "$selected_category" ]]; then
                    printf "  ${GREEN}${key}${NC})  ${BOLD}%-16s${NC}  ${desc}\n" "$cmd"
                    ((cmd_count++))
                fi
            done

            if (( cmd_count == 0 )); then
                echo -e "  ${YELLOW}No commands found${NC}"
            fi

            echo ""
            echo -e "  ${GREEN}b${NC})  Back to menu  ${GREEN}q${NC})  Quit  ${GREEN}s${NC})  Search"
            echo ""
            read -r -n1 -p "  > " nav_choice; echo ""

            case "$nav_choice" in
                b|B) selected_category="" ;;
                q|Q) return ;;
                s|S) selected_category="" ;;
                *) continue ;;
            esac
        fi
    done
}

# Print text-based help (for `kmac help` or piped output)
print_help_text() {
    title_box "KMac Commands" "❓"
    echo ""

    local current_cat=""
    for entry in "${HELP_REGISTRY[@]}"; do
        IFS='|' read -r cat key cmd desc <<< "$entry"

        if [[ "$cat" != "$current_cat" ]]; then
            echo ""
            echo -e "  ${C_CYAN}${BOLD}${cat}${NC}"
            echo -e "  ${DIM}$(printf '─%.0s' {1..60})${NC}"
            current_cat="$cat"
        fi

        printf "    ${GREEN}%-2s${NC}  ${BOLD}%-18s${NC}  %s\n" "$key" "$cmd" "$desc"
    done

    echo ""
    echo -e "  ${DIM}Usage: kmac COMMAND [options]${NC}"
    echo -e "  ${DIM}For command-specific help: kmac COMMAND --help${NC}"
    echo ""
}

# Export for use in other scripts
export -f show_help_menu
export -f print_help_text
export HELP_REGISTRY
