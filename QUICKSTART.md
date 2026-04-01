# Quick Start

## Install (30 seconds)

```bash
# Via Homebrew (easiest)
brew tap ksarrafi/kmac
brew install kmac

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
| `a` | Ask Claude | `d` | Docker Manager |
| `A` | KmacAgent (tools) | `r` | Remote Terminal |
| `o` | Ollama (Local AI) | `P` | Pilot (remote) |
| `+` | AI Toolmaker | `n` | Network Info |
| `R` | Research (autorun) | `k` | Kill Port |
| `p` | Project Launcher | `S` | Storage Manager |
| `e` | Claude Code | `.` | Secrets & Keys |
| `x` | Cursor Agent | `u` | Check Updates |
| `v` | Code Review | `i` | Install / Bootstrap |
| `c` | Smart Commit | `I` | Software Manager |
| `?` | Health Check | `b` | Backup Dotfiles |
| `/` | Aliases | `0` | Exit |

**Plugins:** keys `1`–`7` when installed (e.g. System Cleanup, Wi‑Fi Password, Git Stats, Docker Notify, Git Guardian, Project Stats, Tmux Sessions).

**Ports:** Pilot API server **7890** (`kmac pilot server start` / `kmac server start`). KmacAgent dashboard **7891** by default (`kmac agent web`).

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
kmac agent start              # KmacAgent daemon (menu A)
kmac agent web                # Open agent dashboard (default :7891)
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
