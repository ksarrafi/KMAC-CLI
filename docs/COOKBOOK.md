# KMac Cookbook — How to Do Common Things

**Task-focused recipes. "I want to do X" → here's how.**

---

## Asking Claude Questions

### Ask a quick question

```bash
kmac ask "why is my CPU high?"
```

Claude analyzes your system and responds.

### Ask a follow-up

```bash
kmac ask
# System prompt loaded
❯ what's using the most memory?
❯ how do I reduce that?
❯ can I do it safely?
❯ exit
```

### Pass code or logs to Claude

```bash
# Ask about code
cat myfile.py | kmac ask "fix the bug"

# Ask about logs
tail -100 /var/log/system.log | kmac ask "what's wrong?"

# Ask about git diff
git diff | kmac ask "is this change safe?"
```

### Use a specific model

```bash
# For hard questions, use Opus (deeper reasoning)
kmac ask -m opus "design a cache layer"

# For quick answers, use Haiku (faster, cheaper)
kmac ask -m haiku "what's the weather?"
```

---

## Code Review & Commits

### Review your staged changes

```bash
# Review everything you're about to commit
kmac review

# See AI feedback, then decide to commit or revise
```

### Quick review (surface-level)

```bash
kmac review --quick
# Faster; finds obvious issues only
```

### Thorough PR-ready review

```bash
kmac review --strict
# Takes longer; checks for performance, security, maintainability
```

### Review specific commits

```bash
# Review last 3 commits
kmac review HEAD~3..HEAD

# Review since main branch
kmac review main..HEAD
```

### Generate commit message

```bash
# Stage your changes
git add .

# Generate conventional commit message with scope
kmac aicommit
# Output: "feat(auth): add token refresh with 24h expiry"

# Approve, edit, or abort
```

---

## Docker Management

### Check Docker status

```bash
kmac docker health
# Shows running containers, health, resource usage
```

### See recent container crashes

```bash
kmac docker crashes
# Shows containers that exited recently (useful for debugging)
```

### Clean up Docker (safe)

```bash
kmac docker cleanup
# Removes dangling images + stopped containers
# Never touches volumes (your data is safe)
```

### Check Docker disk usage

```bash
kmac docker disk
# Shows how much space Docker is using
```

---

## File & Disk Management

### Analyze disk usage

```bash
kmac storage scan
# Shows what's using the most space

kmac storage big
# List largest files and folders
```

### Clean up safely

```bash
# Preview what will be deleted
kmac houseclean inspect

# Actually delete (caches, Docker prune, etc.)
kmac houseclean run

# See what changed
kmac houseclean status
```

### Migrate old files to iCloud

```bash
# If you're running out of local space:
kmac storage icloud
# Moves old files to iCloud Drive (keeps shortcuts locally)
```

### Backup your dotfiles

```bash
# Backup to iCloud
kmac dotbackup

# See what changed since last backup
kmac dotbackup diff

# Restore on a new Mac
kmac dotbackup restore
```

---

## Secrets & API Keys

### Store an API key safely

```bash
# Set Claude API key
kmac vault set anthropic sk-ant-...

# Set GitHub token
kmac vault set github ghp_...

# Set any credential
kmac vault set myservice mytoken
```

### Retrieve a secret

```bash
# Get from vault
kmac vault get anthropic

# Use in script
export ANTHROPIC_API_KEY=$(kmac vault get anthropic)
```

### See what's configured

```bash
kmac vault list
# Shows all configured secrets (values redacted)
```

### Switch vault backend

```bash
# Current backend
kmac vault backend

# Switch to Keychain
kmac vault backend keychain

# Switch to encrypted file
kmac vault backend file

# Switch to Docker container
kmac vault backend docker
```

---

## System Health & Monitoring

### Quick health check

```bash
kmac ?
# Shows CPU, memory, disk, uptime, battery
```

### Detailed diagnostic

```bash
kmac doctor
# Checks dependencies, vault, paths, git status
# Shows what's working and what needs attention
```

