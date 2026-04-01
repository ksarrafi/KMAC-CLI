#!/bin/bash
# _vault.sh — unified secret management with multiple backends
# Source this in any script: source "$SCRIPT_DIR/_vault.sh"
#
# Backends:
#   1. macOS Keychain (primary) — hardware-backed, OS-managed
#   2. Encrypted file vault     — AES-256, portable, syncable
#   3. Docker vault             — containerized, isolated, portable volume
#   4. Remote vault             — hosted on Railway/cloud, shared across machines
#
# API:
#   vault_get  <service>              → prints secret value
#   vault_set  <service> <value>      → stores secret
#   vault_del  <service>              → removes secret
#   vault_list                        → prints all service names
#   vault_has  <service>              → returns 0 if exists
#   vault_export <service>            → exports as env var
#   vault_export_all                  → exports all known mappings

_VAULT_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=_platform.sh
[[ -z "${KMAC_PLATFORM_LOADED:-}" ]] && source "$_VAULT_SCRIPT_DIR/_platform.sh"

VAULT_DIR="${KMAC_VAULT_DIR:-$HOME/.config/kmac}"
VAULT_FILE="$VAULT_DIR/vault.enc"
VAULT_REGISTRY="$VAULT_DIR/integrations.json"
VAULT_BACKEND="${KMAC_VAULT_BACKEND:-auto}"  # auto | keychain | file | docker | remote

# ─── Backend Detection ───────────────────────────────────────────────────

_vault_backend() {
    case "$VAULT_BACKEND" in
        keychain) echo "keychain" ;;
        file)     echo "file" ;;
        docker)   echo "docker" ;;
        remote)   echo "remote" ;;
        auto)
            case "${KMAC_OS:-}" in
                macos)
                    if security help &>/dev/null 2>&1; then
                        echo "keychain"
                    else
                        echo "file"
                    fi
                    ;;
                linux)
                    if command -v secret-tool &>/dev/null; then
                        echo "keychain"
                    else
                        echo "file"
                    fi
                    ;;
                *)
                    echo "file"
                    ;;
            esac
            ;;
    esac
}

# ─── Keychain Backend ────────────────────────────────────────────────────

_kc_prefix="kmac"

_kc_get() {
    platform_keychain_get "${_kc_prefix}-${1}"
}

_kc_set() {
    local svc="${_kc_prefix}-${1}" val="$2"
    platform_keychain_set "$svc" "$val"
}

_kc_del() {
    platform_keychain_del "${_kc_prefix}-${1}"
}

_kc_has() {
    local svc="${_kc_prefix}-${1}"
    if [[ "${KMAC_OS:-}" == macos ]]; then
        security find-generic-password -s "$svc" -w &>/dev/null
        return $?
    fi
    command -v secret-tool &>/dev/null && secret-tool lookup service "$svc" account "$USER" &>/dev/null
}

_kc_list_linux_libsecret() {
    _KMAC_KC_PFX="$_kc_prefix" python3 <<'PY' 2>/dev/null
import os, sys
pfx = os.environ.get("_KMAC_KC_PFX", "kmac")
user = os.environ.get("USER", "")
try:
    import dbus
except ImportError:
    sys.exit(0)
try:
    bus = dbus.SessionBus()
    secrets = bus.get_object("org.freedesktop.secrets", "/org/freedesktop/secrets")
    serv = dbus.Interface(secrets, "org.freedesktop.Secret.Service")
    coll_path = serv.ReadAlias("default")
    coll = bus.get_object("org.freedesktop.secrets", coll_path)
    props = dbus.Interface(coll, dbus.PROPERTIES_IFACE)
    item_paths = props.Get("org.freedesktop.Secret.Collection", "Items")
    out = set()
    pre = pfx + "-"
    for path in item_paths:
        item = bus.get_object("org.freedesktop.secrets", path)
        iprops = dbus.Interface(item, dbus.PROPERTIES_IFACE)
        try:
            attrs = iprops.Get("org.freedesktop.Secret.Item", "Attributes")
        except dbus.exceptions.DBusException:
            continue
        if attrs.get("account") != user:
            continue
        s = attrs.get("service", "")
        if s.startswith(pre):
            out.add(s[len(pre):])
    for k in sorted(out):
        print(k)
except Exception:
    sys.exit(0)
PY
}

