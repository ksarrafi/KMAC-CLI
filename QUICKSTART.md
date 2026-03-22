# KMac-CLI — Quick Start

## Install

**From GitHub:**
```bash
git clone https://github.com/ksarrafi/RevestTech.git ~/Projects/KMac-CLI
cd ~/Projects/KMac-CLI
bash install.sh
source ~/.zshrc
```

**From iCloud Drive** (if you sync via iCloud):
```bash
bash $(echo ~/Library/CloudStorage/iCloudDrive*/com~apple~CloudDocs/Scripts/toolkit/install.sh)
source ~/.zshrc
```

## Launch

```bash
kmac             # Interactive menu (or: toolkit)
kmac help        # CLI usage
```

## Key Shortcuts (from the menu)

| Key | Action              | Key | Action              |
|-----|---------------------|-----|---------------------|
| `a` | Ask Claude          | `r` | Remote Terminal     |
| `v` | AI Code Review      | `d` | Docker Manager      |
| `c` | AI Commit           | `n` | Network Info        |
| `s` | Sessions            | `q` | Show QR Code        |
| `p` | Project Launcher    | `.` | Secrets (Keychain)  |
| `e` | Claude Session      | `b` | Backup Dotfiles     |
| `x` | Cursor Agent        | `u` | Check Updates       |
| `k` | Kill Port           | `?` | Health Check        |
| `S` | Storage Manager     | `+` | Build a Tool (AI)   |
| `B` | Bootstrap Mac       | `i` | Install/Update      |

## Quick CLI Commands

```bash
kmac ask "how do I ..."        # Ask Claude
kmac review                    # AI code review
kmac aicommit                  # AI commit message
kmac docker dashboard          # Docker health (Engine API)
kmac storage big               # Find large files with AI analysis
kmac make "build a ..."        # AI tool builder
kmac killport 3000             # Kill port
kmac pilot start               # Start Telegram bot
```

## KMac Pilot — Control AI from Your Phone

```bash
kmac pilot config              # Setup wizard (Telegram bot token, project dirs)
kmac pilot start               # Start Telegram bot daemon
kmac pilot server start        # Start API server (for iOS app)
kmac pilot status              # Check everything
```

### Telegram commands
```
/task <project> <prompt>       Start AI agent on a task
/ask <question>                Follow-up question
/status                        Check progress
/stop                          Stop agent
/projects                      List projects
/diff                          Git changes
/approve [msg]                 Commit
/reject                        Revert
```

### iOS App
```bash
cd ios/KMacPilot
xcodegen generate              # Requires: brew install xcodegen
open KMacPilot.xcodeproj       # Build & run in Xcode
```
Connect using the server URL and token from `kmac pilot server status`.

## Set Up Secrets

Press `.` in the menu, or:

```bash
security add-generic-password -s "toolkit-anthropic" -a "$USER" -w "your-key"
```

## Configuration

```bash
cp env.template env.sh         # Then edit with your settings
kmac pilot config              # Set up Telegram bot + project dirs
```
