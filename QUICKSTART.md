# Quick Start

## Install (30 seconds)

```bash
# Via Homebrew (easiest)
brew tap ksarrafi/tap https://github.com/ksarrafi/KMAC-CLI
brew install ksarrafi/tap/kmac

# From GitHub
git clone https://github.com/ksarrafi/KMAC-CLI.git ~/Projects/KMac-CLI
cd ~/Projects/KMac-CLI && bash install.sh && source ~/.zshrc

# Or from iCloud Drive
bash $(echo ~/Library/CloudStorage/iCloudDrive*/com~apple~CloudDocs/Scripts/toolkit/install.sh)
source ~/.zshrc
```

## Launch

```bash
kmac              # Interactive menu (animated intro on first launch)
kmac help         # All CLI commands
```

## Menu Shortcuts (single keypress — no Enter needed)

| Key | Action | Key | Action |
|-----|--------|-----|--------|
| `a` | Ask Claude | `r` | Remote Terminal |
| `+` | Build a Tool (AI) | `d` | Docker Manager |
| `p` | Project Launcher | `n` | Network Info |
| `e` | Claude Code | `k` | Kill Port |
| `x` | Cursor Agent | `S` | Storage Manager |
| `v` | Code Review | `b` | Backup Dotfiles |
| `c` | Smart Commit | `u` | Check Updates |
| `P` | Pilot (remote agent) | `.` | Secrets & Keys |
| `?` | Health Check | `q` | Connection QR |
| `B` | Bootstrap Mac | `i` | Install/Update |
| `o` | Ollama (Local AI) | `I` | Software Manager |

## Everyday Commands

```bash
kmac ask "explain kubernetes pod affinity"
git diff | kmac ask "review this"
kmac review --staged
kmac aicommit
kmac docker health
kmac docker web
kmac storage big
kmac make "a script that monitors SSL certs"
kmac killport 3000
kmac project
```

## Software Manager

```bash
kmac software                   # Interactive installer menu
kmac software list              # Show all tools with status
kmac software install claude    # Install a specific tool
kmac software update            # Update all installed tools
kmac software search docker     # Search the catalog
```

## Ollama (Local AI)

```bash
kmac ollama                     # Interactive menu
kmac ollama install             # Install + pull recommended model for your RAM
kmac ollama models              # Pull, remove, list models
kmac ollama chat                # Chat with an installed model
kmac ollama status              # Server + model status
kmac ollama serve               # Start the Ollama server
```

## Plugin Hooks

```bash
# Plugins can register for lifecycle events:
# TOOLKIT_HOOKS: post-commit,on-startup
# Available hooks: pre-commit, post-commit, pre-review, post-review,
#   on-error, on-startup, on-exit, pre-deploy, post-deploy,
#   session-start, session-end
```

## Run Tests

```bash
bash tests/run-tests.sh         # Run all 60 smoke tests
```

## Docker Health

```bash
kmac docker health              # Color-coded terminal report
kmac docker health --json       # JSON for scripts/APIs
kmac docker health --history    # 24h trend sparkline
kmac docker web                 # Open web dashboard in browser
kmac docker crashes             # Find OOM kills and crash analysis
kmac docker disk                # Storage breakdown + cleanup
```

## KMac Pilot (Remote Agent Control)

```bash
kmac pilot config               # Setup wizard (Telegram token, project dirs)
kmac pilot start                # Start Telegram bot daemon
kmac pilot server start         # Start API server for iOS app
kmac pilot status               # Check everything
```

**Telegram commands:**
```
/task my-project "add dark mode"    Start AI agent
/status                             Check progress
/diff                               Review git changes
/approve "looks good"               Commit
/projects                           Browse projects
/run ls -la                         Execute shell commands
```

**iOS App:**
```bash
cd ios/KMacPilot && xcodegen generate && open KMacPilot.xcodeproj
```

## Set Up Secrets

Press `.` in the menu, or use the CLI:

```bash
kmac secrets                    # Interactive credential manager
kmac secrets set anthropic      # Store your Anthropic API key
kmac secrets set openai         # Store your OpenAI key
kmac secrets backend            # Switch vault backend (Keychain / File / Docker)
```

## Configuration

```bash
cp env.template env.sh          # Edit with your settings
kmac pilot config               # Telegram bot + project directories
```

## Optional Dependencies

```bash
brew install bat fzf tmux ttyd ngrok caddy qrencode
```

## Server Deployment

```bash
# Quick start (local, no Docker)
kmac server start              # Start the Pilot API server
kmac server status             # Check health + PID
kmac server logs -f            # Follow server logs
kmac server token              # Show/copy auth token
kmac server stop               # Stop the server

# Install as auto-start service
kmac server install            # launchd on macOS, systemd on Linux

# Docker Compose (full stack: server + vault + Caddy TLS proxy)
kmac server docker-up          # Start all containers
kmac server docker-down        # Stop all containers
```

API server (manual):
```bash
cd server && python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
```