_kc_list() {
    if [[ "${KMAC_OS:-}" == macos ]]; then
        security dump-keychain 2>/dev/null \
            | grep -o "\"svce\"<blob>=\"${_kc_prefix}-[^\"]*\"" \
            | sed "s/\"svce\"<blob>=\"${_kc_prefix}-//;s/\"//" \
            | sort -u
        return
    fi
    if [[ "${KMAC_OS:-}" == linux ]] && command -v secret-tool &>/dev/null; then
        _kc_list_linux_libsecret
    fi
}

# ─── Encrypted File Backend ─────────────────────────────────────────────
# Uses openssl AES-256-CBC with PBKDF2. The vault is a JSON object:
# {"service_name": "secret_value", ...}
# Encrypted at rest, decrypted into a shell variable, never to disk.

_vault_master_password="" # cached for session

_vault_get_master() {
    if [[ -n "$_vault_master_password" ]]; then
        return 0
    fi
    if [[ -n "${KMAC_VAULT_PASSWORD:-}" ]]; then
        _vault_master_password="$KMAC_VAULT_PASSWORD"
        return 0
    fi
    echo "" >&2
    read -r -s -p "  Vault password: " _vault_master_password >&2
    echo "" >&2
    if [[ -z "$_vault_master_password" ]]; then
        return 1
    fi
}

_vault_decrypt() {
    [[ -f "$VAULT_FILE" ]] || { echo "{}"; return; }
    _vault_get_master || return 1
    local plain
    plain=$(printf '%s' "$_vault_master_password" | openssl enc -d -aes-256-cbc -pbkdf2 -iter 100000 \
        -in "$VAULT_FILE" -pass stdin 2>/dev/null)
    if [[ $? -ne 0 || -z "$plain" ]]; then
        echo "" >&2
        echo "  Wrong password or corrupted vault." >&2
        _vault_master_password=""
        return 1
    fi
    echo "$plain"
}

_vault_encrypt() {
    local json="$1"
    _vault_get_master || return 1
    mkdir -p "$VAULT_DIR"
    KMAC_VAULT_PASS="$_vault_master_password" openssl enc -aes-256-cbc -pbkdf2 -iter 100000 \
        -out "$VAULT_FILE" -pass env:KMAC_VAULT_PASS <<< "$json" 2>/dev/null
    chmod 600 "$VAULT_FILE" 2>/dev/null || true
}

_file_get() {
    local json name="$1"
    json=$(_vault_decrypt) || return 1
    KMAC_VAULT_NAME="$name" python3 -c "
import os, sys, json
name = os.environ['KMAC_VAULT_NAME']
d = json.load(sys.stdin)
v = d.get(name, '')
if v:
    print(v)
else:
    sys.exit(1)
" <<< "$json" 2>/dev/null
}

