#!/bin/bash
# toolkit.sh — portable macOS toolkit (KMac-CLI)
# Single-letter shortcuts, status dashboard, plugin system
# No set -e — each tool handles its own errors

# Resolve symlinks to find real toolkit directory
_src="${BASH_SOURCE[0]}"
while [[ -L "$_src" ]]; do
    _dir="$(cd "$(dirname "$_src")" && pwd)"
    _src="$(readlink "$_src")"
    [[ "$_src" != /* ]] && _src="$_dir/$_src"
done
TOOLKIT_DIR="$(cd "$(dirname "$_src")" && pwd)"
unset _src _dir
VERSION=$(cat "$TOOLKIT_DIR/VERSION" 2>/dev/null || echo "unknown")
export TOOLKIT_RUNNING=1

SCRIPTS_DIR="$TOOLKIT_DIR/scripts"
PLUGINS_DIR="$TOOLKIT_DIR/plugins"

# ─── Shared UI (colors, title_box, pause) ─────────────────────────────────
source "$SCRIPTS_DIR/_ui.sh"

# ─── AI Self-Healing ──────────────────────────────────────────────────────
source "$SCRIPTS_DIR/_ai-fix.sh" 2>/dev/null

# ─── Helpers ──────────────────────────────────────────────────────────────

tool_error() {
    echo -e "\n${RED}⚠  $1${NC}\n"
    echo -e "  ${GREEN}r)${NC} Retry    ${GREEN}f)${NC} AI Diagnose & Fix    ${GREEN}m)${NC} Back"
    echo ""
    read -r -n1 -p "  > " err_choice; echo ""
    case "$err_choice" in
        r|R) return 0 ;;
        f|F) ai_diagnose "$1" "${2:-toolkit operation}"; return $? ;;
        *)   return 1 ;;
    esac
}

si()       { [[ "$1" == "up" ]] && echo -e "${GREEN}*${NC}" || echo -e "${DIM}-${NC}"; }
si_plain() { [[ "$1" == "up" ]] && echo "*" || echo "-"; }

# safe_run — run a toolkit command live, offer AI fix on failure
# Captures output via tee on first run (never re-executes commands)
safe_run() {
    local label="$1"; shift
    local logfile="/tmp/toolkit-safe-run-$$.log"

    "$@" 2>&1 | tee "$logfile"
    local exit_code=${PIPESTATUS[0]}

    if (( exit_code != 0 )); then
        echo ""
        echo -e "${RED}⚠  $label failed (exit $exit_code)${NC}"
        echo -e "  ${GREEN}f)${NC} Ask AI to diagnose & fix    ${GREEN}r)${NC} Retry    ${GREEN}s)${NC} Skip"
        read -r -n1 -p "  > " fc; echo ""
        case "$fc" in
            f|F)
                local captured
                captured=$(cat "$logfile" 2>/dev/null)
                ai_diagnose "$captured" "$label"
                ;;
            r|R) safe_run "$label" "$@" ;;
        esac
    fi
    rm -f "$logfile"
}

# ─── Status Checks ───────────────────────────────────────────────────────

check_rt() {
    local pf="/tmp/remote-terminal/ttyd.pid"
    [[ -f "$pf" ]] && kill -0 "$(cat "$pf" 2>/dev/null)" 2>/dev/null && echo "up" || echo "down"
}
check_docker() {
    if timeout 2 docker info &>/dev/null 2>&1; then
        echo "up:$(docker ps -q 2>/dev/null | wc -l | tr -d ' ')"
    else echo "down:0"; fi
}
check_ngrok() {
    curl -sf --max-time 1 http://localhost:4040/api/tunnels &>/dev/null && echo "up" || echo "down"
}

# ─── Plugin Discovery ────────────────────────────────────────────────────

declare -a PLUGIN_NAMES=() PLUGIN_PATHS=() PLUGIN_DESCS=() PLUGIN_KEYS=()

_BUILTIN_KEYS="a v c s p e x k r d n q . b u ? / i B P + 0 S"

discover_plugins() {
    PLUGIN_NAMES=() PLUGIN_PATHS=() PLUGIN_DESCS=() PLUGIN_KEYS=()
    [[ -d "$PLUGINS_DIR" ]] || return
    local used_keys="$_BUILTIN_KEYS"
    for plugin in "$PLUGINS_DIR"/*; do
        [[ -x "$plugin" && -f "$plugin" ]] || continue
        local name desc key
        name=$(grep -m1 '^# TOOLKIT_NAME:' "$plugin" 2>/dev/null | sed 's/^# TOOLKIT_NAME: *//')
        desc=$(grep -m1 '^# TOOLKIT_DESC:' "$plugin" 2>/dev/null | sed 's/^# TOOLKIT_DESC: *//')
        key=$(grep -m1 '^# TOOLKIT_KEY:' "$plugin" 2>/dev/null | sed 's/^# TOOLKIT_KEY: *//')
        if [[ -n "$name" ]]; then
            if [[ -n "$key" && " $used_keys " == *" $key "* ]]; then
                echo -e "${YELLOW}Warning: plugin '${name}' key '$key' collides — skipping key${NC}" >&2
                key=""
            fi
            [[ -n "$key" ]] && used_keys+=" $key"
            PLUGIN_NAMES+=("$name")
            PLUGIN_PATHS+=("$plugin")
            PLUGIN_DESCS+=("${desc:-No description}")
            PLUGIN_KEYS+=("${key:-}")
        fi
    done
}

# ─── Animated Intro ──────────────────────────────────────────────────────
_INTRO_PLAYED=0

animate_intro() {
    (( _INTRO_PLAYED )) && return
    _INTRO_PLAYED=1

    local term_cols=$(tput cols 2>/dev/null || echo 80)
    local term_rows=$(tput lines 2>/dev/null || echo 24)
    (( term_cols < 50 || term_rows < 14 )) && return
    tput civis 2>/dev/null || return
    clear

    # 16-point elliptical orbit (1-based row, col for ANSI positioning)
    local -a rr=(7  5  3  2  2  2  3  5   7  9  11 12 12 12 11 9)
    local -a rc=(39 38 34 29 23 17 12 8   7  8  12 17 23 29 34 38)
    local np=16
    local text_c=12 skipped=0

    local frame
    for ((frame=0; frame<32; frame++)); do
        read -r -t 0.001 -n1 _ 2>/dev/null && { skipped=1; break; }

        local bright=$(( frame % np ))
        local p
        for ((p=0; p<np; p++)); do
            printf '\033[%d;%dH' "${rr[$p]}" "${rc[$p]}"
            local d=$(( (bright - p + np) % np ))
            if   (( d == 0 )); then printf '\033[38;5;49m\033[1m●\033[0m'
            elif (( d == 1 )); then printf '\033[38;5;45m●\033[0m'
            elif (( d == 2 )); then printf '\033[38;5;39m●\033[0m'
            elif (( d <= 4 )); then printf '\033[38;5;33m·\033[0m'
            else                    printf '\033[2m·\033[0m'
            fi
        done

        local pc
        case $(( frame % 6 )) in
            0) pc=33;; 1) pc=39;; 2) pc=45;; 3) pc=49;; 4) pc=45;; 5) pc=39;;
        esac
        printf '\033[6;%dH\033[38;5;%dm\033[1m █▄▀  █▀▄▀█  ▄▀█  █▀▀\033[0m' $text_c $pc
        printf '\033[7;%dH\033[38;5;%dm\033[1m █ █  █ ▀ █  █▀█  █▄▄\033[0m  \033[2mCLI\033[0m' $text_c $pc
        printf '\033[9;14H\033[2mportable macOS toolkit\033[0m'

        sleep 0.06
    done

    if (( skipped )); then
        tput cnorm 2>/dev/null; return
    fi

    sleep 0.3
    clear
    echo ""; echo ""

    printf "    \033[38;5;33m██╗  ██╗\033[0m \033[38;5;39m███╗   ███╗\033[0m  \033[38;5;45m█████╗\033[0m   \033[38;5;49m██████╗\033[0m\n"; sleep 0.07
    printf "    \033[38;5;33m██║ ██╔╝\033[0m \033[38;5;39m████╗ ████║\033[0m \033[38;5;45m██╔══██╗\033[0m \033[38;5;49m██╔════╝\033[0m\n"; sleep 0.07
    printf "    \033[38;5;33m█████╔╝\033[0m  \033[38;5;39m██╔████╔██║\033[0m \033[38;5;45m███████║\033[0m \033[38;5;49m██║\033[0m\n"; sleep 0.07
    printf "    \033[38;5;33m██╔═██╗\033[0m  \033[38;5;39m██║╚██╔╝██║\033[0m \033[38;5;45m██╔══██║\033[0m \033[38;5;49m██║\033[0m\n"; sleep 0.07
    printf "    \033[38;5;33m██║  ██╗\033[0m \033[38;5;39m██║ ╚═╝ ██║\033[0m \033[38;5;45m██║  ██║\033[0m \033[38;5;49m╚██████╗\033[0m\n"; sleep 0.07
    printf "    \033[38;5;33m╚═╝  ╚═╝\033[0m \033[38;5;39m╚═╝     ╚═╝\033[0m \033[38;5;45m╚═╝  ╚═╝\033[0m  \033[38;5;49m╚═════╝\033[0m\n"
    echo ""
    sleep 0.2
    printf "        \033[2mportable macOS toolkit\033[0m                       \033[2mv${VERSION}\033[0m\n"

    sleep 0.8
    tput cnorm 2>/dev/null
}