### Monitor in background

```bash
# Start background watcher (daemon)
kmac monitor daemon install

# Check current status
kmac monitor status

# View alerts
kmac monitor logs
```

### Check for updates

```bash
kmac update
# Shows available KMac updates
# Offers to install automatically
```

---

## Project Management

### Launch a project

```bash
# Interactive picker
kmac project

# Jump straight to a project
kmac project MyProject
```

### Open project in Claude Code

```bash
# Pick project, then open in Claude Code
kmac project
# Then select "open in Claude" option
```

### List all projects

```bash
kmac project list
```

---

## Network & Connectivity

### Check IP addresses and network

```bash
kmac network
# Shows local IP, public IP, Wi-Fi SSID, listening ports
```

### Find what's using a port

```bash
# Find and kill process on port 3000
kmac killport 3000

# List all listening ports
kmac killport
```

### Test remote access

```bash
# Start remote terminal
kmac server start

# Get tunnel URL
kmac server status

# Access from another machine
# Use the ngrok URL + auth credentials
```

---

## Software & Tools Installation

### Install developer tools

```bash
# Interactive installer
kmac software

# Install specific tool
kmac software install node
kmac software install python
kmac software install gh
```

### List installed tools

```bash
kmac software list
```

### Search for available tools

```bash
kmac software search docker
```

---

## Advanced: Autonomous Experiments

### Start a research project

```bash
# Create a new experiment
kmac research init

# AI modifies code iteratively
kmac research run

# See what it's doing
kmac research status

# Review all iterations
kmac research review
```

---

## Advanced: AI Commit Messages

### Generate commit with hint

```bash
git add .

# Give AI context
kmac aicommit -m "refactor database queries"

# AI generates: "refactor: optimize database queries with batch operations"
```

### Amend previous commit

```bash
kmac aicommit --amend
# Regenerates message for last commit
```

---

## Advanced: Cursor Agent

### Quick task from command line

```bash
kmac cursor-agent "add error handling to server.js"
# Cursor runs the task autonomously
```

### Interactive prompt

```bash
kmac cursor-agent
# Prompts you for the task
```

---

## Troubleshooting Common Issues

### "Command not found: kmac"

```bash
# Reload your shell
source ~/.zshrc

# Or manually add to PATH
export PATH="$PATH:$HOME/.local/bin"
```

### "API key not configured"

```bash
# Set your Claude API key
kmac vault set anthropic sk-ant-your-key-here

# Or export in current session
export ANTHROPIC_API_KEY="sk-ant-your-key-here"
```

### "Docker is not running"

```bash
# Start Docker
open -a Docker

# Or check Docker status
kmac docker health
```

### "fzf not installed"

```bash
# Install fzf for faster help search
brew install fzf

# Now help will be searchable
kmac ?
```

### "Missing dependencies"

```bash
# Check what's missing
kmac doctor

# Or see all dependencies
kmac D  # Press D in menu
```

---

## Cheat Sheet: Most Common Commands

| Want to... | Command |
|-----------|---------|
| Ask Claude | `kmac ask "question"` |
| Review code | `kmac review` |
| Generate commit | `kmac aicommit` |
| Check health | `kmac ?` |
| Docker status | `kmac docker health` |
| Disk usage | `kmac storage scan` |
| Clean up | `kmac houseclean run` |
| Store secret | `kmac vault set key value` |
| Help | `kmac ?` (then press f for fast search) |

---

## Next Steps

- **Learn all commands:** See [Command Taxonomy](COMMAND_TAXONOMY.md)
- **Understand the architecture:** See [Platform Guide](PLATFORM_GUIDE.md)
- **Quick start:** See [First 5 Minutes](FIRST_5_MINUTES.md)
- **CLI details:** See [CLI Architecture](CLI_ARCHITECTURE.md)
- **Setup troubleshooting:** See [VAULT_GUIDE.md](VAULT_GUIDE.md)

---

**Have a common workflow not listed?** File an issue or PR to add it. 🚀
