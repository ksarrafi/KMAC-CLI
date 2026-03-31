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
export TOOLKIT_RUNNING=1

SCRIPTS_DIR="$TOOLKIT_DIR/scripts"
PLUGINS_DIR="$TOOLKIT_DIR/plugins"
KMAC_CACHE_DIR="${HOME}/.cache/kmac"
[[ -d "$KMAC_CACHE_DIR" ]] || mkdir -p "$KMAC_CACHE_DIR"
chmod 700 "$KMAC_CACHE_DIR" 2>/dev/null

# Version: cached to avoid git-describe on every launch (re-checks hourly)
_ver_cache="$KMAC_CACHE_DIR/.version"
_ver_mtime=$(stat -f %m "$_ver_cache" 2>/dev/null || stat -c %Y "$_ver_cache" 2>/dev/null || echo 0)
if [[ -f "$_ver_cache" ]] && (( $(date +%s) - _ver_mtime < 3600 )); then
    VERSION=$(<"$_ver_cache")
else
    VERSION=$(git -C "$TOOLKIT_DIR" describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')
    [[ -z "$VERSION" ]] && VERSION=$(cat "$TOOLKIT_DIR/VERSION" 2>/dev/null || echo "unknown")
    printf '%s' "$VERSION" > "$_ver_cache" 2>/dev/null
fi
unset _ver_cache _ver_mtime

# ─── Shared UI (colors, title_box, pause) ─────────────────────────────────
# shellcheck source=scripts/_ui.sh
source "$SCRIPTS_DIR/_ui.sh"

# ─── Vault (secret management) ───────────────────────────────────────────
# shellcheck source=scripts/_vault.sh
source "$SCRIPTS_DIR/_vault.sh" 2>/dev/null

# Registry-backed secrets are exported lazily in main() so sourcing this file
# for one-shot subcommands (e.g. kmac review) does not unlock/export everything at startup.

# ─── AI Self-Healing ──────────────────────────────────────────────────────
# shellcheck source=scripts/_ai-fix.sh
source "$SCRIPTS_DIR/_ai-fix.sh" 2>/dev/null

# ─── Plugin hooks (API v2) ────────────────────────────────────────────────
# shellcheck source=scripts/_hooks.sh
source "$SCRIPTS_DIR/_hooks.sh"

# ─── Helpers ──────────────────────────────────────────────────────────────

tool_error() {
    hooks_emit on-error "$1" || true
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
    local logfile
    logfile="$(mktemp "$KMAC_CACHE_DIR/safe-run.XXXXXX")" || return 1
    chmod 600 "$logfile"

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
                echo -e "${YELLOW}Log may contain sensitive data. Send to AI for diagnosis?${NC}"
                read -r -n1 -p "(y/N) " _confirm; echo ""
                [[ "$_confirm" == [yY] ]] || { rm -f "$logfile"; return "$exit_code"; }
                ai_diagnose "$captured" "$label"
                ;;
            r|R) safe_run "$label" "$@" ;;
        esac
    fi
    rm -f "$logfile"
}

# ─── Status Checks ───────────────────────────────────────────────────────

check_rt() {
    local pf="$HOME/.config/kmac/remote-terminal/ttyd.pid"
    local _pid; _pid=""; [[ -f "$pf" ]] && read -r _pid < "$pf" 2>/dev/null; [[ "$_pid" =~ ^[0-9]+$ ]] && kill -0 "$_pid" 2>/dev/null && echo "up" || echo "down"
}
check_docker() {
    docker info &>/dev/null 2>&1 &
    local pid=$! i
    for ((i = 0; i < 20; i++)); do
        if ! kill -0 "$pid" 2>/dev/null; then
            wait "$pid"
            local ec=$?
            if ((ec == 0)); then
                echo "up:$(docker ps -q 2>/dev/null | wc -l | tr -d ' ')"
            else
                echo "down:0"
            fi
            return
        fi
        sleep 0.1
    done
    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    echo "down:0"
}
check_ngrok() {
    curl -sf --max-time 1 http://localhost:4040/api/tunnels &>/dev/null && echo "up" || echo "down"
}

_MENU_CACHE_TS=0
_MENU_CACHE_RT=""
_MENU_CACHE_DK=""
_MENU_CACHE_NG=""

_refresh_status_cache() {
    local now
    now=$(date +%s)
    if ((now - _MENU_CACHE_TS > 5)); then
        local _st_dir="$KMAC_CACHE_DIR/.status.$$"
        mkdir -p "$_st_dir"
        check_rt     > "$_st_dir/rt" &
        local _p1=$!
        check_docker > "$_st_dir/dk" &
        local _p2=$!
        check_ngrok  > "$_st_dir/ng" &
        local _p3=$!
        wait "$_p1" "$_p2" "$_p3" 2>/dev/null
        _MENU_CACHE_RT=$(<"$_st_dir/rt" 2>/dev/null)
        _MENU_CACHE_DK=$(<"$_st_dir/dk" 2>/dev/null)
        _MENU_CACHE_NG=$(<"$_st_dir/ng" 2>/dev/null)
        rm -rf "$_st_dir"
        _MENU_CACHE_TS=$now
    fi
}

# ─── Plugin Discovery ────────────────────────────────────────────────────

declare -a PLUGIN_NAMES=() PLUGIN_PATHS=() PLUGIN_DESCS=() PLUGIN_KEYS=()
_PLUGINS_DISCOVERED_TS=0

_BUILTIN_KEYS="a A v c s p e x k r d n . b u ? / i I o P R + 0 S"

