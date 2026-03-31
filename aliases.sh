#!/bin/bash
# Custom aliases and shortcuts
# Source this file in your .zshrc or .bashrc

# ─── Resolve Toolkit Path ────────────────────────────────────────────────
# Works whether installed via iCloud, git clone, or local copy
_KMAC_ALIAS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-${(%):-%x}}")" 2>/dev/null && pwd)"
_KMAC_SCRIPTS="${_KMAC_ALIAS_DIR}/scripts"

# ─── KMac Shortcut ───────────────────────────────────────────────────────
alias kmac='toolkit'

# ─── Basic Navigation ────────────────────────────────────────────────────
alias ll="ls -l"
alias la="ls -la"
alias l="ls -CF"
alias ..="cd .."
alias ...="cd ../.."

# ─── Clear Screen ────────────────────────────────────────────────────────
alias cls="clear"
alias c="clear"

# ─── Python ──────────────────────────────────────────────────────────────
alias py="python3"
alias pipi="pip install -r requirements.txt"
alias act="source venv/bin/activate"
alias mkvenv="python3 -m venv venv && source venv/bin/activate"

# ─── Git ─────────────────────────────────────────────────────────────────
alias gs="git status"
alias ga="git add ."
alias gc="git commit -m"
alias gp="git push"
alias gpl="git pull"
alias gl="git log --oneline --graph --decorate"

# ─── Docker ──────────────────────────────────────────────────────────────
alias dps="docker ps"
alias dcu="docker-compose up"
alias dcd="docker-compose down"
function drm  { local ids; ids=$(docker ps -a -q); [[ -z "$ids" ]] || echo "$ids" | xargs docker rm --; }
function drmi { local ids; ids=$(docker images -q); [[ -z "$ids" ]] || echo "$ids" | xargs docker rmi --; }
alias dimg="docker images"

# ─── Networking ──────────────────────────────────────────────────────────
alias ip="ipconfig getifaddr en0"

# ─── Dev Servers ─────────────────────────────────────────────────────────
alias rserver="python3 -m http.server"
alias serve="python manage.py runserver"

# ─── VS Code ─────────────────────────────────────────────────────────────
alias code.="code ."

# ─── Better Tools ────────────────────────────────────────────────────────
command -v bat &>/dev/null && alias cat="bat"

# ─── KMac Tools (portable — no hardcoded paths) ─────────────────────────
docker-mgr()    { bash "$_KMAC_SCRIPTS/docker" "$@"; }
alias docker-manager='docker-mgr'

ask()            { bash "$_KMAC_SCRIPTS/ask" "$@"; }
review()         { bash "$_KMAC_SCRIPTS/review" "$@"; }
aicommit()       { bash "$_KMAC_SCRIPTS/aicommit" "$@"; }
sessions()       { bash "$_KMAC_SCRIPTS/sessions" "$@"; }
project()        { bash "$_KMAC_SCRIPTS/project" "$@"; }
cursoragent()    { bash "$_KMAC_SCRIPTS/cursoragent" "$@"; }

# ─── Utilities ───────────────────────────────────────────────────────────
storage()        { bash "$_KMAC_SCRIPTS/storage" "$@"; }
killport()       { bash "$_KMAC_SCRIPTS/killport" "$@"; }
pilot()          { bash "$_KMAC_SCRIPTS/pilot" "$@"; }
dotbackup()      { bash "$_KMAC_SCRIPTS/dotbackup" "$@"; }
update-check()   { bash "$_KMAC_SCRIPTS/update-check" "$@"; }