_file_set() {
    local svc="$1" val="$2"
    local json
    if [[ -f "$VAULT_FILE" ]]; then
        json=$(_vault_decrypt) || return 1
    else
        json="{}"
    fi
    json=$(KMAC_VAULT_NAME="$svc" KMAC_VAULT_VAL="$val" python3 -c "
import os, json, sys
name = os.environ['KMAC_VAULT_NAME']
val = os.environ['KMAC_VAULT_VAL']
d = json.load(sys.stdin)
d[name] = val
print(json.dumps(d))
" <<< "$json" 2>/dev/null) || return 1
    _vault_encrypt "$json"
}

_file_del() {
    local json name="$1"
    json=$(_vault_decrypt) || return 1
    json=$(KMAC_VAULT_NAME="$name" python3 -c "
import os, json, sys
name = os.environ['KMAC_VAULT_NAME']
d = json.load(sys.stdin)
d.pop(name, None)
print(json.dumps(d))
" <<< "$json" 2>/dev/null) || return 1
    _vault_encrypt "$json"
}

_file_has() {
    local json name="$1"
    json=$(_vault_decrypt) || return 1
    KMAC_VAULT_NAME="$name" python3 -c "
import os, sys, json
name = os.environ['KMAC_VAULT_NAME']
d = json.load(sys.stdin)
sys.exit(0 if name in d and d[name] else 1)
" <<< "$json" 2>/dev/null
}

_file_list() {
    local json
    json=$(_vault_decrypt) || return 0
    echo "$json" | python3 -c "
import sys,json
d = json.load(sys.stdin)
for k in sorted(d.keys()):
    if d[k]: print(k)
" 2>/dev/null
}

# ─── Docker Vault Backend ────────────────────────────────────────────────
# Talks to a containerized key-value store via REST on 127.0.0.1.
# Container: kmac-vault  |  Volume: kmac-vault-data  |  Port: 9999

VAULT_DOCKER_PORT="${KMAC_VAULT_DOCKER_PORT:-9999}"
VAULT_DOCKER_TOKEN_FILE="$VAULT_DIR/docker-vault-token"
VAULT_DOCKER_CONTAINER="kmac-vault"
VAULT_DOCKER_VOLUME="kmac-vault-data"
VAULT_DOCKER_IMAGE="kmac-vault:latest"

_docker_vault_url() {
    echo "http://127.0.0.1:${VAULT_DOCKER_PORT}"
}

_docker_vault_token() {
    if [[ -f "$VAULT_DOCKER_TOKEN_FILE" ]]; then
        cat "$VAULT_DOCKER_TOKEN_FILE"
    else
        echo ""
    fi
}

_docker_vault_running() {
    docker inspect -f '{{.State.Running}}' "$VAULT_DOCKER_CONTAINER" 2>/dev/null | grep -q "true"
}

docker_vault_start() {
    if _docker_vault_running; then
        return 0
    fi
    mkdir -p "$VAULT_DIR"
    if [[ ! -f "$VAULT_DOCKER_TOKEN_FILE" ]]; then
        openssl rand -base64 32 | tr -d '\n' > "$VAULT_DOCKER_TOKEN_FILE"
        chmod 600 "$VAULT_DOCKER_TOKEN_FILE"
    fi
    # Build image if it doesn't exist
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    local vault_ctx="${script_dir}/../server/vault"
    if ! docker image inspect "$VAULT_DOCKER_IMAGE" &>/dev/null; then
        echo "  Building Docker vault image..." >&2
        docker build -t "$VAULT_DOCKER_IMAGE" "$vault_ctx" >/dev/null 2>&1 || {
            echo "  Failed to build vault image." >&2
            return 1
        }
    fi
    docker run -d \
        --name "$VAULT_DOCKER_CONTAINER" \
        --restart unless-stopped \
        -p "127.0.0.1:${VAULT_DOCKER_PORT}:9999" \
        -v "${VAULT_DOCKER_VOLUME}:/vault/data" \
        -v "${VAULT_DOCKER_TOKEN_FILE}:/vault/token:ro" \
        "$VAULT_DOCKER_IMAGE" >/dev/null 2>&1 || {
        # Container might exist but be stopped
        docker start "$VAULT_DOCKER_CONTAINER" >/dev/null 2>&1 || return 1
    }
    # Wait for it to become healthy
    local i
    for i in 1 2 3 4 5; do
        sleep 0.5
        curl -sf "$(_docker_vault_url)/health" >/dev/null 2>&1 && return 0
    done
    echo "  Docker vault failed to start." >&2
    return 1
}

docker_vault_stop() {
    docker stop "$VAULT_DOCKER_CONTAINER" >/dev/null 2>&1
}

docker_vault_destroy() {
    docker rm -f "$VAULT_DOCKER_CONTAINER" >/dev/null 2>&1
    docker volume rm "$VAULT_DOCKER_VOLUME" >/dev/null 2>&1
}

_docker_get() {
    docker_vault_start || return 1
    local resp
    resp=$(curl -sf "$(_docker_vault_url)/get/$1" \
        -H "Authorization: Bearer $(_docker_vault_token)" 2>/dev/null) || return 1
    echo "$resp" | python3 -c "import sys,json; print(json.load(sys.stdin).get('value',''))" 2>/dev/null
}

_docker_set() {
    docker_vault_start || return 1
    local json
    json=$(python3 -c "import json,sys; print(json.dumps({'key':sys.argv[1],'value':sys.argv[2]}))" "$1" "$2")
    curl -sf -X POST "$(_docker_vault_url)/set" \
        -H "Authorization: Bearer $(_docker_vault_token)" \
        -H "Content-Type: application/json" \
        -d "$json" >/dev/null 2>&1
}

_docker_del() {
    docker_vault_start || return 1
    curl -sf -X POST "$(_docker_vault_url)/delete/$1" \
        -H "Authorization: Bearer $(_docker_vault_token)" >/dev/null 2>&1
}

_docker_has() {
    docker_vault_start || return 1
    local resp
    resp=$(curl -sf "$(_docker_vault_url)/has/$1" \
        -H "Authorization: Bearer $(_docker_vault_token)" 2>/dev/null) || return 1
    echo "$resp" | python3 -c "
import sys,json
d = json.load(sys.stdin)
sys.exit(0 if d.get('exists') else 1)
" 2>/dev/null
}

_docker_list() {
    docker_vault_start || return 0
    local resp
    resp=$(curl -sf "$(_docker_vault_url)/list" \
        -H "Authorization: Bearer $(_docker_vault_token)" 2>/dev/null) || return 0
    echo "$resp" | python3 -c "
import sys,json
for k in json.load(sys.stdin).get('keys',[]):
    print(k)
" 2>/dev/null
}

# ─── Remote Vault Backend ─────────────────────────────────────────────────
# Talks to a hosted KMac Vault Server (Railway, fly.io, VPS, etc.) via HTTPS.
# Config stored at ~/.config/kmac/remote-vault.json:
#   {"url": "https://vault-production-xxxx.up.railway.app", "token": "..."}
# Or via env vars: KMAC_VAULT_REMOTE_URL and KMAC_VAULT_REMOTE_TOKEN

VAULT_REMOTE_CONFIG="$VAULT_DIR/remote-vault.json"

_remote_vault_cfg() {
    local url="" token=""
    url="${KMAC_VAULT_REMOTE_URL:-}"
    token="${KMAC_VAULT_REMOTE_TOKEN:-}"
    if [[ -z "$url" && -f "$VAULT_REMOTE_CONFIG" ]]; then
        url=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('url',''))" "$VAULT_REMOTE_CONFIG" 2>/dev/null)
        token=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('token',''))" "$VAULT_REMOTE_CONFIG" 2>/dev/null)
    fi
    echo "${url}|${token}"
}