discover_plugins() {
    local _now; _now=$(date +%s)
    (( _now - _PLUGINS_DISCOVERED_TS < 5 )) && return
    _PLUGINS_DISCOVERED_TS=$_now
    PLUGIN_NAMES=() PLUGIN_PATHS=() PLUGIN_DESCS=() PLUGIN_KEYS=()
    hooks_clear_plugin_handlers 2>/dev/null || true
    [[ -d "$PLUGINS_DIR" ]] || return
    local used_keys="$_BUILTIN_KEYS"
    for plugin in "$PLUGINS_DIR"/*; do
        [[ -x "$plugin" && -f "$plugin" ]] || continue
        local name desc key hooks_raw hook_entry
        name=$(grep -m1 '^# TOOLKIT_NAME:' "$plugin" 2>/dev/null | sed 's/^# TOOLKIT_NAME: *//')
        desc=$(grep -m1 '^# TOOLKIT_DESC:' "$plugin" 2>/dev/null | sed 's/^# TOOLKIT_DESC: *//')
        key=$(grep -m1 '^# TOOLKIT_KEY:' "$plugin" 2>/dev/null | sed 's/^# TOOLKIT_KEY: *//')
        hooks_raw=$(grep -m1 '^# TOOLKIT_HOOKS:' "$plugin" 2>/dev/null | sed 's/^# TOOLKIT_HOOKS: *//')
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
            if [[ -n "$hooks_raw" ]]; then
                hooks_raw="${hooks_raw//,/ }"
                read -r -a _hook_entries <<< "$hooks_raw"
                for hook_entry in "${_hook_entries[@]}"; do
                    [[ -n "$hook_entry" ]] && hooks_register_plugin "$hook_entry" "$plugin"
                done
            fi
        fi
    done
}

# ─── Animated Intro ──────────────────────────────────────────────────────
_INTRO_PLAYED=0

