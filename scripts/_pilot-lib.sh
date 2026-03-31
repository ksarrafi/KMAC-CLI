#!/bin/bash
# _pilot-lib.sh — Shared constants and helpers for KMac Pilot
# Source this in pilot scripts: source "$(dirname "${BASH_SOURCE[0]}")/_pilot-lib.sh"

PILOT_DIR="${XDG_RUNTIME_DIR:-$HOME/.config/kmac-pilot/run}"
PILOT_PID_FILE="$PILOT_DIR/bot.pid"
PILOT_AGENT_PID="$PILOT_DIR/agent.pid"
export PILOT_AGENT_LOG="$PILOT_DIR/agent.log"
PILOT_TASK_FILE="$PILOT_DIR/task.json"
export PILOT_OFFSET_FILE="$PILOT_DIR/update_offset"
PILOT_CONFIG="$HOME/.config/kmac-pilot/config.json"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_ui.sh
source "$SCRIPT_DIR/_ui.sh" 2>/dev/null

TELEGRAM_API="https://api.telegram.org/bot"

# ─── Config helpers ──────────────────────────────────────────────────────

pilot_ensure_dirs() {
    mkdir -p "$PILOT_DIR" && chmod 700 "$PILOT_DIR"
    mkdir -p "$(dirname "$PILOT_CONFIG")"
}

pilot_get_config() {
    local key="$1"
    [[ -f "$PILOT_CONFIG" ]] && jq -r ".$key // empty" "$PILOT_CONFIG" 2>/dev/null
}

pilot_set_config() {
    local key="$1" value="$2"
    pilot_ensure_dirs
    local tmp tmpfile
    if [[ -f "$PILOT_CONFIG" ]]; then
        tmp=$(jq --arg k "$key" --arg v "$value" '.[$k] = $v' "$PILOT_CONFIG")
    else
        tmp=$(jq -n --arg k "$key" --arg v "$value" '{($k): $v}')
    fi
    tmpfile=$(mktemp "${PILOT_CONFIG}.XXXXXX")
    printf '%s\n' "$tmp" > "$tmpfile" && mv -f "$tmpfile" "$PILOT_CONFIG"
}

pilot_token()   { pilot_get_config "telegram_token"; }
pilot_chat_id() { pilot_get_config "chat_id"; }

# Active AI agent: "claude" or "cursor" (default: claude)
pilot_agent() {
    local a
    a=$(pilot_get_config "agent")
    echo "${a:-claude}"
}

# Deprecated: embedding $task in a shell string is unsafe (quote-breaking / injection).
# Not referenced elsewhere; use explicit argv arrays at call sites if this is revived.
# pilot_agent_cmd() {
#     local task="$1"
#     case "$(pilot_agent)" in
#         cursor) echo "cursor agent \"$task\"" ;;
#         *)      echo "claude --print \"$task\"" ;;
#     esac
# }

pilot_agent_label() {
    case "$(pilot_agent)" in
        cursor)     echo "Cursor Agent" ;;
        kmac-agent) echo "KmacAgent" ;;
        *)          echo "Claude Code" ;;
    esac
}

pilot_project_dirs() {
    local dirs
    dirs=$(pilot_get_config "project_dirs")
    if [[ -z "$dirs" ]]; then
        echo "$HOME/Projects"
    else
        echo "$dirs"
    fi
}

# Find all scannable project directories (supports comma-separated list)
pilot_scan_dirs() {
    local base
    base=$(pilot_project_dirs)
    echo "$base" | tr ',' '\n' | while IFS= read -r d; do
        d=$(echo "$d" | xargs)  # trim whitespace
        [[ -d "$d" ]] && echo "$d"
    done
}

# Directories to skip during deep scanning
_SCAN_SKIP="node_modules|.git|.next|__pycache__|.venv|venv|dist|build|.turbo|.cache|.tox|Backup|Archive|backup"

# Resolve a project name to its full path.
# Checks immediate children first, then scans up to 3 levels deep.
pilot_resolve_project() {
    local name="$1"
    local dir

    if [[ "$name" == *['*?[']* ]]; then
        return 1
    fi

    # Fast path: direct child of a scan dir
    while IFS= read -r dir; do
        [[ -d "$dir/$name" ]] && echo "$dir/$name" && return 0
    done < <(pilot_scan_dirs)

    # Deep search: walk up to 3 levels for a matching dir name
    while IFS= read -r dir; do
        local match
        match=$(find "$dir" -maxdepth 3 -mindepth 2 -type d -name "$name" \
            ! -path '*/Backup/*' ! -path '*/Archive/*' ! -path '*/backup/*' \
            ! -path '*/node_modules/*' ! -path '*/.git/*' 2>/dev/null | head -1)
        [[ -n "$match" ]] && echo "$match" && return 0
    done < <(pilot_scan_dirs)

    return 1
}

