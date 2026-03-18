#!/bin/bash
# Custom aliases and shortcuts
# Source this file in your .zshrc or .bashrc

# ─── KMac Shortcut ───────────────────────────────────────────────────────────
alias kmac='toolkit'

# ─── Basic Navigation ───────────────────────────────────────────────────────
alias ll="ls -l"
alias la="ls -la"
alias l="ls -CF"
alias ..="cd .."
alias ...="cd ../.."

# ─── Clear Screen ──────────────────────────────────────────────────────────
alias cls="clear"
alias c="clear"

# ─── Python ───────────────────────────────────────────────────────────────
alias py="python3"
alias pipi="pip install -r requirements.txt"
alias act="source venv/bin/activate"
alias mkvenv="python3 -m venv venv && source venv/bin/activate"

# ─── Git ──────────────────────────────────────────────────────────────────
alias gs="git status"
alias ga="git add ."
alias gc="git commit -m"
alias gp="git push"
alias gpl="git pull"
alias gl="git log --oneline --graph --decorate"

# ─── Docker ───────────────────────────────────────────────────────────────
alias dps="docker ps"
alias dcu="docker-compose up"
alias dcd="docker-compose down"
alias drm='docker rm $(docker ps -a -q)'
alias drmi='docker rmi $(docker images -q)'
alias dimg="docker images"

# ─── Networking ───────────────────────────────────────────────────────────
alias ip="ipconfig getifaddr en0"

# ─── Dev Servers ──────────────────────────────────────────────────────────
alias rserver="python -m http.server"
alias serve="python manage.py runserver"

# ─── VS Code ──────────────────────────────────────────────────────────────
alias code.="code ."

# ─── Better Tools ────────────────────────────────────────────────────────
alias cat="bat"

# ─── Docker Manager ───────────────────────────────────────────────────────
docker-mgr()    { "$(echo ~/Library/CloudStorage/iCloudDrive*/com~apple~CloudDocs/Scripts/toolkit/scripts/docker)" "$@"; }
alias docker-manager='docker-mgr'

# ─── AI Power Tools ───────────────────────────────────────────────────────
ask()        { "$(echo ~/Library/CloudStorage/iCloudDrive*/com~apple~CloudDocs/Scripts/toolkit/scripts/ask)" "$@"; }
review()     { "$(echo ~/Library/CloudStorage/iCloudDrive*/com~apple~CloudDocs/Scripts/toolkit/scripts/review)" "$@"; }
aicommit()   { "$(echo ~/Library/CloudStorage/iCloudDrive*/com~apple~CloudDocs/Scripts/toolkit/scripts/aicommit)" "$@"; }
sessions()   { "$(echo ~/Library/CloudStorage/iCloudDrive*/com~apple~CloudDocs/Scripts/toolkit/scripts/sessions)" "$@"; }
project()    { "$(echo ~/Library/CloudStorage/iCloudDrive*/com~apple~CloudDocs/Scripts/toolkit/scripts/project)" "$@"; }
cursoragent()  { "$(echo ~/Library/CloudStorage/iCloudDrive*/com~apple~CloudDocs/Scripts/toolkit/scripts/cursoragent)" "$@"; }

# ─── Utilities ────────────────────────────────────────────────────────────
storage()       { "$(echo ~/Library/CloudStorage/iCloudDrive*/com~apple~CloudDocs/Scripts/toolkit/scripts/storage)" "$@"; }
killport()      { "$(echo ~/Library/CloudStorage/iCloudDrive*/com~apple~CloudDocs/Scripts/toolkit/scripts/killport)" "$@"; }
pilot()         { "$(echo ~/Library/CloudStorage/iCloudDrive*/com~apple~CloudDocs/Scripts/toolkit/scripts/pilot)" "$@"; }
dotbackup()     { "$(echo ~/Library/CloudStorage/iCloudDrive*/com~apple~CloudDocs/Scripts/toolkit/scripts/dotbackup)" "$@"; }
update-check()  { "$(echo ~/Library/CloudStorage/iCloudDrive*/com~apple~CloudDocs/Scripts/toolkit/scripts/update-check)" "$@"; }
