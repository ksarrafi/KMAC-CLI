#!/bin/bash
# remote-terminal.sh — Sourceable remote terminal functions

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_vault.sh" 2>/dev/null

RT_RUNTIME_DIR="${KMAC_RT_RUNTIME_DIR:-$HOME/.config/kmac/remote-terminal}"

remote-terminal() {
    local pid_dir="$RT_RUNTIME_DIR"
    local ttyd_pidfile="$pid_dir/ttyd.pid"
    local caddy_pidfile="$pid_dir/caddy.pid"
    local ngrok_pidfile="$pid_dir/ngrok.pid"
    local caddyfile="$pid_dir/Caddyfile"

    # ── dependency check ──
    local missing=()
    local dep
    for dep in ttyd ngrok caddy qrencode tmux; do
        command -v "$dep" &>/dev/null || missing+=("$dep")
    done
    if (( ${#missing[@]} )); then
        echo "Error: missing dependencies: ${missing[*]}"
        echo "Install with:  brew install ${missing[*]}"
        return 1
    fi

    # ── idempotency: bail if already running ──
    if [[ -f "$ttyd_pidfile" ]] && kill -0 "$(cat "$ttyd_pidfile")" 2>/dev/null; then
        echo "remote-terminal is already running (ttyd PID $(cat "$ttyd_pidfile"))."
        echo "Run stop-remote-terminal first."
        return 1
    fi

    mkdir -p "$pid_dir" && chmod 700 "$pid_dir"

    # ── cleanup helper (kills whatever has been started so far) ──
    _rt_cleanup() {
        echo "Error: $1"
        echo "Cleaning up partially started services..."
        local pf
        for pf in "$ttyd_pidfile" "$caddy_pidfile" "$ngrok_pidfile"; do
            if [[ -f "$pf" ]]; then
                kill "$(cat "$pf")" 2>/dev/null
                rm -f "$pf"
            fi
        done
        rm -f "$caddyfile"
    }

    # ── credentials (from vault) ──
    local RT_USER="user"
    local RT_PASS
    RT_PASS=$(vault_get "rt-password" 2>/dev/null)
    if [[ -z "$RT_PASS" ]]; then
        echo "No remote-terminal password found in vault."
        echo "Set one with: kmac secrets set rt-password"
        read -r -s -p "Or enter a password now: " RT_PASS; echo ""
        if [[ -n "$RT_PASS" ]]; then
            vault_set "rt-password" "$RT_PASS" 2>/dev/null
            echo "Saved to vault for next time."
        else
            return 1
        fi
    fi

    # ── tmux session ──
    if ! tmux has-session -t remote 2>/dev/null; then
        tmux new-session -d -s remote || { _rt_cleanup "Failed to create tmux session 'remote'"; return 1; }
        echo "Created new tmux session 'remote'."
    else
        echo "Reusing existing tmux session 'remote'."
    fi

    # ── ttyd ──
    ttyd --writable -p 7681 tmux attach -t remote &>/dev/null &
    printf '%s\n' "$!" > "$ttyd_pidfile"
    sleep 1
    if ! kill -0 "$(cat "$ttyd_pidfile")" 2>/dev/null; then
        _rt_cleanup "ttyd failed to start on port 7681 (port already in use?)"; return 1
    fi
    echo "Started ttyd (PID $(cat "$ttyd_pidfile")) on :7681"

    # ── caddy: hash password & write config ──
    local HASHED
    HASHED=$(caddy hash-password --plaintext "$RT_PASS" 2>/dev/null)
    if [[ -z "$HASHED" ]]; then
        _rt_cleanup "caddy hash-password failed"; return 1
    fi

    cat > "$caddyfile" <<EOF
:7682 {
    reverse_proxy localhost:7681
    basic_auth {
        $RT_USER $HASHED
    }
}
EOF
    chmod 600 "$caddyfile"

    caddy run --config "$caddyfile" &>/dev/null &
    printf '%s\n' "$!" > "$caddy_pidfile"
    sleep 1
    if ! kill -0 "$(cat "$caddy_pidfile")" 2>/dev/null; then
        _rt_cleanup "Caddy failed to start on port 7682"; return 1
    fi
    echo "Started Caddy (PID $(cat "$caddy_pidfile")) on :7682"

    # ── ngrok ──
    if [[ -n "${NGROK_DOMAIN:-}" ]]; then
        ngrok http 7682 --url="$NGROK_DOMAIN" &>/dev/null &
    else
        ngrok http 7682 &>/dev/null &
    fi
    printf '%s\n' "$!" > "$ngrok_pidfile"
    sleep 2
    if ! kill -0 "$(cat "$ngrok_pidfile")" 2>/dev/null; then
        _rt_cleanup "ngrok failed to start"; return 1
    fi
    echo "Started ngrok (PID $(cat "$ngrok_pidfile"))"

    # ── poll ngrok API for the public URL ──
    local url="" elapsed=0
    echo "Waiting for ngrok tunnel..."
    while (( elapsed < 15 )); do
        url=$(curl -sf http://localhost:4040/api/tunnels 2>/dev/null \
            | grep -o '"public_url":"[^"]*"' | head -1 | cut -d'"' -f4)
        [[ -n "$url" ]] && break
        sleep 1
        (( elapsed++ ))
    done
    if [[ -z "$url" ]]; then
        _rt_cleanup "Timed out waiting for ngrok tunnel after 15 s"; return 1
    fi

    # ── print results ──
    echo ""
    echo "============================================"
    echo "  Remote Terminal is live!"
    echo "============================================"
    echo "  URL:      $url"
    echo "  Username: $RT_USER"
    echo "  Password: ******** (stored in vault — use toolkit Remote Terminal → 'p' to reveal, or: kmac secrets get rt-password)"
    echo "============================================"
    echo ""
    qrencode -t UTF8 "$url"
}

stop-remote-terminal() {
    local pid_dir="$RT_RUNTIME_DIR"
    local stopped=()
    local svc pf pid

    # ── kill by PID file ──
    for svc in ngrok caddy ttyd; do
        pf="$pid_dir/${svc}.pid"
        if [[ -f "$pf" ]]; then
            pid=$(cat "$pf")
            if kill "$pid" 2>/dev/null; then
                stopped+=("$svc (PID $pid)")
            fi
            rm -f "$pf"
        fi
    done

    # ── fallback: targeted pkill (caddy stopped via caddy.pid in loop above) ──
    pkill -f 'ttyd -p 7681' 2>/dev/null
    pkill -f 'ngrok http 7682' 2>/dev/null

    # ── clean up runtime files ──
    rm -f "$pid_dir/Caddyfile"

    # ── optionally kill tmux session ──
    if tmux has-session -t remote 2>/dev/null; then
        echo "Warning: tmux session 'remote' still exists."
        echo -n "Kill it? [y/N] "
        local ans
        read -r ans
        if [[ "$ans" =~ ^[Yy]$ ]]; then
            tmux kill-session -t remote
            stopped+=("tmux session 'remote'")
        else
            echo "Leaving tmux session 'remote' alive."
        fi
    fi

    # ── summary ──
    if (( ${#stopped[@]} )); then
        echo "Stopped: ${stopped[*]}"
    else
        echo "No remote-terminal services were running."
    fi
}