# ─── Banner & Menu ───────────────────────────────────────────────────────

print_logo() {
    echo ""
    echo -e "  ${C_BLUE}${BOLD} █▄▀${NC}  ${C_CYAN}${BOLD}█▀▄▀█${NC}  ${C_TEAL}${BOLD}▄▀█${NC}  ${C_GREEN}${BOLD}█▀▀${NC}"
    echo -e "  ${C_BLUE}${BOLD} █ █${NC}  ${C_CYAN}${BOLD}█ ▀ █${NC}  ${C_TEAL}${BOLD}█▀█${NC}  ${C_GREEN}${BOLD}█▄▄${NC}  ${DIM}CLI${NC}"
    echo ""
    echo -e "  ${DIM}  portable macOS toolkit${NC}                  ${DIM}v${VERSION}${NC}"
}

print_menu() {
    clear
    discover_plugins

    local rt=$(check_rt) dk=$(check_docker) ng=$(check_ngrok)
    local dk_state="${dk%%:*}" dk_count="${dk##*:}"

    # ─── Logo ───
    print_logo

    # ─── Status Bar ───
    local _box_w=52
    echo ""
    echo -e "  ${DIM}┌ services ──────────────────────────────────────────┐${NC}"

    local _plain="  $(si_plain "$rt") Remote Terminal   $(si_plain "$dk_state") Docker (${dk_count})   $(si_plain "$ng") ngrok"
    local _pad=$(( _box_w - ${#_plain} ))
    (( _pad < 1 )) && _pad=1
    local _sp; printf -v _sp '%*s' "$_pad" ''
    printf "  ${DIM}│${NC}  $(si "$rt") Remote Terminal   $(si "$dk_state") Docker ${DIM}(${dk_count})${NC}   $(si "$ng") ngrok${_sp}${DIM}│${NC}\n"

    local _cache="/tmp/toolkit-update-cache/last-check.json"
    if [[ -s "$_cache" ]]; then
        local _ucount
        _ucount=$(wc -l < "$_cache" 2>/dev/null | tr -d ' ')
        if (( _ucount > 0 )); then
            local _up_plain="  >> ${_ucount} update(s) available -- press u for details"
            local _up_pad=$(( _box_w - ${#_up_plain} ))
            (( _up_pad < 1 )) && _up_pad=1
            local _up_sp; printf -v _up_sp '%*s' "$_up_pad" ''
            echo -e "  ${DIM}│${NC}  ${YELLOW}>>${NC} ${_ucount} update(s) available ${DIM}--${NC} press ${BOLD}u${NC} for details${_up_sp}${DIM}│${NC}"
        fi
    fi
    echo -e "  ${DIM}└────────────────────────────────────────────────────┘${NC}"

    # ─── Commands ───
    echo ""
    echo -e "   ${BOLD}${C_CYAN}  AI${NC}                       ${BOLD}${C_TEAL}  Dev${NC}                      ${BOLD}${C_GREEN}  Infra${NC}"
    echo -e "   ${DIM}────${NC}                       ${DIM}─────${NC}                      ${DIM}──────${NC}"
    echo -e "   ${GREEN}a${NC}  Ask Claude              ${GREEN}p${NC}  Project Launcher        ${GREEN}r${NC}  Remote Terminal"
    echo -e "   ${GREEN}v${NC}  AI Code Review          ${GREEN}e${NC}  Claude Code             ${GREEN}d${NC}  Docker Manager"
    echo -e "   ${GREEN}c${NC}  AI Commit               ${GREEN}x${NC}  Cursor Agent            ${GREEN}n${NC}  Network Info"
    echo -e "   ${GREEN}+${NC}  ${BOLD}Build a Tool${NC}            ${GREEN}s${NC}  Sessions                ${GREEN}k${NC}  Kill Port"
    echo -e "                               ${GREEN}P${NC}  ${C_MINT}${BOLD}Pilot${NC} ${DIM}(remote agent)${NC}"
    echo ""
    echo -e "   ${BOLD}${YELLOW}  System${NC}"
    echo -e "   ${DIM}────────${NC}"
    echo -e "   ${GREEN}S${NC}  ${BOLD}Storage Manager${NC}         ${GREEN}b${NC}  Backup Dotfiles         ${GREEN}u${NC}  Check Updates"
    echo -e "   ${GREEN}.${NC}  Secrets (Keychain)      ${GREEN}/${NC}  Show Aliases            ${GREEN}i${NC}  Install/Update"
    echo -e "   ${GREEN}?${NC}  Health Check            ${GREEN}q${NC}  Connection QR           ${GREEN}B${NC}  Bootstrap Mac"

    # ─── Plugins ───
    if (( ${#PLUGIN_NAMES[@]} > 0 )); then
        echo ""
        echo -e "   ${BOLD}${MAGENTA}  Plugins${NC}"
        echo -e "   ${DIM}─────────${NC}"
        for idx in "${!PLUGIN_NAMES[@]}"; do
            local pkey="${PLUGIN_KEYS[$idx]:-$((idx+1))}"
            printf "   ${GREEN}${pkey}${NC}  %-22s ${DIM}%s${NC}\n" "${PLUGIN_NAMES[$idx]}" "${PLUGIN_DESCS[$idx]}"
        done
    fi

    # ─── Footer ───
    echo ""
    echo -e "  ${DIM}─────────────────────────────────────────────────────${NC}"
    echo -e "   ${DIM}0  Exit${NC}"
    echo ""
}

# ─── Tool Functions ───────────────────────────────────────────────────────

do_docker() {
    bash "$SCRIPTS_DIR/docker" || { tool_error "Docker Manager error"; }
}

do_remote_terminal() {
    source "$SCRIPTS_DIR/remote-terminal.sh" 2>/dev/null
    local status=$(check_rt)
    title_box "Remote Terminal" "🖥"
    if [[ "$status" == "up" ]]; then
        local url
        url=$(curl -sf http://localhost:4040/api/tunnels 2>/dev/null \
            | grep -o '"public_url":"[^"]*"' | head -1 | cut -d'"' -f4)
        echo -e "  Status: ${GREEN}● Running${NC}"
        echo -e "  URL:    ${GREEN}${url:-unknown}${NC}"
        local _rt_pass
        _rt_pass=$(security find-generic-password -s "toolkit-rt-password" -w 2>/dev/null || echo "(stored in Keychain)")
        echo -e "  Auth:   user / ${_rt_pass}"
        echo ""
        echo -e "  ${GREEN}q${NC}) Show QR code"
        echo -e "  ${GREEN}r${NC}) Restart"
        echo -e "  ${GREEN}s${NC}) Stop"
        echo -e "  ${GREEN}t${NC}) Re-attach tmux (reconnect only)"
        echo -e "  ${GREEN}m${NC}) Back"
        echo ""
        read -r -n1 -p "  > " rt_ch; echo ""
        case "$rt_ch" in
            q|Q)
                [[ -n "$url" ]] && qrencode -t UTF8 "$url" 2>/dev/null || echo "No URL available"
                ;;
            r|R) stop-remote-terminal; echo ""; remote-terminal ;;
            s|S) stop-remote-terminal ;;
            t|T)
                echo "Re-attaching to tmux session 'remote'..."
                tmux attach -t remote 2>/dev/null || echo "No tmux session found."
                ;;
        esac
    else
        echo -e "  Status: ${DIM}○ Stopped${NC}"
        echo ""
        echo -e "  ${GREEN}s${NC}) Start    ${GREEN}m${NC}) Back"
        echo ""
        read -r -n1 -p "  > " rt_ch; echo ""
        case "$rt_ch" in
            s|S) remote-terminal || tool_error "Failed to start Remote Terminal" ;;
        esac
    fi
    pause
}

do_show_qr() {
    if [[ "$(check_rt)" != "up" ]]; then
        echo -e "${YELLOW}Remote Terminal is not running. Start it first [r].${NC}"
        pause; return
    fi
    local url
    url=$(curl -sf http://localhost:4040/api/tunnels 2>/dev/null \
        | grep -o '"public_url":"[^"]*"' | head -1 | cut -d'"' -f4)
    title_box "Remote Terminal — QR" "📡"
    echo -e "  URL:      ${GREEN}${url:-unknown}${NC}"
    echo -e "  Username: ${GREEN}user${NC}"
    local _rt_pass
    _rt_pass=$(security find-generic-password -s "toolkit-rt-password" -w 2>/dev/null || echo "(stored in Keychain)")
    echo -e "  Password: ${GREEN}${_rt_pass}${NC}"
    echo ""
    [[ -n "$url" ]] && qrencode -t UTF8 "$url" 2>/dev/null
    pause
}

do_ask() {
    title_box "Ask Claude" "🤖"
    echo -e "  ${DIM}(-m opus for hard questions, Ctrl+D when done)${NC}"
    echo ""
    read -r -p "Question: " q
    [[ -z "$q" ]] && return
    echo ""
    bash "$SCRIPTS_DIR/ask" "$q"
    pause
}

do_network() {
    title_box "Network Info" "🌐"
    local lip=$(ipconfig getifaddr en0 2>/dev/null || echo "Not connected")
    local pip=$(curl -sf --max-time 3 https://ifconfig.me 2>/dev/null || echo "Unavailable")
    local wifi=$(/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -I 2>/dev/null | awk '/ SSID/ {print $NF}')
    local gw=$(netstat -rn 2>/dev/null | awk '/default.*en0/ {print $2; exit}')
    echo -e "  Local IP:   $lip"
    echo -e "  Public IP:  $pip"
    echo -e "  Wi-Fi:      ${wifi:-Unknown}"
    echo -e "  Gateway:    ${gw:-Unknown}"
    echo ""
    echo -e "  ${BOLD}Listening Ports:${NC}"
    lsof -iTCP -sTCP:LISTEN -P -n 2>/dev/null | awk 'NR>1 {printf "    %-15s %-8s %s\n", $1, $2, $9}' | sort -u | head -12
    echo ""
    echo -e "  ${DIM}Tip: 'networkQuality' for speed test${NC}"
    pause
}

do_health() {
    title_box "Health Check" "🩺"
    local issues=0
    echo -e "  ${BOLD}Dependencies:${NC}"
    for dep in ttyd ngrok caddy qrencode tmux bat fzf git docker brew claude cursor; do
        if command -v "$dep" &>/dev/null; then
            local ver=$("$dep" --version 2>/dev/null | head -1 | tr -d '\n')
            echo -e "    ${GREEN}✓${NC} $dep  ${DIM}${ver:0:40}${NC}"
        else
            echo -e "    ${RED}✗${NC} $dep"; ((issues++))
        fi
    done
    echo ""
    echo -e "  ${BOLD}Environment:${NC}"
    [[ -n "${ANTHROPIC_API_KEY:-}" && "$ANTHROPIC_API_KEY" != "your-api-key-here" ]] \
        && echo -e "    ${GREEN}✓${NC} ANTHROPIC_API_KEY" || echo -e "    ${YELLOW}!${NC} ANTHROPIC_API_KEY not set"
    security find-generic-password -s "toolkit-anthropic" &>/dev/null 2>&1 \
        && echo -e "    ${GREEN}✓${NC} Keychain: toolkit-anthropic" || echo -e "    ${DIM}○${NC} Keychain: not stored (use '.' to set up)"
    echo ""
    echo -e "  ${BOLD}Paths:${NC}"
    [[ -d "$TOOLKIT_DIR" ]] && echo -e "    ${GREEN}✓${NC} Toolkit dir" || { echo -e "    ${RED}✗${NC} Toolkit dir missing"; ((issues++)); }
    [[ -d "$SCRIPTS_DIR" ]] && echo -e "    ${GREEN}✓${NC} Scripts ($(ls "$SCRIPTS_DIR" | wc -l | tr -d ' '))" || { echo -e "    ${RED}✗${NC} Scripts missing"; ((issues++)); }
    [[ -d "$PLUGINS_DIR" ]] && echo -e "    ${GREEN}✓${NC} Plugins ($(ls "$PLUGINS_DIR" 2>/dev/null | wc -l | tr -d ' '))" || echo -e "    ${DIM}○${NC} No plugins dir"
    grep -q "alias toolkit=" ~/.zshrc 2>/dev/null \
        && echo -e "    ${GREEN}✓${NC} .zshrc integrated" || { echo -e "    ${RED}✗${NC} .zshrc missing toolkit"; ((issues++)); }
    echo ""
    (( issues == 0 )) && echo -e "  ${GREEN}${BOLD}All clear!${NC}" || echo -e "  ${YELLOW}${BOLD}$issues issue(s) found.${NC}"
    pause
}

do_aliases() {
    clear
    title_box "Aliases" "📋"
    if [[ -f "$TOOLKIT_DIR/aliases.sh" ]]; then
        grep "^alias\|^[a-z_]*() " "$TOOLKIT_DIR/aliases.sh" | while IFS= read -r line; do
            if [[ "$line" == alias* ]]; then
                local name="${line#alias }" key="${name%%=*}" val="${name#*=}"
                val="${val//\"/}"; val="${val//\'/}"
                echo -e "  ${GREEN}${key}${NC}  →  ${val}"
            else
                local fn="${line%%(*}"
                echo -e "  ${GREEN}${fn}${NC}  →  ${DIM}(function)${NC}"
            fi
        done
    fi
    pause
}

do_secrets() {
    title_box "Secrets (macOS Keychain)" "🔐"
    local secrets=("toolkit-openai:OPENAI_API_KEY" "toolkit-anthropic:ANTHROPIC_API_KEY" "toolkit-ngrok:NGROK_AUTHTOKEN" "toolkit-rt-password:RT_PASSWORD")
    for entry in "${secrets[@]}"; do
        local svc="${entry%%:*}" envvar="${entry##*:}"
        security find-generic-password -s "$svc" -w &>/dev/null \
            && echo -e "  ${GREEN}✓${NC} $envvar" || echo -e "  ${RED}✗${NC} $envvar"
    done
    echo -e "\n  ${GREEN}a${NC}) Add/update    ${GREEN}l${NC}) Load into shell    ${GREEN}m${NC}) Back\n"
    read -r -n1 -p "  > " sc; echo ""
    case "$sc" in
        a|A)
            echo -e "\n  1) OPENAI_API_KEY  2) ANTHROPIC_API_KEY  3) NGROK_AUTHTOKEN  4) RT_PASSWORD\n"
            read -r -p "Which [1-4]: " kc
            local sn=""
            case "$kc" in 1) sn="toolkit-openai";; 2) sn="toolkit-anthropic";; 3) sn="toolkit-ngrok";; 4) sn="toolkit-rt-password";; *) return;; esac
            read -r -s -p "Paste key (hidden): " nk; echo ""
            [[ -n "$nk" ]] && {
                security add-generic-password -U -s "$sn" -a "$USER" -w "$nk" 2>/dev/null \
                    || security add-generic-password -s "$sn" -a "$USER" -w "$nk"
                echo -e "${GREEN}✓ Saved${NC}"
            }
            ;;
        l|L)
            for entry in "${secrets[@]}"; do
                local svc="${entry%%:*}" envvar="${entry##*:}"
                local val=$(security find-generic-password -s "$svc" -w 2>/dev/null)
                [[ -n "$val" ]] && { export "$envvar=$val"; echo -e "  ${GREEN}✓${NC} $envvar loaded"; }
            done
            echo -e "${DIM}Loaded for this session only.${NC}"
            ;;
    esac
    pause
}

