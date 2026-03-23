#!/bin/bash
# _platform.sh — cross-platform helpers (macOS + Linux)
# Source once: source "$SCRIPT_DIR/_platform.sh"
# Sets: KMAC_OS, KMAC_DISTRO, KMAC_PKG_MGR

[[ -n "${KMAC_PLATFORM_LOADED:-}" ]] && return
KMAC_PLATFORM_LOADED=1

KMAC_OS="unknown"
KMAC_DISTRO="unknown"
KMAC_PKG_MGR="unknown"

case "$(uname -s 2>/dev/null)" in
    Darwin)
        KMAC_OS="macos"
        KMAC_DISTRO="macos"
        KMAC_PKG_MGR="brew"
        ;;
    Linux)
        KMAC_OS="linux"
        if [[ -r /etc/os-release ]]; then
            # shellcheck source=/dev/null
            . /etc/os-release
            case "${ID:-}" in
                ubuntu|debian|pop|linuxmint|zorin|kali|raspbian)
                    KMAC_DISTRO="ubuntu"
                    KMAC_PKG_MGR="apt"
                    ;;
                fedora|rhel|centos|rocky|almalinux|ol)
                    KMAC_DISTRO="fedora"
                    KMAC_PKG_MGR="dnf"
                    ;;
                arch|manjaro|endeavouros)
                    KMAC_DISTRO="arch"
                    KMAC_PKG_MGR="pacman"
                    ;;
                *)
                    case " ${ID_LIKE:-} " in
                        *"debian"*|*"ubuntu"*)
                            KMAC_DISTRO="ubuntu"
                            KMAC_PKG_MGR="apt"
                            ;;
                        *"rhel"*|*"fedora"*|*"centos"*)
                            KMAC_DISTRO="fedora"
                            KMAC_PKG_MGR="dnf"
                            ;;
                        *"arch"*)
                            KMAC_DISTRO="arch"
                            KMAC_PKG_MGR="pacman"
                            ;;
                    esac
                    ;;
            esac
        fi
        if [[ "$KMAC_PKG_MGR" == unknown ]]; then
            command -v apt-get &>/dev/null && { KMAC_DISTRO="ubuntu"; KMAC_PKG_MGR="apt"; }
            command -v dnf &>/dev/null && { KMAC_DISTRO="fedora"; KMAC_PKG_MGR="dnf"; }
            command -v pacman &>/dev/null && { KMAC_DISTRO="arch"; KMAC_PKG_MGR="pacman"; }
        fi
        ;;
esac

# ─── Package install (single package name or pass-through args) ───────────

platform_install() {
    [[ $# -lt 1 ]] && return 1
    case "$KMAC_PKG_MGR" in
        brew)
            brew install "$@"
            ;;
        apt)
            if [[ "$(id -u)" -eq 0 ]]; then
                DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
            else
                sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "$@"
            fi
            ;;
        dnf)
            if [[ "$(id -u)" -eq 0 ]]; then
                dnf install -y "$@"
            else
                sudo dnf install -y "$@"
            fi
            ;;
        pacman)
            if [[ "$(id -u)" -eq 0 ]]; then
                pacman -S --noconfirm "$@"
            else
                sudo pacman -S --noconfirm "$@"
            fi
            ;;
        *)
            echo "platform_install: unknown package manager (KMAC_PKG_MGR=$KMAC_PKG_MGR)" >&2
            return 1
            ;;
    esac
}

# ─── Clipboard ───────────────────────────────────────────────────────────

platform_clipboard_copy() {
    if [[ "$KMAC_OS" == macos ]]; then
        pbcopy
    else
        if command -v xclip &>/dev/null; then
            xclip -selection clipboard
        elif command -v xsel &>/dev/null; then
            xsel --clipboard --input
        else
            echo "platform_clipboard_copy: need xclip or xsel" >&2
            return 1
        fi
    fi
}

platform_clipboard_paste() {
    if [[ "$KMAC_OS" == macos ]]; then
        pbpaste
    else
        if command -v xclip &>/dev/null; then
            xclip -selection clipboard -o
        elif command -v xsel &>/dev/null; then
            xsel --clipboard --output
        else
            echo "platform_clipboard_paste: need xclip or xsel" >&2
            return 1
        fi
    fi
}

# ─── Open URL / file ─────────────────────────────────────────────────────

platform_open() {
    if [[ "$KMAC_OS" == macos ]]; then
        open "$@"
    else
        if command -v xdg-open &>/dev/null; then
            xdg-open "$@" &>/dev/null &
        else
            echo "platform_open: xdg-open not found" >&2
            return 1
        fi
    fi
}

# ─── Desktop notification ──────────────────────────────────────────────────

platform_notify() {
    local title="${1:-KMac}"
    local message="${2:-}"
    if [[ "$KMAC_OS" == macos ]]; then
        osascript - "$title" "$message" <<'APPLESCRIPT' 2>/dev/null || true
on run argv
    display notification (item 2 of argv) with title (item 1 of argv)
end run
APPLESCRIPT
    else
        if command -v notify-send &>/dev/null; then
            notify-send "$title" "$message"
        else
            echo "[$title] $message" >&2
        fi
    fi
}

# ─── Keychain / libsecret (service = keychain -s value, e.g. kmac-anthropic) ─

platform_keychain_get() {
    local service="$1"
    if [[ "$KMAC_OS" == macos ]]; then
        security find-generic-password -s "$service" -w 2>/dev/null
    else
        if ! command -v secret-tool &>/dev/null; then
            return 1
        fi
        secret-tool lookup service "$service" account "$USER" 2>/dev/null
    fi
}

platform_keychain_set() {
    local service="$1"
    local value="$2"
    if [[ "$KMAC_OS" == macos ]]; then
        security add-generic-password -U -s "$service" -a "$USER" -w "$value" 2>/dev/null \
            || security add-generic-password -s "$service" -a "$USER" -w "$value" 2>/dev/null
    else
        if ! command -v secret-tool &>/dev/null; then
            echo "platform_keychain_set: secret-tool not found (install libsecret-tools)" >&2
            return 1
        fi
        printf '%s' "$value" | secret-tool store --label="kmac:${service}" service "$service" account "$USER" 2>/dev/null
    fi
}

platform_keychain_del() {
    local service="$1"
    if [[ "$KMAC_OS" == macos ]]; then
        security delete-generic-password -s "$service" 2>/dev/null
    else
        command -v secret-tool &>/dev/null || return 1
        secret-tool clear service "$service" account "$USER" 2>/dev/null
    fi
}

# ─── Network / files / sed ─────────────────────────────────────────────────

platform_local_ip() {
    if [[ "$KMAC_OS" == macos ]]; then
        ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true
    else
        hostname -I 2>/dev/null | awk '{print $1; exit}'
    fi
}

platform_file_age() {
    local f="$1"
    [[ -f "$f" ]] || { echo 0; return; }
    if [[ "$KMAC_OS" == macos ]]; then
        stat -f %m "$f" 2>/dev/null || echo 0
    else
        stat -c %Y "$f" 2>/dev/null || echo 0
    fi
}

# Usage: platform_sed_inplace [sed-args...] — last arg should be the file path
# For in-place editing: platform_sed_inplace 's/a/b/' file  OR  platform_sed_inplace -e 's/a/b/' -e 's/c/d/' file
platform_sed_inplace() {
    if [[ "$KMAC_OS" == macos ]]; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
}
