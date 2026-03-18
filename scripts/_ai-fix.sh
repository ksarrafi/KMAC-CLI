#!/bin/bash
# _ai-fix.sh — AI-powered error diagnosis and self-healing
# Source this in any script, then use: ai_diagnose "error output" "what was attempted"
# Or use the wrapper: run_with_ai_fix <command> [args...]

# Requires _auth-helper.sh to be sourced first for _claude_ask

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_auth-helper.sh"

RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[0;33m' CYAN='\033[0;36m'
BOLD='\033[1m' DIM='\033[2m' NC='\033[0m'

# ─── Shell Environment Helper ────────────────────────────────────────────
# nvm, rvm, etc. are shell functions, not binaries. If a fix command uses
# them we need to source the init script first.

_prepare_shell_env() {
    local cmd="$1"
    local prefix=""
    # If command uses nvm, source it first
    if [[ "$cmd" == *"nvm "* ]]; then
        local nvm_init="$HOME/.nvm/nvm.sh"
        if [[ -f "$nvm_init" ]]; then
            prefix="source \"$nvm_init\" && "
        else
            echo -e "${YELLOW}⚠  nvm not found at $nvm_init — you may need to run this manually${NC}"
        fi
    fi
    # If command uses rvm, source it
    if [[ "$cmd" == *"rvm "* ]]; then
        local rvm_init="$HOME/.rvm/scripts/rvm"
        [[ -f "$rvm_init" ]] && prefix="${prefix}source \"$rvm_init\" && "
    fi
    echo "${prefix}${cmd}"
}

# ─── AI Diagnose ──────────────────────────────────────────────────────────

ai_diagnose() {
    local error_output="$1"
    local context="$2"  # what was being attempted
    local system_info=""

    # Gather system context
    system_info="macOS $(sw_vers -productVersion 2>/dev/null), "
    system_info+="Node $(node --version 2>/dev/null || echo 'not found'), "
    system_info+="npm $(npm --version 2>/dev/null || echo 'not found'), "
    system_info+="brew $(brew --version 2>/dev/null | head -1 || echo 'not found')"
    # Also note nvm versions available
    local nvm_versions=""
    if [[ -d "$HOME/.nvm/versions/node" ]]; then
        nvm_versions=$(ls "$HOME/.nvm/versions/node" 2>/dev/null | tr '\n' ', ')
        system_info+=", nvm nodes: $nvm_versions"
    fi

    _ensure_claude_auth || return 1

    local prompt="You are a macOS terminal troubleshooter. Diagnose this error and give ONE fix command.

IMPORTANT: nvm is a shell function, not a binary. If your fix involves nvm, include 'source ~/.nvm/nvm.sh &&' before any nvm commands. Prefer using full paths to node/npm binaries when possible (e.g. ~/.nvm/versions/node/v22.x.x/bin/npm).

SYSTEM: $system_info
TASK: $context
ERROR:
$error_output
Reply in EXACTLY this format (no markdown, no backticks):
DIAGNOSIS: one-line explanation of what went wrong
FIX: the exact shell command to fix it
SAFE: yes or no (is this safe to run automatically?)
NOTE: optional one-line note if the user should know something"

    local response
    response=$(_claude_ask "$prompt" "claude-haiku-4-5" 500 "Diagnosing")

    if [[ -z "$response" ]]; then
        echo -e "${YELLOW}Could not reach AI for diagnosis.${NC}"
        return 1
    fi

    # Parse response
    local diagnosis fix safe note
    diagnosis=$(echo "$response" | grep -i '^DIAGNOSIS:' | sed 's/^DIAGNOSIS: *//')
    fix=$(echo "$response" | grep -i '^FIX:' | sed 's/^FIX: *//')
    safe=$(echo "$response" | grep -i '^SAFE:' | sed 's/^SAFE: *//' | tr '[:upper:]' '[:lower:]')
    note=$(echo "$response" | grep -i '^NOTE:' | sed 's/^NOTE: *//')

    echo ""
    echo -e "${BOLD}${CYAN}🤖 AI Diagnosis${NC}"
    echo -e "   ${diagnosis}"
    if [[ -n "$note" && "$note" != "none" && "$note" != "N/A" ]]; then
        echo -e "   ${DIM}${note}${NC}"
    fi

    AI_FIX_CMD=""
    if [[ -n "$fix" && "$fix" != "none" && "$fix" != "N/A" ]]; then
        AI_FIX_CMD="$fix"
        echo ""
        echo -e "   Suggested fix:"
        echo -e "   ${GREEN}$ ${fix}${NC}"
        echo ""

        if [[ "$safe" == "yes" ]]; then
            echo -e "   ${GREEN}a)${NC} Run fix automatically"
        else
            echo -e "   ${YELLOW}a)${NC} Run fix ${YELLOW}(AI says: review first)${NC}"
        fi
        echo -e "   ${GREEN}c)${NC} Copy fix to clipboard"
        echo -e "   ${GREEN}s)${NC} Skip"
        echo ""
        read -r -n1 -p "   > " fix_choice
        echo ""

        case "$fix_choice" in
            a|A)
                echo ""
                # Prepare the command — auto-source nvm/rvm if needed
                local prepared_cmd
                prepared_cmd=$(_prepare_shell_env "$fix")
                echo -e "${DIM}Running: $prepared_cmd${NC}"
                echo ""
                eval "$prepared_cmd" 2>&1
                local rc=$?
                if (( rc == 0 )); then
                    echo -e "\n${GREEN}✓ Fix applied successfully!${NC}"
                else
                    echo -e "\n${RED}Fix command exited with code $rc${NC}"
                    echo -e "${DIM}You may need to run it manually or try a different approach.${NC}"
                fi
                # Refresh update cache so menu reflects the new state
                local _cache="/tmp/toolkit-update-cache/last-check.json"
                if [[ -f "$_cache" ]]; then
                    rm -f "$_cache"
                fi
                return $rc
                ;;
            c|C)
                echo -n "$fix" | pbcopy
                echo -e "   ${GREEN}✓ Copied to clipboard${NC}"
                ;;
            s|S|*)
                echo -e "   ${DIM}Skipped.${NC}"
                ;;
        esac
    fi
    return 0
}

# run_with_ai_fix — wrapper that runs a command and offers AI fix on failure
# Usage: run_with_ai_fix "description of task" command arg1 arg2 ...
run_with_ai_fix() {
    local description="$1"
    shift
    local cmd_display="$*"

    # Capture both stdout and stderr
    local output
    output=$("$@" 2>&1)
    local rc=$?

    if (( rc == 0 )); then
        echo "$output"
        return 0
    fi

    # Command failed — show error and offer AI diagnosis
    echo "$output"
    echo ""
    echo -e "${RED}⚠  Error running: ${cmd_display}${NC}"
    echo ""
    echo -e "  ${GREEN}f)${NC} Ask AI to diagnose & fix"
    echo -e "  ${GREEN}r)${NC} Retry"
    echo -e "  ${GREEN}s)${NC} Skip"
    echo ""
    read -r -n1 -p "  > " err_choice
    echo ""

    case "$err_choice" in
        f|F) ai_diagnose "$output" "$description" ;;
        r|R) run_with_ai_fix "$description" "$@" ;;
        s|S|*) return $rc ;;
    esac
}
