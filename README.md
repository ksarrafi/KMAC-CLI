# KMac-CLI — Portable macOS Toolkit

A comprehensive, portable development toolkit that lives in iCloud Drive and can be installed on any Mac with a single command. AI-powered tools, remote AI agent control from your phone, a native iOS app, plugin system, dotfile backup, and a beautiful interactive TUI.

## Features

- **Portable**: Lives in iCloud Drive, syncs across all your Macs
- **Interactive TUI**: Color-coded menu with single-keypress navigation and status dashboard
- **AI Power Tools**: Ask Claude, AI code review, AI commits, AI tool builder
- **KMac Pilot**: Control AI agents (Claude Code, Cursor) remotely from Telegram or the iOS app
- **iOS App**: Native SwiftUI app for remote project management, agent sessions, file browsing
- **API Server**: Python (aiohttp) backend with REST + WebSocket for real-time agent streaming
- **AI Self-Healing**: Tools auto-detect failures and offer AI-powered diagnosis
- **Plugin System**: Drop scripts into `plugins/` with header metadata
- **Secrets Manager**: Store API keys in macOS Keychain — never in plaintext
- **Mac Bootstrap**: Brewfile export/import, macOS preferences, full setup

## Installation

```bash
bash $(echo ~/Library/CloudStorage/iCloudDrive*/com~apple~CloudDocs/Scripts/toolkit/install.sh)
```

The installer will:
- Verify iCloud Drive access
- Make all scripts executable
- Add `toolkit` and `kmac` aliases to `.zshrc` and `.bashrc`
- Symlink scripts (including `kmac`) to `~/bin`
- Install Homebrew dependencies (optional)
- Create `env.sh` from template

After installation:
```bash
source ~/.zshrc
kmac            # or: toolkit
```

## KMac Pilot — Remote AI Agent Control

Pilot lets you start and monitor AI coding agents from your phone. It has three interfaces:

### Telegram Bot
```bash
pilot config           # Setup wizard (bot token, project dirs)
pilot start            # Start the Telegram bot daemon
pilot status           # Check bot + agent + server status
```

Telegram commands:
```
/task <project> <prompt>     Start an AI agent on a task
/ask <question>              Follow-up question
/status                      Check agent progress
/stop                        Stop the running agent
/agent [claude|cursor]       View/switch AI agent
/projects [filter]           List projects
/tree [subdir]               Directory tree
/cat <file>                  View a file
/run <command>               Run a shell command
/log                         Agent output
/diff                        Git changes
/approve [msg]               Commit changes
/reject                      Revert changes
```

### API Server (for iOS app)
```bash
pilot server start     # Start the REST + WebSocket server on port 7890
pilot server stop      # Stop the server
pilot server status    # Show server URL + auth token
```

The server provides:
- REST API for projects, files, git, Docker, sessions, system info
- WebSocket for real-time agent output streaming
- Token-based auth (auto-generated on first run)
- Multi-session agent management with PTY-based real-time output

### iOS App (KMacPilot)
Native SwiftUI app that connects to the API server. Features:
- Dashboard with system info and active sessions
- Start AI tasks on any project with Claude Code or Cursor Agent
- Live-streaming terminal output as agents work
- File browser with syntax-highlighted code viewer
- Git status, diff, commit/revert from your phone
- Shell command execution
- Docker container management

Build with Xcode:
```bash
cd ios/KMacPilot
xcodegen generate      # Requires xcodegen
open KMacPilot.xcodeproj
```

## Development Workflow

This repo is the **development copy**. The production copy lives in iCloud.

```bash
# Develop here in Cursor/VS Code
# When ready to deploy:
./deploy.sh --dry-run    # Preview changes
./deploy.sh              # Push to iCloud (syncs to all Macs)
```

## Interactive Menu

```
  ╭───────────────────────────────────────────────────────╮
  │  ⚡ TOOLKIT                                   v2.3.0  │
  ╰───────────────────────────────────────────────────────╯

    AI                         Dev                        Infra
    ────                       ─────                      ──────
    a  Ask Claude              p  Project Launcher        r  Remote Terminal
    v  AI Code Review          e  Claude Session          d  Docker Manager
    c  AI Commit               x  Cursor Agent            n  Network Info
    s  Sessions                k  Kill Port               q  Show QR Code

    System
    ────────
    .  Secrets (Keychain)      b  Backup Dotfiles         u  Check Updates
    ?  Health Check            /  Show Aliases             i  Install/Update
    B  Bootstrap Mac           +  Build a Tool (AI)
```

## CLI Subcommands