# List all projects from configured scan dirs.
# Shows immediate children (git or not), plus discovers git repos up
# to 2 extra levels inside non-git "namespace" directories.
# Deduplicates by path when scan dirs overlap.
pilot_list_projects() {
    local dir _seen_paths=""

    while IFS= read -r dir; do
        local label="${dir/#$HOME/~}"

        for child in "$dir"/*/; do
            [[ -d "$child" ]] || continue
            local _pn="${child%/}"
            _pn="${_pn##*/}"
            [[ "$_pn" == .* || "$_pn" == "node_modules" ]] && continue

            local _cpath="${child%/}"
            # Deduplicate by path
            case "$_seen_paths" in *"|${_cpath}|"*) continue ;; esac
            _seen_paths="${_seen_paths}|${_cpath}|"

            if [[ -d "$child/.git" ]]; then
                local _br=""
                _br=$(git -C "$child" branch --show-current 2>/dev/null)
                echo "${_pn}|${_cpath}|${_br:-—}|${label}"
            else
                # Non-git immediate child — list it
                echo "${_pn}|${_cpath}|—|${label}"

                # Also scan 2 levels deeper for git repos (skip Backup/Archive)
                [[ "|${_SCAN_SKIP}|" == *"|${_pn}|"* ]] && continue
                for deep in "${_cpath}"/*/ "${_cpath}"/*/*/; do
                    [[ -d "$deep" ]] || continue
                    [[ -d "$deep/.git" ]] || continue
                    local _dn="${deep%/}"
                    _dn="${_dn##*/}"
                    local _dpath="${deep%/}"

                    # Skip if inside a Backup/Archive directory
                    case "$_dpath" in */Backup/*|*/Archive/*|*/backup/*) continue ;; esac

                    case "$_seen_paths" in *"|${_dpath}|"*) continue ;; esac
                    _seen_paths="${_seen_paths}|${_dpath}|"

                    local _dbr=""
                    _dbr=$(git -C "$deep" branch --show-current 2>/dev/null)
                    echo "${_dn}|${_dpath}|${_dbr:-—}|${label}"
                done
            fi
        done
    done < <(pilot_scan_dirs)
}

# ─── Telegram helpers ────────────────────────────────────────────────────

tg_call() {
    local method="$1"; shift
    local token
    token=$(pilot_token)
    [[ -z "$token" ]] && return 1
    curl -sf --max-time 65 "${TELEGRAM_API}${token}/${method}" "$@"
}

# Show "typing..." indicator in the chat
tg_typing() {
    local chat_id="$1"
    tg_call "sendChatAction" -d "chat_id=$chat_id" -d "action=typing" &>/dev/null
}

tg_send() {
    local chat_id="$1" text="$2"
    # Telegram max message is 4096 chars — truncate if needed
    if (( ${#text} > 4000 )); then
        text="${text:0:3990}...(truncated)"
    fi
    tg_call "sendMessage" \
        -d "chat_id=$chat_id" \
        --data-urlencode "text=$text" \
        -d "parse_mode=Markdown" \
        -d "disable_web_page_preview=true" 2>/dev/null
}

tg_send_plain() {
    local chat_id="$1" text="$2"
    if (( ${#text} > 4000 )); then
        text="${text:0:3990}...(truncated)"
    fi
    tg_call "sendMessage" \
        -d "chat_id=$chat_id" \
        --data-urlencode "text=$text" \
        -d "disable_web_page_preview=true" 2>/dev/null
}

# Send a file as a Telegram document
tg_send_document() {
    local chat_id="$1" filepath="$2" caption="${3:-}"
    local token
    token=$(pilot_token)
    [[ -z "$token" ]] && return 1
    if [[ -n "$caption" ]]; then
        curl -sf --max-time 30 "${TELEGRAM_API}${token}/sendDocument" \
            -F "chat_id=$chat_id" \
            -F "document=@$filepath" \
            -F "caption=$caption" 2>/dev/null
    else
        curl -sf --max-time 30 "${TELEGRAM_API}${token}/sendDocument" \
            -F "chat_id=$chat_id" \
            -F "document=@$filepath" 2>/dev/null
    fi
}

# ─── Agent helpers ───────────────────────────────────────────────────────

pilot_agent_running() {
    [[ -f "$PILOT_AGENT_PID" ]] && kill -0 "$(cat "$PILOT_AGENT_PID" 2>/dev/null)" 2>/dev/null
}

pilot_bot_running() {
    [[ -f "$PILOT_PID_FILE" ]] && kill -0 "$(cat "$PILOT_PID_FILE" 2>/dev/null)" 2>/dev/null
}

pilot_current_task() {
    [[ -f "$PILOT_TASK_FILE" ]] && cat "$PILOT_TASK_FILE" 2>/dev/null
}

pilot_task_field() {
    local field="$1"
    [[ -f "$PILOT_TASK_FILE" ]] && jq -r ".$field // empty" "$PILOT_TASK_FILE" 2>/dev/null
}
