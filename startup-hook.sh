#!/bin/bash
# startup-hook.sh — Lightweight shell startup check
# Source this in .zshrc. Runs check in background, shows alert if updates exist.
# Does NOT slow down shell startup — everything async.

_kmac_startup_hook_dir=""
if [[ -n "${ZSH_VERSION:-}" ]]; then
    # shellcheck disable=SC2296
    _kmac_startup_hook_dir="$(cd "$(dirname "${(%):-%x}")" && pwd)"
elif [[ -n "${BASH_SOURCE[0]:-}" ]]; then
    _kmac_startup_hook_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
if [[ -n "$_kmac_startup_hook_dir" && -f "$_kmac_startup_hook_dir/scripts/_platform.sh" ]]; then
    # shellcheck source=/dev/null
    source "$_kmac_startup_hook_dir/scripts/_platform.sh"
fi
if ! type platform_file_age &>/dev/null; then
    platform_file_age() {
        [[ -f "${1:-}" ]] || { echo 0; return; }
        case "$(uname -s 2>/dev/null)" in
            Darwin) stat -f %m "$1" 2>/dev/null || echo 0 ;;
            Linux)  stat -c %Y "$1" 2>/dev/null || echo 0 ;;
            *)      echo 0 ;;
        esac
    }
fi

_toolkit_update_check() {
    local cache="/tmp/toolkit-update-cache/last-check.json"
    local cache_age_limit=14400  # 4 hours

    if [[ -f "$cache" && -s "$cache" ]]; then
        local age=$(( $(date +%s) - $(platform_file_age "$cache") ))
        if (( age < cache_age_limit )); then
            local count
            count=$(wc -l < "$cache" | tr -d ' ')
            if (( count > 0 )); then
                echo -e "\033[0;33m⚡ $count toolkit update(s) available — run 'toolkit update'\033[0m"
            fi
        fi
    fi

    # Resolve toolkit directory: env var → script location → iCloud → common paths
    local toolkit_dir=""
    if [[ -n "$KMAC_DIR" && -d "$KMAC_DIR" ]]; then
        toolkit_dir="$KMAC_DIR"
    elif [[ -n "${BASH_SOURCE[0]:-${(%):-%x}}" ]]; then
        local _hook_src="${BASH_SOURCE[0]:-${(%):-%x}}"
        [[ -f "$_hook_src" ]] && toolkit_dir="$(cd "$(dirname "$_hook_src")" && pwd)"
    fi
    if [[ -z "$toolkit_dir" || ! -f "$toolkit_dir/scripts/update-check" ]]; then
        local _icloud
        _icloud="$(echo ~/Library/CloudStorage/iCloudDrive*/com~apple~CloudDocs/Scripts/toolkit 2>/dev/null)"
        if [[ -d "$_icloud" ]]; then
            toolkit_dir="$_icloud"
        fi
    fi
    for _candidate in "$HOME/projects/KMAC-CLI" "$HOME/Projects/KMac-CLI" "$HOME/.kmac"; do
        [[ -n "$toolkit_dir" && -f "$toolkit_dir/scripts/update-check" ]] && break
        [[ -d "$_candidate" ]] && toolkit_dir="$_candidate"
    done

    # Refresh cache in background (silent, non-blocking)
    if [[ -f "$toolkit_dir/scripts/update-check" ]]; then
        ( bash "$toolkit_dir/scripts/update-check" --quick &>/dev/null ) &
        disown 2>/dev/null
    fi
}

# Only run if interactive shell and not inside toolkit already
if [[ $- == *i* && -z "$TOOLKIT_RUNNING" ]]; then
    _toolkit_update_check
fi
