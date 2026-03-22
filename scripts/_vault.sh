#!/bin/bash
# _vault.sh — unified secret management with triple backends
# Source this in any script: source "$SCRIPT_DIR/_vault.sh"
#
# Backends:
#   1. macOS Keychain (primary) — hardware-backed, OS-managed
#   2. Encrypted file vault     — AES-256, portable, syncable
#   3. Docker vault             — containerized, isolated, portable volume
#
# API:
#   vault_get  <service>              → prints secret value
#   vault_set  <service> <value>      → stores secret
#   vault_del  <service>              → removes secret
#   vault_list                        → prints all service names
#   vault_has  <service>              → returns 0 if exists
#   vault_export <service>            → exports as env var
#   vault_export_all                  → exports all known mappings

VAULT_DIR="${KMAC_VAULT_DIR:-$HOME/.config/kmac}"
VAULT_FILE="$VAULT_DIR/vault.enc"
VAULT_REGISTRY="$VAULT_DIR/integrations.json"
VAULT_BACKEND="${KMAC_VAULT_BACKEND:-auto}"  # auto | keychain | file | docker

# ─── Backend Detection ───────────────────────────────────────────────────

_vault_backend() {
    case "$VAULT_BACKEND" in
        keychain) echo "keychain" ;;
        file)     echo "file" ;;
        docker)   echo "docker" ;;
        auto)
            if security help &>/dev/null 2>&1; then
                echo "keychain"
            else
                echo "file"
            fi
            ;;
    esac
}

# ─── Keychain Backend ────────────────────────────────────────────────────

_kc_prefix="kmac"

_kc_get() {
    security find-generic-password -s "${_kc_prefix}-${1}" -w 2>/dev/null
}

_kc_set() {
    local svc="${_kc_prefix}-${1}" val="$2"
    security add-generic-password -U -s "$svc" -a "$USER" -w "$val" 2>/dev/null \
        || security add-generic-password -s "$svc" -a "$USER" -w "$val" 2>/dev/null
}

_kc_del() {
    security delete-generic-password -s "${_kc_prefix}-${1}" 2>/dev/null
}

_kc_has() {
    security find-generic-password -s "${_kc_prefix}-${1}" -w &>/dev/null
}

_kc_list() {
    security dump-keychain 2>/dev/null \
        | grep -o "\"svce\"<blob>=\"${_kc_prefix}-[^\"]*\"" \
        | sed "s/\"svce\"<blob>=\"${_kc_prefix}-//;s/\"//" \
        | sort -u
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
    plain=$(openssl enc -d -aes-256-cbc -pbkdf2 -iter 100000 \
        -in "$VAULT_FILE" -pass "pass:${_vault_master_password}" 2>/dev/null)
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
    echo "$json" | openssl enc -aes-256-cbc -pbkdf2 -iter 100000 \
        -out "$VAULT_FILE" -pass "pass:${_vault_master_password}" 2>/dev/null
}

_file_get() {
    local json
    json=$(_vault_decrypt) || return 1
    echo "$json" | python3 -c "
import sys,json
d = json.load(sys.stdin)
v = d.get('$1','')
if v: print(v)
else: sys.exit(1)
" 2>/dev/null
}