animate_intro() {
    (( _INTRO_PLAYED )) && return
    _INTRO_PLAYED=1

    local term_cols term_rows
    term_cols=$(tput cols 2>/dev/null || echo 80)
    term_rows=$(tput lines 2>/dev/null || echo 24)
    (( term_cols < 50 || term_rows < 14 )) && return
    tput civis 2>/dev/null || return
    clear

    # 16-point elliptical orbit (1-based row, col for ANSI positioning)
    local -a rr=(7  5  3  2  2  2  3  5   7  9  11 12 12 12 11 9)
    local -a rc=(39 38 34 29 23 17 12 8   7  8  12 17 23 29 34 38)
    local np=16
    local text_c=12 skipped=0

    local frame
    for ((frame=0; frame<16; frame++)); do
        read -r -t 0.04 -n1 _ 2>/dev/null && { skipped=1; break; }

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
        printf '\033[6;%dH\033[38;5;%dm\033[1m █▄▀  █▀▄▀█  ▄▀█  █▀▀\033[0m' "$text_c" "$pc"
        printf '\033[7;%dH\033[38;5;%dm\033[1m █ █  █ ▀ █  █▀█  █▄▄\033[0m  \033[2mCLI\033[0m' "$text_c" "$pc"
        printf '\033[9;14H\033[2mportable macOS toolkit\033[0m'

        sleep 0.04
    done

    if (( skipped )); then
        tput cnorm 2>/dev/null; return
    fi

    sleep 0.1
    clear
    echo ""; echo ""

    printf "    \033[38;5;33m██╗  ██╗\033[0m \033[38;5;39m███╗   ███╗\033[0m  \033[38;5;45m█████╗\033[0m   \033[38;5;49m██████╗\033[0m\n"; sleep 0.03
    printf "    \033[38;5;33m██║ ██╔╝\033[0m \033[38;5;39m████╗ ████║\033[0m \033[38;5;45m██╔══██╗\033[0m \033[38;5;49m██╔════╝\033[0m\n"; sleep 0.03
    printf "    \033[38;5;33m█████╔╝\033[0m  \033[38;5;39m██╔████╔██║\033[0m \033[38;5;45m███████║\033[0m \033[38;5;49m██║\033[0m\n"; sleep 0.03
    printf "    \033[38;5;33m██╔═██╗\033[0m  \033[38;5;39m██║╚██╔╝██║\033[0m \033[38;5;45m██╔══██║\033[0m \033[38;5;49m██║\033[0m\n"; sleep 0.03
    printf "    \033[38;5;33m██║  ██╗\033[0m \033[38;5;39m██║ ╚═╝ ██║\033[0m \033[38;5;45m██║  ██║\033[0m \033[38;5;49m╚██████╗\033[0m\n"; sleep 0.03
    printf "    \033[38;5;33m╚═╝  ╚═╝\033[0m \033[38;5;39m╚═╝     ╚═╝\033[0m \033[38;5;45m╚═╝  ╚═╝\033[0m  \033[38;5;49m╚═════╝\033[0m\n"
    echo ""
    printf '        \033[2mportable macOS toolkit\033[0m                       \033[2mv%s\033[0m\n' "$VERSION"

    sleep 0.3
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

    _refresh_status_cache
    local rt="$_MENU_CACHE_RT" dk="$_MENU_CACHE_DK" ng="$_MENU_CACHE_NG"
    local dk_state="${dk%%:*}" dk_count="${dk##*:}"

    # ─── Logo ───
    print_logo

    # ─── Status Bar (fixed-width box with absolute cursor positioning) ───
    echo ""
    local _BW=56  # box inner width (content area between │ markers)
    local _BR=58  # right-border column (2 indent + 1 border + _BW + 1 border)

    _box_top()    { printf "  ${DIM}┌─ %s " "$1"; printf '%*s' "$(( _BW - ${#1} - 3 ))" '' | tr ' ' '─'; printf "┐${NC}\n"; }
    _box_mid()    { printf "  ${DIM}├─ %s " "$1"; printf '%*s' "$(( _BW - ${#1} - 3 ))" '' | tr ' ' '─'; printf "┤${NC}\n"; }
    _box_bottom() { printf "  ${DIM}└"; printf '%*s' "$(( _BW ))" '' | tr ' ' '─'; printf "┘${NC}\n"; }
    _box_row()    { printf "  ${DIM}│${NC}  %b" "$1"; printf "\033[${_BR}G${DIM}│${NC}\n"; }

    local rt_label dk_label ng_label
    if [[ "$rt" == "up" ]]; then rt_label="${GREEN}●${NC} Remote Terminal"; else rt_label="${DIM}○ Remote Terminal${NC}"; fi
    if [[ "$dk_state" == "up" ]]; then dk_label="${GREEN}●${NC} Docker ${DIM}(${dk_count})${NC}"; else dk_label="${DIM}○ Docker${NC}"; fi
    if [[ "$ng" == "up" ]]; then ng_label="${GREEN}●${NC} ngrok"; else ng_label="${DIM}○ ngrok${NC}"; fi

    _box_top "services"
    _box_row "${rt_label}    ${dk_label}    ${ng_label}"

    local _cache="$KMAC_CACHE_DIR/last-check.json"
    if [[ -s "$_cache" ]]; then
        local _ucount
        _ucount=$(wc -l < "$_cache" 2>/dev/null | tr -d ' ')
        if (( _ucount > 0 )); then
            _box_row "${YELLOW}▸${NC} ${_ucount} update(s) available ${DIM}— press${NC} ${BOLD}u${NC} ${DIM}to review${NC}"
        fi
    fi

    # ─── System Stats ───
    local _df_out _disk_used _disk_total _disk_pct _disk_num
    _df_out=$(df -H / 2>/dev/null | tail -1)
    _disk_used=$(echo "$_df_out" | awk '{print $3}')
    _disk_total=$(echo "$_df_out" | awk '{print $2}')
    _disk_pct=$(echo "$_df_out" | awk '{print $5}')
    _disk_num=${_disk_pct%%%}

    local _up_raw _uptime _load
    _up_raw=$(uptime 2>/dev/null)
    _uptime=$(echo "$_up_raw" | sed 's/.*up //;s/, [0-9]* user.*//' \
        | sed 's/ days*/d/;s/ mins*/m/;s/,//;s/\([0-9]*\):[0-9]*/\1h/' | xargs)
    _load=$(echo "$_up_raw" | sed 's/.*load average[s]*: //' | awk '{print $1}')

    local _bat _bat_str=""
    _bat=$(pmset -g batt 2>/dev/null | grep -o '[0-9]*%' | head -1)
    [[ -n "$_bat" ]] && _bat_str="  ${DIM}·${NC}  Bat ${_bat}"

    local _disk_color="${NC}"
    (( _disk_num > 75 )) && _disk_color="${YELLOW}"
    (( _disk_num > 90 )) && _disk_color="${RED}"

    _box_mid "system"
    _box_row "Disk ${_disk_used}/${_disk_total} ${_disk_color}${_disk_pct}${NC}  ${DIM}·${NC}  Load ${_load}  ${DIM}·${NC}  Up ${_uptime}${_bat_str}"
    _box_bottom

    # ─── Commands — 3-column layout (absolute column positioning for ANSI-safe alignment) ───
    echo ""
    local C1=4 C2=30 C3=56

    _mc() {
        printf "   ${GREEN}%s${NC}  %b" "$1" "$2"
        printf "\033[${C2}G${GREEN}%s${NC}  %b" "$3" "$4"
        if [[ -n "$5" ]]; then
            printf "\033[${C3}G${GREEN}%s${NC}  %b" "$5" "$6"
        fi
        printf '\n'
    }

    printf "   ${C_CYAN}${BOLD}AI & Research${NC}"
    printf "\033[${C2}G${C_TEAL}${BOLD}Dev${NC}"
    printf "\033[${C3}G${C_GREEN}${BOLD}Infra${NC}\n"

    printf "   ${DIM}─────────────${NC}"
    printf "\033[${C2}G${DIM}───${NC}"
    printf "\033[${C3}G${DIM}─────${NC}\n"

    _mc "a" "Ask Claude"             "p" "Project Launcher"     "d" "Docker Manager"
    _mc "A" "KmacAgent ${DIM}(tools)${NC}" "e" "Claude Code"          "r" "Remote Terminal"
    _mc "o" "Ollama (Local AI)"      "x" "Cursor Agent"         "P" "Pilot ${DIM}(remote)${NC}"
    _mc "+" "AI Toolmaker"           "v" "Code Review"          "n" "Network Info"
    _mc "R" "Research ${DIM}(autorun)${NC}" "c" "Smart Commit"        "k" "Kill Port"
    echo ""
    echo -e "   ${YELLOW}${BOLD}System${NC}"
    echo -e "   ${DIM}──────${NC}"
    _mc "S" "Storage Manager"     "u" "Check Updates"       "b" "Backup Dotfiles"
    _mc "." "Secrets & Keys"      "i" "Install / Bootstrap" "I" "Software Manager"
    _mc "?" "Health Check"        "/" "Aliases"             "" ""

    # ─── Plugins (sorted by key, 3-column grid) ───
    if (( ${#PLUGIN_NAMES[@]} > 0 )); then
        echo ""
        echo -e "   ${MAGENTA}${BOLD}Plugins${NC}  ${DIM}— drop-in extensions${NC}"
        echo -e "   ${DIM}───────${NC}"
        local _sorted_pi=()
        _sorted_pi=($(
            for _si in "${!PLUGIN_KEYS[@]}"; do
                printf '%s %s\n' "${PLUGIN_KEYS[$_si]:-$((_si+1))}" "$_si"
            done | sort -n -k1 | awk '{print $2}'
        ))
        local _pcol=0
        for _si in "${_sorted_pi[@]}"; do
            local _pk="${PLUGIN_KEYS[$_si]:-$((_si+1))}"
            local _col=$(( C1 + (_pcol % 3) * 26 ))
            if (( _pcol % 3 == 0 )) && (( _pcol > 0 )); then printf '\n'; fi
            printf "\033[${_col}G${GREEN}%s${NC})  %s" "$_pk" "${PLUGIN_NAMES[$_si]}"
            ((_pcol++))
        done
        echo ""
    fi

    # ─── Footer ───
    echo ""
    echo -e "  ${DIM}─────────────────────────────────────────────────────${NC}"
    random_tip
    echo -e "   ${DIM}0  Exit${NC}"
    echo ""
}

# ─── Tool Functions ───────────────────────────────────────────────────────

do_docker() {
    bash "$SCRIPTS_DIR/docker" || { tool_error "Docker Manager error"; }
}

do_remote_terminal() {
    # shellcheck source=scripts/remote-terminal.sh
    source "$SCRIPTS_DIR/remote-terminal.sh" 2>/dev/null
    local status
    status=$(check_rt)
    title_box "Remote Terminal" "🖥"
    if [[ "$status" == "up" ]]; then
        local url
        url=$(curl -sf http://localhost:4040/api/tunnels 2>/dev/null \
            | grep -o '"public_url":"[^"]*"' | head -1 | cut -d'"' -f4)
        echo -e "  Status: ${GREEN}● Running${NC}"
        echo -e "  URL:    ${GREEN}${url:-unknown}${NC}"
        echo -e "  Auth:   user / ******** ${DIM}(stored in vault)${NC}"
        echo -e "  ${DIM}Press 'p' to reveal password${NC}"
        echo ""
        echo -e "  ${GREEN}q${NC}) Show QR code"
        echo -e "  ${GREEN}p${NC}) Reveal password"
        echo -e "  ${GREEN}r${NC}) Restart"
        echo -e "  ${GREEN}s${NC}) Stop"
        echo -e "  ${GREEN}t${NC}) Re-attach tmux (reconnect only)"
        menu_back
        read -r -n1 -p "  > " rt_ch; echo ""
        case "$rt_ch" in
            p|P)
                local _rt_pass
                _rt_pass=$(vault_get "rt-password" 2>/dev/null)
                [[ -n "$_rt_pass" ]] && echo -e "  Password: ${_rt_pass}" || echo -e "  ${YELLOW}(not in vault)${NC}"
                ;;
            q|Q)
                [[ -n "$url" ]] && qrencode -t UTF8 "$url" 2>/dev/null || echo "No URL available"
                ;;
            r|R) stop-remote-terminal; echo ""; remote-terminal ;;
            s|S) stop-remote-terminal ;;
            t|T)
                echo "Re-attaching to tmux session 'remote'..."
                tmux attach -t remote 2>/dev/null || echo "No tmux session found."
                ;;
            m|M|"") return ;;
        esac
    else
        echo -e "  Status: ${DIM}○ Stopped${NC}"
        echo ""
        echo -e "  ${GREEN}s${NC}) Start"
        menu_back
        read -r -n1 -p "  > " rt_ch; echo ""
        case "$rt_ch" in
            s|S) remote-terminal || tool_error "Failed to start Remote Terminal" ;;
            m|M|"") return ;;
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
    echo -e "  Password: ${GREEN}********${NC} ${DIM}(stored in vault)${NC}"
    echo -e "  ${DIM}Press 'p' to reveal password${NC}"
    echo ""
    [[ -n "$url" ]] && qrencode -t UTF8 "$url" 2>/dev/null
    echo ""
    read -r -n1 -p "  > " _qrpw; echo ""
    if [[ "$_qrpw" == [pP] ]]; then
        local _rp
        _rp=$(vault_get "rt-password" 2>/dev/null)
        [[ -n "$_rp" ]] && echo -e "  Password: ${_rp}" || echo -e "  ${YELLOW}(not in vault)${NC}"
    fi
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
    local lip pip wifi gw
    lip=$(ipconfig getifaddr en0 2>/dev/null || echo "Not connected")
    pip=$(curl -sf --max-time 3 https://ifconfig.me 2>/dev/null || echo "Unavailable")
    wifi=$(/System/Library/PrivateFrameworks/Apple80211.framework/Versions/Current/Resources/airport -I 2>/dev/null | awk '/ SSID/ {print $NF}')
    gw=$(netstat -rn 2>/dev/null | awk '/default.*en0/ {print $2; exit}')
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
            local ver
            ver=$("$dep" --version 2>/dev/null | head -1 | tr -d '\n')
            echo -e "    ${GREEN}✓${NC} $dep  ${DIM}${ver:0:40}${NC}"
        else
            echo -e "    ${RED}✗${NC} $dep"; ((issues++))
        fi
    done
    echo ""
    echo -e "  ${BOLD}Secrets Vault:${NC}"
    local _hc_backend
    _hc_backend=$(_vault_backend 2>/dev/null || echo "unknown")
    echo -e "    Backend: ${CYAN}${_hc_backend}${NC}"

    local _hc_configured=0 _hc_total=0
    _vault_load_registry 2>/dev/null
    for (( _hi=0; _hi<${#_REG_SERVICES[@]}; _hi++ )); do
        ((_hc_total++))
        vault_has "${_REG_SERVICES[$_hi]}" 2>/dev/null && ((_hc_configured++))
    done
    if (( _hc_configured > 0 )); then
        echo -e "    ${GREEN}✓${NC} ${_hc_configured}/${_hc_total} integrations configured"
    else
        echo -e "    ${YELLOW}!${NC} No credentials configured ${DIM}(use '.' to set up)${NC}"
    fi

    # Key checks via vault
    vault_has "anthropic" 2>/dev/null \
        && echo -e "    ${GREEN}✓${NC} Anthropic API key" \
        || echo -e "    ${DIM}○${NC} Anthropic API key not set"
    vault_has "github" 2>/dev/null \
        && echo -e "    ${GREEN}✓${NC} GitHub token" \
        || echo -e "    ${DIM}○${NC} GitHub token not set"
    vault_has "rt-password" 2>/dev/null \
        && echo -e "    ${GREEN}✓${NC} Remote Terminal password" \
        || echo -e "    ${DIM}○${NC} Remote Terminal password not set"
    echo ""
    echo -e "  ${BOLD}Paths:${NC}"
    local _n_scripts _n_plugins
    if [[ -d "$TOOLKIT_DIR" ]]; then
        echo -e "    ${GREEN}✓${NC} Toolkit dir"
    else
        echo -e "    ${RED}✗${NC} Toolkit dir missing"
        ((issues++))
    fi
    if [[ -d "$SCRIPTS_DIR" ]]; then
        _n_scripts=$(find "$SCRIPTS_DIR" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' ')
        echo -e "    ${GREEN}✓${NC} Scripts (${_n_scripts})"
    else
        echo -e "    ${RED}✗${NC} Scripts missing"
        ((issues++))
    fi
    if [[ -d "$PLUGINS_DIR" ]]; then
        _n_plugins=$(find "$PLUGINS_DIR" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' ')
        echo -e "    ${GREEN}✓${NC} Plugins (${_n_plugins})"
    else
        echo -e "    ${DIM}○${NC} No plugins dir"
    fi
    if grep -q "alias toolkit=" ~/.zshrc 2>/dev/null; then
        echo -e "    ${GREEN}✓${NC} .zshrc integrated"
    else
        echo -e "    ${RED}✗${NC} .zshrc missing toolkit"
        ((issues++))
    fi
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
                local name key val
                name="${line#alias }"
                key="${name%%=*}"
                val="${name#*=}"
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
    bash "$SCRIPTS_DIR/secrets"
}

do_install_bootstrap() {
    title_box "Install / Bootstrap" "⚙"
    echo -e "  ${GREEN}i${NC}) Install/Update Toolkit"
    echo -e "  ${GREEN}b${NC}) Export Brewfile ${DIM}(save current)${NC}"
    echo -e "  ${GREEN}B${NC}) Install from Brewfile"
    echo -e "  ${GREEN}p${NC}) Apply macOS Preferences"
    echo -e "  ${GREEN}f${NC}) Full Bootstrap ${DIM}(Brewfile + prefs + install)${NC}"
    menu_back
    read -r -n1 -p "  > " bc; echo ""
    case "$bc" in
        i)  safe_run "Install/Update Toolkit" bash "$TOOLKIT_DIR/install.sh" ;;
        b)  brew bundle dump --file="$TOOLKIT_DIR/Brewfile" --force 2>/dev/null
            echo -e "${GREEN}✓ Brewfile saved${NC}" ;;
        B)  [[ -f "$TOOLKIT_DIR/Brewfile" ]] && brew bundle --file="$TOOLKIT_DIR/Brewfile" || echo "No Brewfile found" ;;
        p)  defaults write com.apple.dock autohide -bool true
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
        f)  [[ -f "$TOOLKIT_DIR/Brewfile" ]] && brew bundle --file="$TOOLKIT_DIR/Brewfile"
            defaults write com.apple.dock autohide -bool true; defaults write com.apple.dock tilesize -int 48
            defaults write NSGlobalDomain AppleShowAllExtensions -bool true; defaults write NSGlobalDomain KeyRepeat -int 2
            mkdir -p ~/Screenshots; defaults write com.apple.screencapture location ~/Screenshots
            killall Dock Finder 2>/dev/null || true
            bash "$TOOLKIT_DIR/install.sh"
            echo -e "${GREEN}✓ Full bootstrap complete${NC}" ;;
        m|M) return ;;
    esac
    pause
}