_remote_vault_url() {
    local cfg
    cfg=$(_remote_vault_cfg)
    echo "${cfg%%|*}"
}

_remote_vault_token() {
    local cfg
    cfg=$(_remote_vault_cfg)
    echo "${cfg#*|}"
}

_remote_vault_configured() {
    local url token
    url=$(_remote_vault_url)
    token=$(_remote_vault_token)
    [[ -n "$url" && -n "$token" ]]
}

_remote_get() {
    local url token
    url=$(_remote_vault_url)
    token=$(_remote_vault_token)
    local resp
    resp=$(curl -sf --max-time 10 "${url}/get/$1" \
        -H "Authorization: Bearer ${token}" 2>/dev/null) || return 1
    echo "$resp" | python3 -c "import sys,json; v=json.load(sys.stdin).get('value',''); print(v) if v else sys.exit(1)" 2>/dev/null
}

_remote_set() {
    local url token
    url=$(_remote_vault_url)
    token=$(_remote_vault_token)
    local json
    json=$(python3 -c "import json,sys; print(json.dumps({'key':sys.argv[1],'value':sys.argv[2]}))" "$1" "$2")
    curl -sf --max-time 10 -X POST "${url}/set" \
        -H "Authorization: Bearer ${token}" \
        -H "Content-Type: application/json" \
        -d "$json" >/dev/null 2>&1
}

