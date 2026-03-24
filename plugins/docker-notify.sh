#!/bin/bash
# TOOLKIT_NAME: Docker Notify
# TOOLKIT_DESC: Alert when Docker containers crash or restart unexpectedly
# TOOLKIT_KEY: 4
# TOOLKIT_HOOKS: on-startup

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../scripts/_ui.sh
source "$SCRIPT_DIR/../scripts/_ui.sh"
# shellcheck source=../scripts/_platform.sh
[[ -z "${KMAC_PLATFORM_LOADED:-}" ]] && source "$SCRIPT_DIR/../scripts/_platform.sh"

docker_notify_check() {
    command -v docker &>/dev/null || return 0
    docker info &>/dev/null 2>&1 || return 0

    local unhealthy
    unhealthy=$(docker ps --filter "health=unhealthy" --format "{{.Names}}" 2>/dev/null)
    local restarting
    restarting=$(docker ps --filter "status=restarting" --format "{{.Names}}" 2>/dev/null)

    if [[ -n "$unhealthy" ]]; then
        ui_warn "Unhealthy containers:"
        while IFS= read -r name; do
            [[ -n "$name" ]] && echo "  - $name"
        done <<< "$unhealthy"
    fi

    if [[ -n "$restarting" ]]; then
        ui_warn "Restarting containers:"
        while IFS= read -r name; do
            [[ -n "$name" ]] && echo "  - $name"
        done <<< "$restarting"
    fi

    if [[ -z "$unhealthy" ]] && [[ -z "$restarting" ]]; then
        ui_success "All containers healthy"
    fi
}

case "${1:-}" in
    on-startup) docker_notify_check ;;
    check|"") docker_notify_check ;;
    help) echo "Usage: kmac docker-notify [check]" ;;
    *) echo "Unknown command: $1"; exit 1 ;;
esac