_file_set() {
    local svc="$1" val="$2"
    local json
    if [[ -f "$VAULT_FILE" ]]; then
        json=$(_vault_decrypt) || return 1
    else
        json="{}"
    fi
    json=$(echo "$json" | python3 -c "
import sys,json
d = json.load(sys.stdin)
d['$svc'] = '''$val'''
print(json.dumps(d))
" 2>/dev/null) || return 1
    _vault_encrypt "$json"
}

_file_del() {
    local json
    json=$(_vault_decrypt) || return 1
    json=$(echo "$json" | python3 -c "
import sys,json
d = json.load(sys.stdin)
d.pop('$1', None)
print(json.dumps(d))
" 2>/dev/null) || return 1
    _vault_encrypt "$json"
}

_file_has() {
    local json
    json=$(_vault_decrypt) || return 1
    echo "$json" | python3 -c "
import sys,json
d = json.load(sys.stdin)
sys.exit(0 if '$1' in d and d['$1'] else 1)
" 2>/dev/null
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
        -H "Authorization: Bearer $(_docker_vault_token)" 2>/dev/null)
    [[ $? -ne 0 ]] && return 1
    echo "$resp" | python3 -c "import sys,json; print(json.load(sys.stdin).get('value',''))" 2>/dev/null
}

_docker_set() {
    docker_vault_start || return 1
    curl -sf -X POST "$(_docker_vault_url)/set" \
        -H "Authorization: Bearer $(_docker_vault_token)" \
        -H "Content-Type: application/json" \
        -d "{\"key\":\"$1\",\"value\":\"$2\"}" >/dev/null 2>&1
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
        -H "Authorization: Bearer $(_docker_vault_token)" 2>/dev/null)
    [[ $? -ne 0 ]] && return 1
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
        -H "Authorization: Bearer $(_docker_vault_token)" 2>/dev/null)
    [[ $? -ne 0 ]] && return 0
    echo "$resp" | python3 -c "
import sys,json
for k in json.load(sys.stdin).get('keys',[]):
    print(k)
" 2>/dev/null
}

# ─── Unified API ─────────────────────────────────────────────────────────

vault_get() {
    local backend
    backend=$(_vault_backend)
    case "$backend" in
        keychain) _kc_get "$1" ;;
        file)     _file_get "$1" ;;
        docker)   _docker_get "$1" ;;
    esac
}

vault_set() {
    local backend
    backend=$(_vault_backend)
    case "$backend" in
        keychain) _kc_set "$1" "$2" ;;
        file)     _file_set "$1" "$2" ;;
        docker)   _docker_set "$1" "$2" ;;
    esac
}

vault_del() {
    local backend
    backend=$(_vault_backend)
    case "$backend" in
        keychain) _kc_del "$1" ;;
        file)     _file_del "$1" ;;
        docker)   _docker_del "$1" ;;
    esac
}

vault_has() {
    local backend
    backend=$(_vault_backend)
    case "$backend" in
        keychain) _kc_has "$1" ;;
        file)     _file_has "$1" ;;
        docker)   _docker_has "$1" ;;
    esac
}

vault_list() {
    local backend
    backend=$(_vault_backend)
    case "$backend" in
        keychain) _kc_list ;;
        file)     _file_list ;;
        docker)   _docker_list ;;
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
    python3 -c "
import json
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
with open('$VAULT_REGISTRY', 'w') as f:
    json.dump(registry, f, indent=2)
" 2>/dev/null
}

_vault_load_registry() {
    $_REG_LOADED && return
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
    done < <(python3 -c "
import json
with open('$VAULT_REGISTRY') as f:
    for r in json.load(f):
        print(f\"{r['service']}|{r['category']}|{r['env']}|{r['desc']}\")
" 2>/dev/null)
    _REG_LOADED=true
}

vault_add_integration() {
    local svc="$1" cat="$2" env="$3" desc="$4"
    _vault_init_registry
    python3 -c "
import json
with open('$VAULT_REGISTRY') as f:
    reg = json.load(f)
reg = [r for r in reg if r['service'] != '$svc']
reg.append({'service': '$svc', 'category': '$cat', 'env': '$env', 'desc': '$desc'})
with open('$VAULT_REGISTRY', 'w') as f:
    json.dump(reg, f, indent=2)
" 2>/dev/null
    _REG_LOADED=false
}

vault_remove_integration() {
    local svc="$1"
    python3 -c "
import json
with open('$VAULT_REGISTRY') as f:
    reg = json.load(f)
reg = [r for r in reg if r['service'] != '$svc']
with open('$VAULT_REGISTRY', 'w') as f:
    json.dump(reg, f, indent=2)
" 2>/dev/null
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
            val=$(security find-generic-password -s "$old" -w 2>/dev/null)
            if [[ -n "$val" ]]; then
                vault_set "$new" "$val"
                ((migrated++))
            fi
        fi
    done
    (( migrated > 0 )) && echo -e "  ${DIM}Migrated $migrated legacy key(s) to new vault${NC}" >&2
}
