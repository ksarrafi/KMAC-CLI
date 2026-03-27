#!/bin/bash
# _agent-hook.sh — Lightweight interface for any KMAC script to talk to the agent
#
# Source this to get:
#   agent_running        — check if daemon is up (return code)
#   agent_ask "question" — one-shot question, prints answer to stdout
#   agent_ask_quiet "q"  — one-shot, captures answer into $AGENT_REPLY
#   agent_remember "f"   — save a fact to agent memory
#   agent_task "desc"    — queue a background task
#   agent_diagnose "ctx" — ask agent to diagnose an error (pass context via stdin or arg)

_AGENT_SCRIPT_DIR="${_AGENT_SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
_AGENT_SOCK="${HOME}/.cache/kmac/agent/agent.sock"

_agent_engine() {
    PYTHONPATH="$_AGENT_SCRIPT_DIR" python3 -m _agent_engine "$@"
}

# Returns 0 if daemon is running, 1 otherwise
agent_running() {
    [[ -S "$_AGENT_SOCK" ]] && _agent_engine ping &>/dev/null
}

# Ensure daemon is running, start if needed
_agent_ensure() {
    agent_running && return 0
    bash "$_AGENT_SCRIPT_DIR/agent" start &>/dev/null
    sleep 1
    agent_running
}

# One-shot question — prints full answer to stdout
agent_ask() {
    local question="$*"
    [[ -z "$question" ]] && return 1
    _agent_ensure || { echo "Agent unavailable" >&2; return 1; }
    _agent_engine ask "$question" 2>/dev/null
}

# Quiet ask — captures answer into $AGENT_REPLY variable (no terminal output)
agent_ask_quiet() {
    local question="$*"
    [[ -z "$question" ]] && return 1
    _agent_ensure || return 1
    AGENT_REPLY=$(_agent_engine ask "$question" 2>/dev/null | \
        python3 -c "
import sys, json
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try:
        e = json.loads(line)
        if e.get('type') == 'text': print(e.get('content', ''), end='')
    except: print(line, end='')
" 2>/dev/null)
    export AGENT_REPLY
}

# Save a fact to agent memory
agent_remember() {
    local fact="$*"
    [[ -z "$fact" ]] && return 1
    _agent_ensure || return 1
    _agent_engine memory-add "$fact" &>/dev/null
}

# Queue a background task for the agent
agent_task() {
    local desc="$*"
    [[ -z "$desc" ]] && return 1
    _agent_ensure || return 1
    _agent_engine task-create "$desc"
}

# Ask agent to diagnose an error — pass context as argument or pipe via stdin
agent_diagnose() {
    local context="$*"
    if [[ -z "$context" ]] && [[ ! -t 0 ]]; then
        context=$(cat)
    fi
    [[ -z "$context" ]] && { echo "No context provided" >&2; return 1; }

    local prompt="Diagnose this error and suggest a fix. Be concise (2-3 sentences max):

$context"
    agent_ask "$prompt"
}
