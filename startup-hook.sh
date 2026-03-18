#!/bin/bash
# startup-hook.sh — Lightweight shell startup check
# Source this in .zshrc. Runs check in background, shows alert if updates exist.
# Does NOT slow down shell startup — everything async.

_toolkit_update_check() {
    local cache="/tmp/toolkit-update-cache/last-check.json"
    local cache_age_limit=14400  # 4 hours

    # If cache exists and is fresh, show alert from cache
    if [[ -f "$cache" && -s "$cache" ]]; then
        local age=$(( $(date +%s) - $(stat -f %m "$cache" 2>/dev/null || echo 0) ))
        if (( age < cache_age_limit )); then
            local count
            count=$(wc -l < "$cache" | tr -d ' ')
            if (( count > 0 )); then
                echo -e "\033[0;33m⚡ $count toolkit update(s) available — run 'toolkit update'\033[0m"
            fi
        fi
    fi

    # Refresh cache in background (silent, non-blocking)
    (
        local toolkit_dir
        toolkit_dir="$(echo ~/Library/CloudStorage/iCloudDrive*/com~apple~CloudDocs/Scripts/toolkit)"
        [[ -f "$toolkit_dir/scripts/update-check" ]] && bash "$toolkit_dir/scripts/update-check" --quick &>/dev/null
    ) &
    disown 2>/dev/null
}

# Only run if interactive shell and not inside toolkit already
if [[ $- == *i* && -z "$TOOLKIT_RUNNING" ]]; then
    _toolkit_update_check
fi
