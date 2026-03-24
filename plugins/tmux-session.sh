#!/bin/bash
# TOOLKIT_NAME: Tmux Sessions
# TOOLKIT_DESC: Quick tmux session create, attach, and list
# TOOLKIT_KEY: 7

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../scripts/_ui.sh
source "$SCRIPT_DIR/../scripts/_ui.sh"

_ensure_tmux() {
    if ! command -v tmux &>/dev/null; then
        ui_fail "tmux is not installed. Run: brew install tmux"
        return 1
    fi
}

tmux_list() {
    _ensure_tmux || return 1
    local sessions
    sessions=$(tmux list-sessions 2>/dev/null)
    if [[ -z "$sessions" ]]; then
        ui_info "No active tmux sessions"
    else
        title_box "Tmux Sessions" "🪟"
        echo "$sessions"
    fi
}

tmux_new() {
    _ensure_tmux || return 1
    local name="${1:-dev}"
    if tmux has-session -t "$name" 2>/dev/null; then
        ui_info "Attaching to existing session '$name'"
        tmux attach-session -t "$name"
    else
        ui_info "Creating session '$name'"
        tmux new-session -s "$name"
    fi
}

tmux_kill() {
    _ensure_tmux || return 1
    local name="${1:-}"
    if [[ -z "$name" ]]; then
        ui_fail "Usage: kmac tmux-session kill <name>"
        return 1
    fi
    if tmux kill-session -t "$name" 2>/dev/null; then
        ui_success "Killed session '$name'"
    else
        ui_fail "Session '$name' not found"
    fi
}

case "${1:-}" in
    list|"") tmux_list ;;
    new)     shift; tmux_new "$@" ;;
    kill)    shift; tmux_kill "$@" ;;
    help)    echo "Usage: kmac tmux-session [list|new <name>|kill <name>]" ;;
    *)       echo "Unknown command: $1"; exit 1 ;;
esac
