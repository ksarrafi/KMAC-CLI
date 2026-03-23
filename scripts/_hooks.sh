#!/bin/bash
# _hooks.sh — Plugin API v2 lifecycle hooks (sourceable, bash 3.2+)
#
# Available hooks:
#   pre-commit    — runs before aicommit creates a commit
#   post-commit   — runs after a commit succeeds
#   pre-deploy    — runs before a deployment action
#   post-deploy   — runs after deployment completes
#   on-error      — runs when any toolkit command fails (error info via env vars)
#   on-startup    — runs when toolkit interactive menu starts
#   on-exit       — runs when toolkit exits
#   pre-review    — runs before AI code review
#   post-review   — runs after code review completes
#   session-start — runs when a new agent session begins
#   session-end   — runs when an agent session ends

# Registry entries: "hook_name|kind|payload"
# kind: fn (bash function), path (user script), plugin (auto-registered plugin script)
declare -a _KMAC_HOOK_REGISTRY=()

_KMAC_KNOWN_HOOKS="pre-commit post-commit pre-deploy post-deploy on-error on-startup on-exit pre-review post-review session-start session-end"

_hooks_warn() {
    if [[ -n "${YELLOW:-}" && -n "${NC:-}" ]]; then
        echo -e "${YELLOW}⚠  hook: $*${NC}" >&2
    else
        echo "⚠  hook: $*" >&2
    fi
}

_hooks_valid_hook() {
    local h="$1"
    local k
    for k in $_KMAC_KNOWN_HOOKS; do
        [[ "$k" == "$h" ]] && return 0
    done
    return 1
}

# Remove all plugin-sourced handlers (for rediscovery on each menu refresh)
hooks_clear_plugin_handlers() {
    local -a kept=()
    local entry
    for entry in "${_KMAC_HOOK_REGISTRY[@]}"; do
        case "$entry" in
            *"|plugin|"*) ;;
            *) kept+=("$entry") ;;
        esac
    done
    _KMAC_HOOK_REGISTRY=("${kept[@]}")
}

# Internal: register a plugin script for a hook (absolute path to script)
hooks_register_plugin() {
    local hook="$1" script="$2"
    [[ -n "$hook" && -n "$script" ]] || return 0
    if ! _hooks_valid_hook "$hook"; then
        _hooks_warn "unknown hook '$hook' — skipping plugin registration for $(basename "$script")"
        return 0
    fi
    _KMAC_HOOK_REGISTRY+=( "${hook}|plugin|${script}" )
}

# hooks_register <hook_name> <callback_function_or_script>
hooks_register() {
    local hook="$1" handler="$2"
    if [[ -z "$hook" || -z "$handler" ]]; then
        _hooks_warn "hooks_register: missing hook or handler"
        return 1
    fi
    if ! _hooks_valid_hook "$hook"; then
        _hooks_warn "unknown hook '$hook' — registering anyway"
    fi
    if declare -f "$handler" &>/dev/null; then
        _KMAC_HOOK_REGISTRY+=( "${hook}|fn|${handler}" )
    elif [[ -f "$handler" ]]; then
        _KMAC_HOOK_REGISTRY+=( "${hook}|path|${handler}" )
    else
        _hooks_warn "hooks_register: not a function or file: $handler"
        return 1
    fi
}

# hooks_emit <hook_name> [args...]
hooks_emit() {
    local hook="$1"
    shift
    local cwd
    cwd="$(pwd)"
    export KMAC_HOOK="$hook"
    export KMAC_HOOK_ARGS="$*"
    export KMAC_PROJECT_DIR="$cwd"

    local entry h kind payload rc rest
    for entry in "${_KMAC_HOOK_REGISTRY[@]}"; do
        h="${entry%%|*}"
        [[ "$h" == "$hook" ]] || continue
        rest="${entry#*|}"
        kind="${rest%%|*}"
        payload="${rest#*|}"

        rc=0
        case "$kind" in
            fn)
                "$payload" "$hook" "$@" || rc=$?
                ;;
            path|plugin)
                if [[ -f "$payload" ]]; then
                    bash "$payload" "$hook" "$@" || rc=$?
                else
                    _hooks_warn "missing script for hook '$hook': $payload"
                    rc=1
                fi
                ;;
            *)
                _hooks_warn "bad registry entry for '$hook'"
                rc=1
                ;;
        esac
        if (( rc != 0 )); then
            _hooks_warn "handler failed (exit $rc) for hook '$hook': $payload"
        fi
    done
}

# hooks_list — show all registered hooks and their handlers
hooks_list() {
    local entry h kind payload rest
    if (( ${#_KMAC_HOOK_REGISTRY[@]} == 0 )); then
        echo "  (no hook handlers registered)"
        return 0
    fi
    for entry in "${_KMAC_HOOK_REGISTRY[@]}"; do
        h="${entry%%|*}"
        rest="${entry#*|}"
        kind="${rest%%|*}"
        payload="${rest#*|}"
        echo "  $h  [$kind]  $payload"
    done
}

# hooks_clear <hook_name> — remove all handlers for a hook
hooks_clear() {
    local hook="$1"
    if [[ -z "$hook" ]]; then
        _hooks_warn "hooks_clear: missing hook name"
        return 1
    fi
    local -a kept=()
    local entry h
    for entry in "${_KMAC_HOOK_REGISTRY[@]}"; do
        h="${entry%%|*}"
        [[ "$h" == "$hook" ]] && continue
        kept+=("$entry")
    done
    _KMAC_HOOK_REGISTRY=("${kept[@]}")
}