_remote_del() {
    local url token
    url=$(_remote_vault_url)
    token=$(_remote_vault_token)
    curl -sf --max-time 10 -X POST "${url}/delete/$1" \
        -H "Authorization: Bearer ${token}" >/dev/null 2>&1
}

_remote_has() {
    local url token
    url=$(_remote_vault_url)
    token=$(_remote_vault_token)
    local resp
    resp=$(curl -sf --max-time 10 "${url}/has/$1" \
        -H "Authorization: Bearer ${token}" 2>/dev/null) || return 1
    echo "$resp" | python3 -c "import sys,json; sys.exit(0 if json.load(sys.stdin).get('exists') else 1)" 2>/dev/null
}

_remote_list() {
    local url token
    url=$(_remote_vault_url)
    token=$(_remote_vault_token)
    local resp
    resp=$(curl -sf --max-time 10 "${url}/list" \
        -H "Authorization: Bearer ${token}" 2>/dev/null) || return 0
    echo "$resp" | python3 -c "import sys,json
for k in json.load(sys.stdin).get('keys',[]):
    print(k)" 2>/dev/null
}

_remote_health() {
    local url token
    url=$(_remote_vault_url)
    token=$(_remote_vault_token)
    curl -sf --max-time 5 "${url}/health" >/dev/null 2>&1
}

remote_vault_setup() {
    echo ""
    echo -e "  ${BOLD}Remote Vault Setup${NC}"
    echo -e "  ${DIM}Connect to a hosted KMac Vault Server (Railway, fly.io, VPS, etc.)${NC}"
    echo ""
    echo -e "  ${BOLD}Deploy in 2 minutes:${NC}"
    echo -e "  ${DIM}1. Push server/vault/ to a Railway project${NC}"
    echo -e "  ${DIM}2. Set VAULT_TOKEN env var in Railway dashboard${NC}"
    echo -e "  ${DIM}3. Add a Railway volume mounted at /vault/data${NC}"
    echo -e "  ${DIM}4. Paste the Railway URL below${NC}"
    echo ""
    local existing_url
    existing_url=$(_remote_vault_url)
    if [[ -n "$existing_url" ]]; then
        echo -e "  ${DIM}Current: ${existing_url}${NC}"
        echo ""
    fi
    read -r -p "  Vault URL (e.g. https://vault-xxx.up.railway.app): " vault_url
    [[ -z "$vault_url" ]] && return 1
    vault_url="${vault_url%/}"

    read -r -s -p "  Vault token: " vault_token; echo ""
    [[ -z "$vault_token" ]] && return 1

    echo ""
    printf '  %s...%s Testing connection' "$CYAN" "$NC"
    if curl -sf --max-time 10 "${vault_url}/health" \
        -H "Authorization: Bearer ${vault_token}" >/dev/null 2>&1; then
        printf '\r  %s✓%s Connection successful     \n' "$GREEN" "$NC"
    else
        printf '\r  %s✗%s Could not reach vault     \n' "$RED" "$NC"
        echo -e "  ${DIM}Check the URL and token. The vault server must be running.${NC}"
        read -r -n1 -p "  Save anyway? (y/N) > " yn; echo ""
        [[ "$yn" != [yY] ]] && return 1
    fi

    mkdir -p "$VAULT_DIR"
    python3 -c "
import json,sys
with open(sys.argv[1],'w') as f:
    json.dump({'url':sys.argv[2],'token':sys.argv[3]},f,indent=2)
" "$VAULT_REMOTE_CONFIG" "$vault_url" "$vault_token"
    chmod 600 "$VAULT_REMOTE_CONFIG"
    echo -e "  ${GREEN}✓ Remote vault configured${NC}"
    echo -e "  ${DIM}Config: ${VAULT_REMOTE_CONFIG}${NC}"
}

