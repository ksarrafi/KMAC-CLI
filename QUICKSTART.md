# Quick Start

## Install (30 seconds)

```bash
# From GitHub
git clone https://github.com/ksarrafi/RevestTech.git ~/Projects/KMac-CLI
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
| `v` | AI Code Review | `r` | Remote Terminal |
| `c` | AI Commit | `n` | Network Info |
| `+` | Build a Tool (AI) | `k` | Kill Port |
| `S` | Storage Manager | `.` | Secrets (Keychain) |
| `p` | Project Launcher | `b` | Backup Dotfiles |
| `e` | Claude Session | `u` | Check Updates |
| `x` | Cursor Agent | `?` | Health Check |
| `P` | Pilot Status | `B` | Bootstrap Mac |
| `s` | Sessions | `0` | Exit |

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

Press `.` in the menu, or manually:

```bash
security add-generic-password -s "toolkit-anthropic" -a "$USER" -w "your-key"
security add-generic-password -s "toolkit-openai" -a "$USER" -w "your-key"
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

API server:
```bash
cd server && python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
```