do_bootstrap() {
    echo -e "${BOLD}${CYAN}Bootstrap New Mac${NC}\n"
    echo -e "  ${GREEN}1${NC}) Export Brewfile (save current)    ${GREEN}3${NC}) Apply macOS prefs"
    echo -e "  ${GREEN}2${NC}) Install from Brewfile             ${GREEN}4${NC}) Full bootstrap (all)"
    echo -e "  ${GREEN}m${NC}) Back\n"
    read -r -n1 -p "  > " bc; echo ""
    case "$bc" in
        1)  brew bundle dump --file="$TOOLKIT_DIR/Brewfile" --force 2>/dev/null
            echo -e "${GREEN}✓ Brewfile saved${NC}" ;;
        2)  [[ -f "$TOOLKIT_DIR/Brewfile" ]] && brew bundle --file="$TOOLKIT_DIR/Brewfile" || echo "No Brewfile found" ;;
        3)  defaults write com.apple.dock autohide -bool true
            defaults write com.apple.dock tilesize -int 48
            defaults write NSGlobalDomain AppleShowAllExtensions -bool true
            defaults write com.apple.finder ShowPathbar -bool true
            defaults write com.apple.finder ShowStatusBar -bool true
            defaults write NSGlobalDomain KeyRepeat -int 2
            defaults write NSGlobalDomain InitialKeyRepeat -int 15
            mkdir -p ~/Screenshots
            defaults write com.apple.screencapture location ~/Screenshots
            killall Dock Finder 2>/dev/null || true
            echo -e "${GREEN}✓ Preferences applied${NC}" ;;
        4)  [[ -f "$TOOLKIT_DIR/Brewfile" ]] && brew bundle --file="$TOOLKIT_DIR/Brewfile"
            defaults write com.apple.dock autohide -bool true; defaults write com.apple.dock tilesize -int 48
            defaults write NSGlobalDomain AppleShowAllExtensions -bool true; defaults write NSGlobalDomain KeyRepeat -int 2
            mkdir -p ~/Screenshots; defaults write com.apple.screencapture location ~/Screenshots
            killall Dock Finder 2>/dev/null || true
            bash "$TOOLKIT_DIR/install.sh"
            echo -e "${GREEN}✓ Full bootstrap complete${NC}" ;;
    esac
    pause
}