# ── Vault Sync (push/pull between local and remote) ─────────────────────

vault_sync_push() {
    if ! _remote_vault_configured; then
        echo -e "  ${RED}Remote vault not configured. Run: kmac secrets backend → Remote${NC}" >&2
        return 1
    fi
    _vault_load_registry
    local pushed=0 skipped=0
    for (( i=0; i<${#_REG_SERVICES[@]}; i++ )); do
        local svc="${_REG_SERVICES[$i]}"
        local val
        val=$(vault_get "$svc" 2>/dev/null) || continue
        [[ -z "$val" ]] && continue
        if _remote_set "$svc" "$val" 2>/dev/null; then
            echo -e "  ${GREEN}↑${NC} ${svc}"
            ((pushed++))
        else
            echo -e "  ${RED}✗${NC} ${svc}"
            ((skipped++))
        fi
    done
    echo ""
    echo -e "  ${BOLD}Pushed ${pushed} secret(s)${NC}$( (( skipped > 0 )) && echo " ${RED}(${skipped} failed)${NC}" )"
}

vault_sync_pull() {
    if ! _remote_vault_configured; then
        echo -e "  ${RED}Remote vault not configured. Run: kmac secrets backend → Remote${NC}" >&2
        return 1
    fi
    _vault_load_registry
    local pulled=0 skipped=0
    for (( i=0; i<${#_REG_SERVICES[@]}; i++ )); do
        local svc="${_REG_SERVICES[$i]}"
        local val
        val=$(_remote_get "$svc" 2>/dev/null) || continue
        [[ -z "$val" ]] && continue
        if vault_set "$svc" "$val" 2>/dev/null; then
            echo -e "  ${GREEN}↓${NC} ${svc}"
            ((pulled++))
        else
            echo -e "  ${RED}✗${NC} ${svc}"
            ((skipped++))
        fi
    done
    echo ""
    echo -e "  ${BOLD}Pulled ${pulled} secret(s)${NC}$( (( skipped > 0 )) && echo " ${RED}(${skipped} failed)${NC}" )"
}

# ─── Unified API ─────────────────────────────────────────────────────────

vault_get() {
    local backend
    backend=$(_vault_backend)
    case "$backend" in
        keychain) _kc_get "$1" ;;
        file)     _file_get "$1" ;;
        docker)   _docker_get "$1" ;;
        remote)   _remote_get "$1" ;;
    esac
}

vault_set() {
    local backend
    backend=$(_vault_backend)
    case "$backend" in
        keychain) _kc_set "$1" "$2" ;;
        file)     _file_set "$1" "$2" ;;
        docker)   _docker_set "$1" "$2" ;;
        remote)   _remote_set "$1" "$2" ;;
    esac
}

vault_del() {
    local backend
    backend=$(_vault_backend)
    case "$backend" in
        keychain) _kc_del "$1" ;;
        file)     _file_del "$1" ;;
        docker)   _docker_del "$1" ;;
        remote)   _remote_del "$1" ;;
    esac
}

vault_has() {
    local backend
    backend=$(_vault_backend)
    case "$backend" in
        keychain) _kc_has "$1" ;;
        file)     _file_has "$1" ;;
        docker)   _docker_has "$1" ;;
        remote)   _remote_has "$1" ;;
    esac
}

