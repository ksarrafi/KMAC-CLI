# KMac-CLI

A portable macOS development toolkit with AI tools, Docker management, and remote agent control.

![macOS](https://img.shields.io/badge/macOS-13%2B-blue)
![Bash](https://img.shields.io/badge/Bash-3.2%2B-green)
![License](https://img.shields.io/badge/License-MIT-yellow)
![Docker](https://img.shields.io/badge/Docker-MCP%20Ready-2496ED)

## Features

- **Interactive TUI** — animated intro, single-keypress navigation, live status dashboard
- **AI Tools** — ask Claude, AI code review, AI commit messages, AI tool builder
- **Docker Manager v3.0** — Engine API monitoring, MCP Toolkit, crash detective, auto-cleanup
- **Storage Manager** — disk analysis with AI-powered file categorization and cleanup
- **KMac Pilot** — control AI agents remotely via Telegram bot or iOS app
- **Plugin System** — drop scripts into `plugins/` and they appear in the menu
- **Secrets Manager** — API keys stored in macOS Keychain, never in plaintext
- **Portable** — lives in iCloud Drive for multi-Mac sync, or install from git clone

## Quick Start

### From GitHub

```bash
git clone https://github.com/ksarrafi/RevestTech.git ~/Projects/KMac-CLI
cd ~/Projects/KMac-CLI
bash install.sh
source ~/.zshrc
kmac
```

### From iCloud Drive

```bash
bash $(echo ~/Library/CloudStorage/iCloudDrive*/com~apple~CloudDocs/Scripts/toolkit/install.sh)
source ~/.zshrc
kmac
```

The installer detects whether you're running from a git clone or iCloud and configures paths accordingly. It will:
- Make all scripts executable
- Add `toolkit` and `kmac` aliases to your shell
- Symlink tools to `~/bin`
- Optionally install Homebrew dependencies
- Create `env.sh` from template

## What's Inside

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
    S  Storage Manager        .  Secrets (Keychain)       b  Backup Dotfiles
    ?  Health Check           /  Show Aliases             u  Check Updates
    B  Bootstrap Mac          +  Build a Tool (AI)        i  Install/Update
```

Plus KMac Pilot for remote AI agent control and a full plugin system.

## CLI Commands

```bash
kmac                          # Interactive menu
kmac ask "question"           # Ask Claude (-i for interactive, -m opus for model)
kmac review [--strict]        # AI code review (--quick, --staged)
kmac aicommit                 # AI commit message with scope detection
kmac docker dashboard         # Docker health dashboard (Engine API)
kmac docker mcp               # Docker MCP Toolkit (catalog, profiles)
kmac storage big              # Find large files with AI analysis
kmac storage clean            # Clean caches and build artifacts
kmac pilot start              # Start Telegram bot daemon
kmac pilot server start       # Start API server for iOS app
kmac make "description"       # Build a new tool with AI
kmac sessions                 # Resume a Claude session
kmac project                  # Project launcher with fzf
kmac killport [port]          # Kill process on port
kmac dotbackup                # Backup/restore dotfiles
kmac doctor                   # Health check
kmac help                     # Show all commands
```

## AI Tools

**Ask Claude** — instant answers from the terminal. Supports piped input, model switching, and interactive conversations.

```bash
kmac ask "how do I reverse a list in python"
git diff | kmac ask "explain this change"
kmac ask -i                    # Interactive conversation
kmac ask -m opus "hard question"
```

**AI Code Review** — reviews your git diff with Claude and gives actionable feedback.

**AI Commit** — generates conventional commit messages from staged changes with scope detection.

**AI Tool Builder** — describe what you want in plain English, AI builds a production bash script, iterates with you, and installs it as a plugin or script.

## Docker Manager

Docker Manager v3.0 connects directly to the Docker Engine API via unix socket for real-time monitoring, and integrates with the Docker MCP Toolkit for AI-assisted management.

| Feature | Description |
|---------|-------------|
| Health Dashboard | Live CPU%, memory, network I/O, health checks per container |
| Crash Detective | Find OOM kills (exit 137), segfaults, application errors with log viewing |
| Disk Monitor | Image sizes, volume usage, reclaimable space with one-click cleanup |
| MCP Toolkit | Search 300+ MCP catalog servers, manage profiles, connect AI clients |
| AI Troubleshoot | Gathers diagnostics, sends to Claude for analysis and recommendations |
| Auto-Cleanup | Install a weekly/daily crontab prune with logging |
| Compose Manager | List, start, stop, restart, view logs for Compose projects |

Access via `kmac docker [dashboard|crashes|disk|mcp|clean|scheduler|compose]` or press `d` in the menu.

## Storage Manager

Scans your home directory for disk usage, finds large files, categorizes them with AI, and lets you delete or back up to iCloud.

| Feature | Description |
|---------|-------------|
| Overview | Disk usage bar, APFS purgeable space |
| Directory Scan | Size breakdown of major directories with bar graphs |
| Big Files | AI-categorized large files with safety ratings (SAFE/CAUTION/KEEP) |
| Cleanup | One-click removal of caches, logs, build artifacts |
| iCloud Migration | Move directories to iCloud Drive with symlink preservation |
| Node Modules | Find and clean stale `node_modules` directories |

Access via `kmac storage [overview|scan|big|clean|icloud|node]` or press `S` in the menu.

## KMac Pilot — Remote AI Control

Control AI coding agents (Claude Code, Cursor) from your phone.

**Telegram Bot** — start tasks, monitor progress, review diffs, approve/reject changes:
```
/task my-project "add dark mode"    Start AI agent
/status                             Check progress
/diff                               Review changes
/approve "looks good"               Commit
```

**API Server** — REST + WebSocket backend for the iOS app:
```bash
kmac pilot server start             # Port 7890, token-based auth
```

**iOS App** — native SwiftUI app with dashboard, live terminal streaming, file browser, git operations.

```bash
cd ios/KMacPilot && xcodegen generate && open KMacPilot.xcodeproj
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

Plugins appear automatically in the menu. Keys are validated to prevent collisions.

## Project Structure

```
KMac-CLI/
├── toolkit.sh                # Main interactive menu + subcommand router
├── install.sh                # Idempotent installer (iCloud + git clone)
├── aliases.sh                # Shell aliases (sourced by .zshrc)
├── env.template              # Environment variables template
├── startup-hook.sh           # Background update check on shell start
├── Brewfile                  # Homebrew package manifest
├── VERSION                   # Single source of truth for version
├── CHANGELOG.md
├── scripts/
│   ├── _ui.sh                # Shared UI (colors, title_box, pause, spinners)
│   ├── _auth-helper.sh       # Claude API auth (Keychain + env fallback)
│   ├── _ai-fix.sh            # AI self-healing engine
│   ├── _pilot-lib.sh         # Pilot shared library
│   ├── _pilot-bot.sh         # Pilot Telegram bot daemon
│   ├── pilot                 # Pilot CLI (start/stop/config/server)
│   ├── docker                # Docker Manager (Engine API + MCP)
│   ├── storage               # Storage Manager (disk analysis + AI)
│   ├── ask                   # Ask Claude from the terminal
│   ├── review                # AI code review
│   ├── aicommit              # AI commit messages
│   ├── toolmaker             # AI tool builder
│   ├── sessions              # Claude session browser
│   ├── project               # fzf project launcher
│   ├── killport              # Kill process by port
│   ├── dotbackup             # Dotfile backup/restore
│   └── remote-terminal.sh    # Remote terminal (ttyd + ngrok + caddy)
├── server/                   # Python API server for Pilot
│   ├── app.py                # aiohttp REST + WebSocket
│   ├── config.py             # Auth token, project dirs
│   ├── session_manager.py    # Multi-agent PTY streaming
│   └── requirements.txt
├── ios/KMacPilot/            # Native SwiftUI iOS app
├── plugins/                  # User plugins (auto-detected)
└── dotfiles/                 # Backed-up dotfiles + Claude agents
```

## Configuration

**Secrets** — stored in macOS Keychain via the menu (`.` key) or manually:
```bash
security add-generic-password -s "toolkit-anthropic" -a "$USER" -w "sk-ant-..."
security add-generic-password -s "toolkit-openai" -a "$USER" -w "sk-..."
```

**Environment** — copy the template and edit:
```bash
cp env.template env.sh    # Then add your settings
```

**Pilot** — run the setup wizard:
```bash
kmac pilot config         # Telegram bot token, project directories
```

## Dependencies

**Core** (included on macOS): bash 3.2+, python3, curl

**Optional** (install via Homebrew):
```bash
brew install bat fzf tmux ttyd ngrok caddy qrencode
```

**API Server:**
```bash
cd server && python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
```

**iOS App:**
```bash
brew install xcodegen
cd ios/KMacPilot && xcodegen generate && open KMacPilot.xcodeproj
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on adding tools, plugins, and submitting PRs.

## License

[MIT](LICENSE) — KMac-CLI Contributors