# ─── Main Loop ────────────────────────────────────────────────────────────

main() {
    mkdir -p "$PLUGINS_DIR" 2>/dev/null
    animate_intro
    while true; do
        print_menu
        read -r -n1 -p "  > " choice; echo ""
        case "$choice" in
            # AI
            a) clear; do_ask ;;
            v) clear; safe_run "AI Code Review" bash "$SCRIPTS_DIR/review"; pause ;;
            c) clear; safe_run "AI Commit" bash "$SCRIPTS_DIR/aicommit"; pause ;;
            s) clear; bash "$SCRIPTS_DIR/sessions" ;;
            # Dev
            p) clear; safe_run "Project Launcher" bash "$SCRIPTS_DIR/project" ;;
            e) clear; bash "$SCRIPTS_DIR/claudeme" ;;
            x) clear; echo -e "${BOLD}Cursor Agent Task:${NC}"; read -r -p "Task: " t; safe_run "Cursor Agent" bash "$SCRIPTS_DIR/cursoragent" "$t" ;;
            k) clear; echo -e "${BOLD}Kill Port:${NC}"; read -r -p "Port (blank=list): " pt; safe_run "Kill Port" bash "$SCRIPTS_DIR/killport" $pt; pause ;;
            P) clear; bash "$SCRIPTS_DIR/pilot" status; pause ;;
            # Infra
            r) clear; do_remote_terminal ;;
            d) clear; do_docker ;;
            n) clear; do_network ;;
            q) clear; do_show_qr ;;
            # System
            .) clear; do_secrets ;;
            b) clear; safe_run "Dotfile Backup" bash "$SCRIPTS_DIR/dotbackup"; pause ;;
            u) clear; safe_run "Update Check" bash "$SCRIPTS_DIR/update-check"; pause ;;
            \?) clear; do_health ;;
            /) clear; do_aliases ;;
            i) clear; safe_run "Install/Update Toolkit" bash "$TOOLKIT_DIR/install.sh"; pause ;;
            B) clear; do_bootstrap ;;
            S) clear; bash "$SCRIPTS_DIR/storage"; pause ;;
            +) clear; bash "$SCRIPTS_DIR/toolmaker"; pause ;;
            0) echo -e "\n  ${C_TEAL}See you! ✌${NC}\n"; exit 0 ;;
            *)
                # Check plugins
                local matched=false
                for idx in "${!PLUGIN_KEYS[@]}"; do
                    if [[ "$choice" == "${PLUGIN_KEYS[$idx]}" ]]; then
                        clear; bash "${PLUGIN_PATHS[$idx]}"; pause; matched=true; break
                    fi
                done
                $matched || { echo -e "${RED}Unknown: '$choice'${NC}"; sleep 0.5; }
                ;;
        esac
    done
}