vault_list() {
    local backend
    backend=$(_vault_backend)
    case "$backend" in
        keychain) _kc_list ;;
        file)     _file_list ;;
        docker)   _docker_list ;;
        remote)   _remote_list ;;
    esac
}

vault_export() {
    local svc="$1" envvar="$2"
    local val
    val=$(vault_get "$svc")
    if [[ -n "$val" ]]; then
        export "$envvar=$val"
        return 0
    fi
    return 1
}

vault_export_all() {
    _vault_load_registry
    local i
    for (( i=0; i<${#_REG_SERVICES[@]}; i++ )); do
        local svc="${_REG_SERVICES[$i]}"
        local envvar="${_REG_ENVVARS[$i]}"
        [[ -z "$envvar" ]] && continue
        local val
        val=$(vault_get "$svc" 2>/dev/null)
        [[ -n "$val" ]] && export "$envvar=$val"
    done
}

# ─── Integration Registry ───────────────────────────────────────────────
# JSON file that maps service names to metadata (category, env var, description).
# Not encrypted — contains no secrets, only the schema of what's stored.

_REG_SERVICES=()
_REG_CATEGORIES=()
_REG_ENVVARS=()
_REG_DESCS=()
_REG_LOADED=false

_vault_init_registry() {
    mkdir -p "$VAULT_DIR"
    [[ -f "$VAULT_REGISTRY" ]] && return
    KMAC_REG="$VAULT_REGISTRY" python3 <<'PYEOF' 2>/dev/null
import json, os
path = os.environ["KMAC_REG"]
registry = [
    {'service': 'anthropic',       'category': 'ai',      'env': 'ANTHROPIC_API_KEY',   'desc': 'Anthropic (Claude) API key'},
    {'service': 'openai',          'category': 'ai',      'env': 'OPENAI_API_KEY',      'desc': 'OpenAI API key'},
    {'service': 'google-ai',       'category': 'ai',      'env': 'GOOGLE_AI_API_KEY',   'desc': 'Google AI (Gemini) API key'},
    {'service': 'groq',            'category': 'ai',      'env': 'GROQ_API_KEY',        'desc': 'Groq inference API key'},
    {'service': 'github',          'category': 'devops',  'env': 'GITHUB_TOKEN',        'desc': 'GitHub personal access token'},
    {'service': 'gitlab',          'category': 'devops',  'env': 'GITLAB_TOKEN',        'desc': 'GitLab personal access token'},
    {'service': 'npm',             'category': 'devops',  'env': 'NPM_TOKEN',           'desc': 'npm publish token'},
    {'service': 'docker-hub',      'category': 'docker',  'env': 'DOCKER_HUB_TOKEN',    'desc': 'Docker Hub access token'},
    {'service': 'ngrok',           'category': 'infra',   'env': 'NGROK_AUTHTOKEN',     'desc': 'ngrok auth token'},
    {'service': 'rt-password',     'category': 'infra',   'env': 'RT_PASSWORD',         'desc': 'Remote Terminal password'},
    {'service': 'telegram-bot',    'category': 'infra',   'env': 'TELEGRAM_BOT_TOKEN',  'desc': 'Telegram Bot API token'},
    {'service': 'pilot-token',     'category': 'infra',   'env': 'KMAC_PILOT_TOKEN',    'desc': 'KMac Pilot server auth token'},
    {'service': 'aws-access-key',  'category': 'cloud',   'env': 'AWS_ACCESS_KEY_ID',   'desc': 'AWS access key ID'},
    {'service': 'aws-secret-key',  'category': 'cloud',   'env': 'AWS_SECRET_ACCESS_KEY','desc': 'AWS secret access key'},
    {'service': 'vercel',          'category': 'cloud',   'env': 'VERCEL_TOKEN',        'desc': 'Vercel deployment token'},
    {'service': 'supabase',        'category': 'cloud',   'env': 'SUPABASE_ACCESS_TOKEN','desc': 'Supabase management token'},
    {'service': 'slack-webhook',   'category': 'services','env': 'SLACK_WEBHOOK_URL',   'desc': 'Slack incoming webhook URL'},
    {'service': 'sentry-dsn',      'category': 'services','env': 'SENTRY_DSN',          'desc': 'Sentry error tracking DSN'},
    {'service': 'sendgrid',        'category': 'services','env': 'SENDGRID_API_KEY',    'desc': 'SendGrid email API key'},
]
with open(path, 'w') as f:
    json.dump(registry, f, indent=2)
PYEOF
    chmod 600 "$VAULT_REGISTRY" 2>/dev/null || true
}

_vault_load_registry() {
    [[ "$_REG_LOADED" == true ]] && return
    _vault_init_registry
    _REG_SERVICES=()
    _REG_CATEGORIES=()
    _REG_ENVVARS=()
    _REG_DESCS=()
    while IFS='|' read -r svc cat env desc; do
        _REG_SERVICES+=("$svc")
        _REG_CATEGORIES+=("$cat")
        _REG_ENVVARS+=("$env")
        _REG_DESCS+=("$desc")
    done < <(KMAC_REG="$VAULT_REGISTRY" python3 <<'PYEOF' 2>/dev/null
import json, os
with open(os.environ["KMAC_REG"]) as f:
    for r in json.load(f):
        print(f"{r['service']}|{r['category']}|{r['env']}|{r['desc']}")
PYEOF
)
    _REG_LOADED=true
}

vault_add_integration() {
    local svc="$1" cat="$2" env="$3" desc="$4"
    _vault_init_registry
    KMAC_REG="$VAULT_REGISTRY" KMAC_SVC="$svc" KMAC_CAT="$cat" KMAC_ENV="$env" KMAC_DESC="$desc" \
    python3 <<'PYEOF' 2>/dev/null
import json, os
path = os.environ["KMAC_REG"]
svc = os.environ["KMAC_SVC"]
cat = os.environ["KMAC_CAT"]
env = os.environ["KMAC_ENV"]
desc = os.environ["KMAC_DESC"]
with open(path) as f:
    reg = json.load(f)
reg = [r for r in reg if r["service"] != svc]
reg.append({"service": svc, "category": cat, "env": env, "desc": desc})
with open(path, "w") as f:
    json.dump(reg, f, indent=2)
PYEOF
    _REG_LOADED=false
}

vault_remove_integration() {
    local svc="$1"
    KMAC_REG="$VAULT_REGISTRY" KMAC_SVC="$svc" \
    python3 <<'PYEOF' 2>/dev/null
import json, os
path = os.environ["KMAC_REG"]
svc = os.environ["KMAC_SVC"]
with open(path) as f:
    reg = json.load(f)
reg = [r for r in reg if r["service"] != svc]
with open(path, "w") as f:
    json.dump(reg, f, indent=2)
PYEOF
    _REG_LOADED=false
    vault_del "$svc"
}

# ─── Migration: old Keychain names → new ─────────────────────────────────

_vault_migrate_legacy() {
    local -a legacy_map=(
        "toolkit-anthropic:anthropic"
        "toolkit-openai:openai"
        "toolkit-ngrok:ngrok"
        "toolkit-rt-password:rt-password"
    )
    local migrated=0
    for entry in "${legacy_map[@]}"; do
        local old="${entry%%:*}" new="${entry##*:}"
        if ! vault_has "$new" 2>/dev/null; then
            local val
            val=$(platform_keychain_get "$old" 2>/dev/null)
            if [[ -n "$val" ]]; then
                vault_set "$new" "$val"
                ((migrated++))
            fi
        fi
    done
    (( migrated > 0 )) && echo -e "  ${DIM}Migrated $migrated legacy key(s) to new vault${NC}" >&2
}