```bash
kmac                          # Interactive menu (alias for toolkit)
kmac ask "question"           # Ask Claude (-i interactive, -m opus)
kmac review [--strict]        # AI code review (--quick, --staged)
kmac aicommit [--amend]       # AI commit message with scope detection
kmac sessions                 # Resume a Claude session
kmac project                  # Project launcher with fzf
kmac cursoragent "task"       # Cursor Agent task (alias: cask)
kmac killport [port]          # Kill process on port
kmac dotbackup [cmd]          # Backup/restore/diff/hook dotfiles
kmac update                   # Check for updates
kmac doctor                   # Health check
kmac make "description"       # Build a new tool with AI
kmac pilot start              # Start Pilot Telegram bot
kmac pilot server start       # Start API server for iOS app
kmac version                  # Show version info
kmac whatsnew                 # Show latest changelog
kmac help                     # Show help
```

## Directory Structure

```
KMac-CLI/
├── toolkit.sh                # Main interactive menu + subcommand router
├── install.sh                # Idempotent installer
├── deploy.sh                 # Sync dev → iCloud production
├── aliases.sh                # Shell aliases (sourced by .zshrc)
├── env.template              # Environment variables template
├── env.sh                    # Local env (git-ignored, has your API keys)
├── startup-hook.sh           # Background update check on shell start
├── Brewfile                  # Homebrew package manifest
├── VERSION                   # Single source of truth for version
├── CHANGELOG.md              # Release notes
├── scripts/
│   ├── _ui.sh                # Shared UI helpers (colors, title_box, pause)
│   ├── _auth-helper.sh       # Claude API auth (Keychain + env fallback)
│   ├── _ai-fix.sh            # AI self-healing engine
│   ├── _pilot-lib.sh         # Pilot shared library (config, Telegram, projects)
│   ├── _pilot-bot.sh         # Pilot Telegram bot daemon
│   ├── pilot                 # Pilot CLI (start/stop/config/server)
│   ├── ask                   # Ask Claude from the terminal
│   ├── review                # AI code review on git diffs
│   ├── aicommit              # AI-generated commit messages
│   ├── sessions              # Claude session browser/resume
│   ├── project               # fzf project launcher
│   ├── cursoragent           # Cursor Agent tasks
│   ├── claudeme              # Claude Code session launcher
│   ├── killport              # Find/kill processes by port
│   ├── dotbackup             # Dotfile backup/restore/diff
│   ├── update-check          # Check for tool updates
│   ├── toolmaker             # AI-powered tool builder
│   ├── aicoder               # AICoder launcher
│   ├── create-aicoder.sh     # AICoder global installer
│   ├── install-aicoder       # Quick AICoder installer
│   └── remote-terminal.sh    # Remote terminal (ttyd + ngrok + caddy)
├── server/                   # Python API server for Pilot
│   ├── app.py                # aiohttp REST + WebSocket server
│   ├── config.py             # Config, auth token, project dirs
│   ├── session_manager.py    # Multi-agent session lifecycle + PTY streaming
│   ├── projects.py           # Project discovery + file browsing
│   ├── git_ops.py            # Git diff, approve, reject, log
│   ├── docker_ops.py         # Docker container/image management
│   ├── system_ops.py         # Disk, memory, processes, network, services
│   └── requirements.txt      # Python dependencies (aiohttp)
├── ios/                      # Native iOS app
│   └── KMacPilot/
│       ├── project.yml       # XcodeGen project spec
│       └── KMacPilot/
│           ├── KMacPilotApp.swift
│           ├── Models/       # Data models (Session, Project, etc.)
│           ├── Services/     # APIClient, AppState, WebSocketClient
│           └── Views/        # SwiftUI views (Dashboard, Sessions, etc.)
├── plugins/
│   ├── cleanup.sh            # System cleanup (caches, logs, Docker)
│   └── wifi-password.sh      # Show current Wi-Fi password
└── dotfiles/                 # Backed-up dotfiles
    ├── .gitconfig
    ├── .zshrc                # (git-ignored — contains local config)
    └── claude/               # Claude Code agent configs
```

## Plugin System

Create a plugin by adding an executable script to `plugins/`:

```bash
#!/bin/bash
# TOOLKIT_NAME: My Plugin
# TOOLKIT_DESC: What it does in one line
# TOOLKIT_KEY: 3

echo "Hello from my plugin!"
```

Plugins appear automatically in the menu. Keys are validated against built-in shortcuts to prevent collisions.

## Secrets Management

API keys are stored in macOS Keychain, not in files:

```bash
# From the menu: press '.' → Add/update
# Or manually:
security add-generic-password -s "toolkit-openai" -a "$USER" -w "sk-..."
security add-generic-password -s "toolkit-anthropic" -a "$USER" -w "sk-..."
security add-generic-password -s "toolkit-rt-password" -a "$USER" -w "your-password"
```

## Dependencies

Install with Homebrew (the installer can do this automatically):

```bash
brew install ttyd ngrok caddy qrencode tmux bat fzf
```

For the API server:
```bash
cd server && python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
```

For the iOS app:
```bash
brew install xcodegen
cd ios/KMacPilot && xcodegen generate && open KMacPilot.xcodeproj
```

## License

A community-driven portable macOS toolkit.
