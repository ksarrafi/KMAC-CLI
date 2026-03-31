#!/bin/bash
# _auth-helper.sh — shared Anthropic API helper
# Source this in any script that needs Claude AI.
# Provides: _ensure_claude_auth, _claude_ask

_ensure_claude_auth() {
    if [[ -n "${ANTHROPIC_API_KEY:-}" && "$ANTHROPIC_API_KEY" != "your-api-key-here" ]]; then
        return 0
    fi

    # Try vault (supports both Keychain and encrypted file backends)
    if type vault_get &>/dev/null; then
        local key
        key=$(vault_get "anthropic" 2>/dev/null)
        if [[ -n "$key" ]]; then
            export ANTHROPIC_API_KEY="$key"
            return 0
        fi
    fi

    # Legacy: direct Keychain lookup for backward compatibility
    local key
    key=$(security find-generic-password -s "toolkit-anthropic" -w 2>/dev/null \
       || security find-generic-password -s "kmac-anthropic" -w 2>/dev/null)
    if [[ -n "$key" ]]; then
        export ANTHROPIC_API_KEY="$key"
        return 0
    fi

    echo "⚠  No Anthropic API key found."
    echo ""
    echo "Set one up:"
    echo "  1) kmac → Secrets (.) → set anthropic"
    echo "  2) export ANTHROPIC_API_KEY=\"sk-ant-...\" in shell"
    echo ""
    echo "Get a key: https://console.anthropic.com/settings/keys"
    return 1
}

# ─── AI Spinner ───────────────────────────────────────────────────────────
# Braille spinner with "thinking" animation on stderr so it doesn't
# pollute captured output.

_ai_spin_pid=""

_ai_spin_start() {
    local label="${1:-Thinking}"
    local model_tag="${2:-}"
    (
        local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
        local colors=('\033[0;36m' '\033[0;35m' '\033[0;34m' '\033[0;36m')
        local i=0 c=0 dots=""
        while true; do
            local f="${frames[i % ${#frames[@]}]}"
            local clr="${colors[c % ${#colors[@]}]}"
            # Build pulsing dots
            case $(( i % 12 )) in
                0|1|2)   dots="   " ;;
                3|4|5)   dots=".  " ;;
                6|7|8)   dots=".. " ;;
                9|10|11) dots="..." ;;
            esac
            if [[ -n "$model_tag" ]]; then
                printf '\r  %b%s\033[0m \033[1m%s%s\033[0m \033[2m(%s)\033[0m  ' "$clr" "$f" "$label" "$dots" "$model_tag" >&2
            else
                printf '\r  %b%s\033[0m \033[1m%s%s\033[0m  ' "$clr" "$f" "$label" "$dots" >&2
            fi
            ((i++))
            (( i % 4 == 0 )) && ((c++))
            sleep 0.12
        done
    ) &
    _ai_spin_pid=$!
}

_ai_spin_stop() {
    if [[ -n "$_ai_spin_pid" ]]; then
        kill "$_ai_spin_pid" 2>/dev/null
        wait "$_ai_spin_pid" 2>/dev/null
        _ai_spin_pid=""
        printf "\r\033[K" >&2  # clear the spinner line
    fi
}

# Cleanup spinner on exit/interrupt
trap '_ai_spin_stop' EXIT INT TERM

# ─── Claude API ───────────────────────────────────────────────────────────
# _claude_ask — call Claude API directly
# Usage: _claude_ask "your prompt" [model] [max_tokens] [spinner_label]
# Models: claude-sonnet-4-6, claude-opus-4-6, claude-haiku-4-5
_claude_ask() {
    local prompt="$1"
    local model="${2:-claude-sonnet-4-6}"
    local max_tokens="${3:-4096}"
    local spin_label="${4:-Thinking}"

    # Friendly model name for spinner
    local model_short
    case "$model" in
        *opus*)  model_short="opus" ;;
        *haiku*) model_short="haiku" ;;
        *)       model_short="sonnet" ;;
    esac

    # Start spinner
    _ai_spin_start "$spin_label" "$model_short"

    local json_body
    if command -v jq &>/dev/null; then
        json_body=$(jq -n \
            --arg model "$model" \
            --argjson max_tokens "$max_tokens" \
            --arg msg "$prompt" \
            '{model: $model, max_tokens: $max_tokens, messages: [{role: "user", content: $msg}]}')
    else
        json_body=$(cat <<ENDJSON
{
    "model": "$model",
    "max_tokens": $max_tokens,
    "messages": [{"role": "user", "content": $(echo "$prompt" | python3 -c 'import sys,json; print(json.dumps(sys.stdin.read()))')}]
}
ENDJSON
)
    fi

    local response
    response=$(curl -s --max-time 60 https://api.anthropic.com/v1/messages \
        -H "content-type: application/json" \
        -H "x-api-key: $ANTHROPIC_API_KEY" \
        -H "anthropic-version: 2023-06-01" \
        -d "$json_body")

    # Stop spinner
    _ai_spin_stop

    # Check for errors
    local error
    error=$(echo "$response" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("error",{}).get("message",""))' 2>/dev/null)
    if [[ -n "$error" ]]; then
        echo "API Error: $error" >&2
        return 1
    fi

    # Extract text
    echo "$response" | python3 -c 'import sys,json; d=json.load(sys.stdin); [print(b["text"]) for b in d.get("content",[]) if b.get("type")=="text"]' 2>/dev/null
}