# ─── Main Loop ────────────────────────────────────────────────────────────

welcome_wizard() {
    clear
    echo ""
    echo -e "  ${C_CYAN}${BOLD}Welcome to KMac CLI${NC}"
    echo -e "  ${DIM}Your portable macOS command center${NC}"
    echo ""
    echo -e "  Let's get you set up. I'll walk you through each step."
    echo ""

    # Step 1: Check essentials
    section "Step 1 of 4 — Health Check"
    local ok=0 total=0
    for dep in git python3 curl docker brew; do
        ((total++))
        if command -v "$dep" &>/dev/null; then
            ui_success "$dep found"
            ((ok++))
        else
            ui_warn "$dep not found ${DIM}(some features will be limited)${NC}"
        fi
    done
    echo ""
    echo -e "  ${BOLD}${ok}/${total}${NC} core tools ready"
    echo ""
    read -r -n1 -p "  Press any key to continue..."; echo ""

    # Step 2: Choose vault backend
    clear
    echo ""
    section "Step 2 of 4 — Choose Your Secret Vault"
    echo ""
    echo -e "  KMac stores API keys and credentials in a secure vault."
    echo -e "  ${DIM}Pick where you'd like secrets stored:${NC}"
    echo ""
    echo -e "   ${GREEN}1${NC})  ${BOLD}macOS Keychain${NC} ${DIM}(recommended)${NC}"
    echo -e "      ${DIM}Hardware-backed, unlocked by your login password.${NC}"
    echo -e "      ${DIM}Best for most users. Secrets survive reinstalls.${NC}"
    echo ""
    echo -e "   ${GREEN}2${NC})  ${BOLD}Encrypted File${NC}"
    echo -e "      ${DIM}AES-256 encrypted vault at ~/.config/kmac/vault.enc${NC}"
    echo -e "      ${DIM}Portable — sync via iCloud or USB to other machines.${NC}"
    echo ""
    if command -v docker &>/dev/null; then
        echo -e "   ${GREEN}3${NC})  ${BOLD}Docker Container${NC}"
        echo -e "      ${DIM}Isolated vault in a local container (kmac-vault).${NC}"
        echo -e "      ${DIM}Portable — export the Docker volume to move it.${NC}"
        echo ""
    fi
    echo -e "  ${DIM}You can switch anytime with:${NC} ${GREEN}kmac secrets backend${NC}"
    echo ""
    read -r -n1 -p "  Choose [1/2/3]: " _vault_choice; echo ""

    # Source the guided setup functions from secrets
    # shellcheck source=scripts/secrets
    source "$SCRIPTS_DIR/secrets" _source_only 2>/dev/null

    case "$_vault_choice" in
        2)
            export KMAC_VAULT_BACKEND="file"
            _write_backend_pref "file"
            echo ""
            echo -e "  ${BOLD}Create your vault master password:${NC}"
            echo -e "  ${DIM}You'll need this each session to unlock your secrets.${NC}"
            echo ""
            read -r -s -p "  Master password: " _pw1; echo ""
            read -r -s -p "  Confirm: " _pw2; echo ""
            if [[ "$_pw1" == "$_pw2" && -n "$_pw1" ]]; then
                _vault_master_password="$_pw1"
                _vault_encrypt "{}"
                ui_success "Encrypted file vault created"
            else
                ui_warn "Passwords didn't match — defaulting to Keychain for now"
                export KMAC_VAULT_BACKEND="keychain"
                _write_backend_pref "keychain"
            fi
            ;;
        3)
            if command -v docker &>/dev/null && docker info &>/dev/null 2>&1; then
                echo ""
                echo -e "  ${DIM}Starting Docker vault container...${NC}"
                if docker_vault_start 2>/dev/null; then
                    export KMAC_VAULT_BACKEND="docker"
                    _write_backend_pref "docker"
                    ui_success "Docker vault running on 127.0.0.1:${VAULT_DOCKER_PORT}"
                else
                    ui_warn "Docker vault failed to start — using Keychain instead"
                    export KMAC_VAULT_BACKEND="keychain"
                    _write_backend_pref "keychain"
                fi
            else
                ui_warn "Docker not running — using Keychain instead"
                export KMAC_VAULT_BACKEND="keychain"
                _write_backend_pref "keychain"
            fi
            ;;
        *)
            export KMAC_VAULT_BACKEND="keychain"
            _write_backend_pref "keychain"
            ui_success "Using macOS Keychain"
            ;;
    esac
    echo ""
    read -r -n1 -p "  Press any key to continue..."; echo ""

    # Step 3: Guided API key setup
    clear
    echo ""
    section "Step 3 of 4 — Connect Your Services"
    echo ""
    echo -e "  KMac works best with API keys for AI, GitHub, and other services."
    echo -e "  ${DIM}I'll open the signup page for each one and walk you through it.${NC}"
    echo -e "  ${DIM}Skip any you don't need — you can always add them later with${NC} ${GREEN}kmac secrets${NC}"
    echo ""

    local -a _wiz_services=("anthropic" "openai" "github" "ngrok")
    local -a _wiz_labels=("Anthropic (Claude AI)" "OpenAI (GPT)" "GitHub" "ngrok (tunnels)")
    local _wiz_configured=0

    for (( _wi=0; _wi<${#_wiz_services[@]}; _wi++ )); do
        local svc="${_wiz_services[$_wi]}"
        local label="${_wiz_labels[$_wi]}"

        # Skip if already configured
        if vault_has "$svc" 2>/dev/null; then
            ui_success "${label} — already configured"
            ((_wiz_configured++))
            continue
        fi

        echo ""
        echo -e "  ${BOLD}${label}${NC}"
        read -r -n1 -p "  Set up now? (y/N/q to skip all) > " yn; echo ""

        case "$yn" in
            y|Y)
                guided_setup "$svc" && ((_wiz_configured++))
                ;;
            q|Q)
                echo -e "  ${DIM}Skipping remaining services.${NC}"
                break
                ;;
            *)
                echo -e "  ${DIM}Skipped — add later with:${NC} ${GREEN}kmac secrets set ${svc}${NC}"
                ;;
        esac
    done

    echo ""
    if (( _wiz_configured > 0 )); then
        echo -e "  ${GREEN}${BOLD}${_wiz_configured} service(s) configured!${NC}"
    else
        echo -e "  ${DIM}No services configured yet — that's fine.${NC}"
        echo -e "  ${DIM}Run${NC} ${GREEN}kmac secrets${NC} ${DIM}anytime to manage your keys.${NC}"
    fi
    echo ""
    read -r -n1 -p "  Press any key to continue..."; echo ""

    # Step 4: Quick orientation
    clear
    echo ""
    section "Step 4 of 4 — Quick Tour"
    echo ""
    echo -e "  ${BOLD}How to use KMac:${NC}"
    echo ""
    echo -e "   ${GREEN}kmac${NC}              Open the interactive menu"
    echo -e "   ${GREEN}kmac ask${NC} ${DIM}\"...\"${NC}    Chat with Claude from anywhere"
    echo -e "   ${GREEN}kmac review${NC}       AI code review on your current changes"
    echo -e "   ${GREEN}kmac secrets${NC}      Manage API keys and credentials"
    echo -e "   ${GREEN}kmac docker${NC}       Docker container manager"
    echo -e "   ${GREEN}kmac help${NC}         See all available commands"
    echo ""
    echo -e "  ${DIM}In the menu, each tool has a single-key shortcut.${NC}"
    echo -e "  ${DIM}Just press the green letter to jump to it.${NC}"
    echo ""

    mark_first_run_done

    echo -e "  ${GREEN}${BOLD}You're all set!${NC}"
    echo ""
    read -r -n1 -p "  Press any key to enter KMac..."; echo ""
}