# ─── Subcommand Router ────────────────────────────────────────────────────

if [[ $# -gt 0 ]]; then
    subcmd="$1"; shift
    case "$subcmd" in
        ask)        exec bash "$SCRIPTS_DIR/ask" "$@" ;;
        review)     exec bash "$SCRIPTS_DIR/review" "$@" ;;
        aicommit)   exec bash "$SCRIPTS_DIR/aicommit" "$@" ;;
        sessions)   exec bash "$SCRIPTS_DIR/sessions" "$@" ;;
        project)    exec bash "$SCRIPTS_DIR/project" "$@" ;;
        cask|cursoragent) exec bash "$SCRIPTS_DIR/cursoragent" "$@" ;;
        killport)   exec bash "$SCRIPTS_DIR/killport" "$@" ;;
        pilot)      exec bash "$SCRIPTS_DIR/pilot" "$@" ;;
        dotbackup)  exec bash "$SCRIPTS_DIR/dotbackup" "$@" ;;
        update)     exec bash "$SCRIPTS_DIR/update-check" "$@" ;;
        doctor)     do_health ;;
        storage)    exec bash "$SCRIPTS_DIR/storage" "$@" ;;
        docker)     exec bash "$SCRIPTS_DIR/docker" "$@" ;;
        make|build|toolmaker) exec bash "$SCRIPTS_DIR/toolmaker" "$@" ;;
        version|-v|--version)
            print_logo
            echo ""
            echo -e "  ${DIM}Installed: ${TOOLKIT_DIR}${NC}"
            echo -e "  ${DIM}Scripts: $(ls "$SCRIPTS_DIR" 2>/dev/null | wc -l | tr -d ' ')  Plugins: $(ls "$PLUGINS_DIR" 2>/dev/null | wc -l | tr -d ' ')${NC}"
            ;;
        whatsnew|--whatsnew|changelog)
            echo -e "${BOLD}${CYAN}What's New — v${VERSION}${NC}"
            echo ""
            # Show only the latest version section from CHANGELOG.md
            if [[ -f "$TOOLKIT_DIR/CHANGELOG.md" ]]; then
                awk '/^## /{if(found) exit; found=1} found' "$TOOLKIT_DIR/CHANGELOG.md" | sed 's/^/  /'
            else
                echo "  No changelog found."
            fi
            ;;
        help|-h|--help)
            print_logo
            echo ""
            echo "Usage: toolkit [command] [args...]"
            echo ""
            echo -e "  ${BOLD}AI${NC}"
            echo "    ask \"question\"        Ask Claude (or -i for interactive, -m opus)"
            echo "    review [--strict]     AI code review (--quick, --staged)"
            echo "    aicommit [--amend]    AI commit message with scope detection"
            echo "    sessions              Resume a Claude session"
            echo ""
            echo -e "  ${BOLD}Dev${NC}"
            echo "    project               Project launcher with fzf"
            echo "    cursoragent \"task\"     Cursor Agent task (alias: cask)"
            echo "    pilot <cmd>           Remote AI agent via Telegram (start/stop/status)"
            echo "    killport [port]       Kill process on port (blank = list all)"
            echo ""
            echo -e "  ${BOLD}System${NC}"
            echo "    storage [cmd]         Disk usage analyzer + iCloud migration"
            echo "    dotbackup [cmd]       Backup/restore/diff/hook dotfiles"
            echo "    update                Check for updates"
            echo "    doctor                Health check"
            echo "    make \"description\"    Build a new tool with AI"
            echo ""
            echo -e "  ${BOLD}Meta${NC}"
            echo "    help, -h              Show this help"
            echo "    version, -v           Show version info"
            echo "    whatsnew              Show latest changelog"
            echo ""
            echo -e "${DIM}Run 'toolkit' or 'kmac' with no args for the interactive menu.${NC}"
            ;;
        *)
            if [[ -x "$PLUGINS_DIR/$subcmd" || -x "$PLUGINS_DIR/${subcmd}.sh" ]]; then
                local p="$PLUGINS_DIR/$subcmd"
                [[ -x "$p" ]] || p="${p}.sh"
                exec bash "$p" "$@"
            fi
            echo "Unknown: $subcmd — try 'toolkit help'"
            exit 1 ;;
    esac
else
    main
fi