# Background vault export — runs keychain lookups in parallel with the intro animation
_VAULT_EXPORT_FILE=""
_VAULT_BG_PID=""

_start_vault_export_bg() {
    _VAULT_EXPORT_FILE="$KMAC_CACHE_DIR/.vault-env.$$"
    (
        _vault_load_registry 2>/dev/null
        for (( _vi=0; _vi<${#_REG_SERVICES[@]}; _vi++ )); do
            _svc="${_REG_SERVICES[$_vi]}"
            _envvar="${_REG_ENVVARS[$_vi]}"
            [[ -z "$_envvar" ]] && continue
            _val=$(vault_get "$_svc" 2>/dev/null) || true
            [[ -n "$_val" ]] && printf 'export %s=%q\n' "$_envvar" "$_val"
        done > "$_VAULT_EXPORT_FILE"
    ) &
    _VAULT_BG_PID=$!
}

_finish_vault_export() {
    if [[ -n "${_VAULT_BG_PID:-}" ]]; then
        wait "$_VAULT_BG_PID" 2>/dev/null
        _VAULT_BG_PID=""
    fi
    if [[ -f "${_VAULT_EXPORT_FILE:-}" ]]; then
        source "$_VAULT_EXPORT_FILE" 2>/dev/null
        rm -f "$_VAULT_EXPORT_FILE"
        _VAULT_EXPORT_FILE=""
    fi
}

main() {
    mkdir -p "$PLUGINS_DIR" 2>/dev/null

    # Start vault export in background — runs during intro animation
    _start_vault_export_bg

    if is_first_run; then
        welcome_wizard
    fi

    # Collect vault exports (should be done by now, waits if still running)
    _finish_vault_export

    discover_plugins
    hooks_emit on-startup || true

    while true; do
        print_menu
        read -r -n1 -p "  > " choice; echo ""
        case "$choice" in
            # AI
            a) clear; do_ask ;;
            A) clear; bash "$SCRIPTS_DIR/agent" ;;
            +) clear; bash "$SCRIPTS_DIR/toolmaker"; pause ;;
            o) clear; bash "$SCRIPTS_DIR/ollama-setup" ;;
            R) clear; bash "$SCRIPTS_DIR/research" ;;
            # Dev
            p) clear; safe_run "Project Launcher" bash "$SCRIPTS_DIR/project" ;;
            e) clear; bash "$SCRIPTS_DIR/claudeme" ;;
            x) clear; echo -e "${BOLD}Cursor Agent Task:${NC}"; read -r -p "Task: " t; safe_run "Cursor Agent" bash "$SCRIPTS_DIR/cursoragent" "$t" ;;
            v) clear; safe_run "Code Review" bash "$SCRIPTS_DIR/review"; pause ;;
            c) clear; safe_run "Smart Commit" bash "$SCRIPTS_DIR/aicommit"; pause ;;
            # Infra
            d) clear; do_docker ;;
            r) clear; do_remote_terminal ;;
            P) clear; bash "$SCRIPTS_DIR/pilot" status; pause ;;
            n) clear; do_network ;;
            k) clear; echo -e "${BOLD}Kill Port:${NC}"; read -r -p "Port (blank=list): " pt; safe_run "Kill Port" bash "$SCRIPTS_DIR/killport" "$pt"; pause ;;
            # System
            .) clear; do_secrets ;;
            S) clear; bash "$SCRIPTS_DIR/storage"; pause ;;
            b) clear; safe_run "Dotfile Backup" bash "$SCRIPTS_DIR/dotbackup"; pause ;;
            u) clear; safe_run "Update Check" bash "$SCRIPTS_DIR/update-check"; pause ;;
            i) clear; do_install_bootstrap ;;
            I) clear; bash "$SCRIPTS_DIR/software" ;;
            /) clear; do_aliases ;;
            \?) clear; do_health ;;
            0) hooks_emit on-exit || true; echo -e "\n  ${C_TEAL}See you! ✌${NC}\n"; exit 0 ;;
            *)
                # Check plugins
                local matched=false
                for idx in "${!PLUGIN_KEYS[@]}"; do
                    if [[ "$choice" == "${PLUGIN_KEYS[$idx]}" ]]; then
                        clear; bash "${PLUGIN_PATHS[$idx]}"; pause; matched=true; break
                    fi
                done
                [[ "$matched" == true ]] || { echo -e "${RED}Unknown: '$choice'${NC}"; sleep 0.5; }
                ;;
        esac
    done
}

# ─── Subcommand Router ────────────────────────────────────────────────────

if [[ $# -gt 0 ]]; then
    subcmd="$1"; shift
    case "$subcmd" in
        ask)        exec bash "$SCRIPTS_DIR/ask" "$@" ;;
        agent)      exec bash "$SCRIPTS_DIR/agent" "$@" ;;
        review)     exec bash "$SCRIPTS_DIR/review" "$@" ;;
        aicommit)   exec bash "$SCRIPTS_DIR/aicommit" "$@" ;;
        sessions)   exec bash "$SCRIPTS_DIR/sessions" "$@" ;;
        project)    exec bash "$SCRIPTS_DIR/project" "$@" ;;
        cask|cursoragent) exec bash "$SCRIPTS_DIR/cursoragent" "$@" ;;
        killport)   exec bash "$SCRIPTS_DIR/killport" "$@" ;;
        pilot)      exec bash "$SCRIPTS_DIR/pilot" "$@" ;;
        server)     # shellcheck source=scripts/server
                    source "$SCRIPTS_DIR/server" ;;
        remote-access)
            # Optional add-on; not present in all trees — shellcheck cannot resolve path
            # shellcheck disable=SC1091
            source "$SCRIPTS_DIR/remote-access" ;;
        dotbackup)  exec bash "$SCRIPTS_DIR/dotbackup" "$@" ;;
        update)     exec bash "$SCRIPTS_DIR/update-check" "$@" ;;
        doctor)     do_health ;;
        storage)    exec bash "$SCRIPTS_DIR/storage" "$@" ;;
        secrets)    exec bash "$SCRIPTS_DIR/secrets" "$@" ;;
        docker)     exec bash "$SCRIPTS_DIR/docker" "$@" ;;
        docker-health) exec bash "$SCRIPTS_DIR/docker-health" "$@" ;;
        make|build|toolmaker) exec bash "$SCRIPTS_DIR/toolmaker" "$@" ;;
        research) exec bash "$SCRIPTS_DIR/research" "$@" ;;
        software|sw) exec bash "$SCRIPTS_DIR/software" "$@" ;;
        ollama) exec bash "$SCRIPTS_DIR/ollama-setup" "$@" ;;
        assistant|ai|orchestrator|orch|skillopt) exec bash "$SCRIPTS_DIR/agent" "$@" ;;
        version|-v|--version)
            print_logo
            echo ""
            echo -e "  ${DIM}Installed: ${TOOLKIT_DIR}${NC}"
            _v_scripts=$(find "$SCRIPTS_DIR" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' ')
            _v_plugins=$(find "$PLUGINS_DIR" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l | tr -d ' ')
            echo -e "  ${DIM}Scripts: ${_v_scripts}  Plugins: ${_v_plugins}${NC}"
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
            echo -e "  ${BOLD}AI & Research${NC}"
            echo "    ask \"question\"        Ask Claude (or -i for interactive, -m opus)"
            echo "    agent                 AI agent with tool use (files, commands, search)"
            echo "    make \"description\"    Build a new tool with AI"
            echo "    research [cmd]        Autonomous experiment runner (init|run|status|review|stop)"
            echo "    ollama [cmd]          Local AI setup (install|models|serve|stop|status|chat)"
            echo ""
            echo -e "  ${BOLD}Dev${NC}"
            echo "    project               Project launcher with fzf"
            echo "    review [--strict]     Code review (--quick, --staged)"
            echo "    aicommit [--amend]    Smart commit message with scope detection"
            echo "    cursoragent \"task\"     Cursor Agent task (alias: cask)"
            echo "    sessions              Resume a Claude Code session"
            echo ""
            echo -e "  ${BOLD}Infra${NC}"
            echo "    docker [cmd]          Docker Manager (dashboard|health|disk|compose|mcp)"
            echo "    docker-health         Docker health report (--json, --history)"
            echo "    pilot <cmd>           Remote AI agent via Telegram (start/stop/status)"
            echo "    server <cmd>          Pilot server lifecycle (start|stop|restart|status|logs|token|install|docker-up|down)"
            echo "    remote-access <cmd>   Pilot remote access (setup|start|stop|restart|status|url|qr)"
            echo "    killport [port]       Kill process on port (blank = list all)"
            echo ""
            echo -e "  ${BOLD}System${NC}"
            echo "    software [cmd]        Install dev tools & AI CLIs (list|install|update|search)"
            echo "    secrets [cmd]         Credential manager (list|get|set|export|add|backend)"
            echo "    storage [cmd]         Disk usage analyzer + iCloud migration"
            echo "    dotbackup [cmd]       Backup/restore/diff/hook dotfiles"
            echo "    update                Check for updates"
            echo "    doctor                Health check"
            echo ""
            echo -e "  ${BOLD}AI Services${NC}"
            echo "    agent [cmd]           KmacAgent daemon (start|stop|ask|chat|agents|tasks|memory|workflows)"
            echo ""
            echo -e "  ${BOLD}Meta${NC}"
            echo "    help, -h              Show this help"
            echo "    version, -v           Show version info"
            echo "    whatsnew              Show latest changelog"
            echo ""
            echo -e "${DIM}Run 'toolkit' or 'kmac' with no args for the interactive menu.${NC}"
            ;;
        *)
            if [[ "$subcmd" == *"/"* || "$subcmd" == *".."* ]]; then
                echo "Invalid plugin name." >&2
                exit 1
            fi
            if [[ -x "$PLUGINS_DIR/$subcmd" || -x "$PLUGINS_DIR/${subcmd}.sh" ]]; then
                p="$PLUGINS_DIR/$subcmd"
                [[ -x "$p" ]] || p="${p}.sh"
                exec bash "$p" "$@"
            fi
            echo "Unknown: $subcmd — try 'toolkit help'"
            exit 1 ;;
    esac
else
    main
fi
