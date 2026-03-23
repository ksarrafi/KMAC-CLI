# KMac-CLI

**Your Mac's command center — AI tools, Docker ops, and remote agent control in one keystroke.**

![macOS](https://img.shields.io/badge/macOS-13%2B-blue)
![Bash](https://img.shields.io/badge/Bash-3.2%2B-green)
![License](https://img.shields.io/badge/License-MIT-yellow)
![Docker](https://img.shields.io/badge/Docker-MCP%20Ready-2496ED)
![Python](https://img.shields.io/badge/Python-3.10%2B-3776AB)

---

KMac-CLI is a portable macOS toolkit that puts AI coding assistants, Docker infrastructure, storage management, and remote agent control behind a single interactive terminal menu — or as direct CLI commands. It's built entirely in Bash (3.2-compatible) with a Python API server and a native iOS companion app.

Type `kmac` and you get this:

```
    ██╗  ██╗ ███╗   ███╗  █████╗   ██████╗
    ██║ ██╔╝ ████╗ ████║ ██╔══██╗ ██╔════╝
    █████╔╝  ██╔████╔██║ ███████║ ██║
    ██╔═██╗  ██║╚██╔╝██║ ██╔══██║ ██║
    ██║  ██╗ ██║ ╚═╝ ██║ ██║  ██║ ╚██████╗
    ╚═╝  ╚═╝ ╚═╝     ╚═╝ ╚═╝  ╚═╝  ╚═════╝
        portable macOS toolkit                       v2.4.0

  ┌ services ──────────────────────────────────────────┐
  │  ● Remote Terminal   ● Docker (8)   ○ ngrok        │
  └────────────────────────────────────────────────────┘

    AI                        Dev                       Infra
    a  Ask Claude             p  Project Launcher       r  Remote Terminal
    +  Build a Tool           e  Claude Code            d  Docker Manager
                              x  Cursor Agent           n  Network Info
                              v  Code Review            k  Kill Port
                              c  Smart Commit
                              P  Pilot (remote agent)

    System
    S  Storage Manager        b  Backup Dotfiles        u  Check Updates
    .  Secrets & Keys         /  Show Aliases           i  Install/Update
    ?  Health Check           q  Connection QR          B  Bootstrap Mac

    0  Exit
```

Every key is one keypress — no Enter needed. Or skip the menu entirely and use CLI commands like `kmac ask "..."`, `kmac docker health`, or `kmac pilot start`.

## Install

```bash
# From GitHub
git clone https://github.com/ksarrafi/KMAC-CLI.git ~/Projects/KMac-CLI
cd ~/Projects/KMac-CLI && bash install.sh && source ~/.zshrc

# Or from iCloud Drive (for multi-Mac sync)
bash $(echo ~/Library/CloudStorage/iCloudDrive*/com~apple~CloudDocs/Scripts/toolkit/install.sh)
source ~/.zshrc
```

The installer auto-detects your setup (git clone vs iCloud), makes scripts executable, adds `kmac` and `toolkit` aliases, symlinks tools to `~/bin`, and optionally installs Homebrew dependencies.

## Features

### 1. AI-Powered Development

Tools that put Claude directly in your terminal workflow — from quick questions to full tool generation.

**Ask Claude** (`a` / `kmac ask`) — instant answers from the command line. Pipe in code, git diffs, logs, or files and get contextual analysis. Supports interactive multi-turn conversations and model switching between Sonnet, Opus, and Haiku.

```bash
kmac ask "explain kubernetes pod affinity"
git diff | kmac ask "what does this change do"
kmac ask -i                              # Multi-turn conversation
kmac ask -m opus "design a cache layer"  # Use a specific model
cat crash.log | kmac ask "why did this crash"
```

**AI Code Review** (`v` / `kmac review`) — sends your git diff to Claude for a structured code review. Supports staged-only, commit range, quick (surface-level), and strict (PR-ready thorough) modes. Detects the repo name, branch, and file count automatically.

```bash
kmac review                    # All uncommitted changes
kmac review --staged           # Only staged changes
kmac review HEAD~3..HEAD       # Specific commit range
kmac review --strict           # PR-ready detailed review
```

**AI Commit** (`c` / `kmac aicommit`) — generates conventional commit messages from staged changes. Analyzes the diff to detect scope (which module/feature changed), writes a message, and gives you an approve/edit/abort flow before committing. Supports `--amend` and hint text.

```bash
kmac aicommit                  # Stage all + generate + commit
kmac aicommit --staged         # Use current staging only
kmac aicommit -m "refactoring auth"  # Give AI context as a hint
kmac aicommit --amend          # Rewrite the last commit message
```

**AI Tool Builder** (`+` / `kmac make`) — describe a tool in plain English and AI builds a production-ready bash script. You iterate in a review loop — preview the code (syntax-highlighted with bat), tell AI what to change, test-run it, or open in your editor. When you're happy, it installs as either a plugin (with a menu key) or a script (with a CLI subcommand). Syntax-validated before install.

```bash
kmac make "a script that monitors SSL certificate expiry across domains"
kmac make "wifi password viewer that pulls from Keychain"
```

**AI Self-Healing** — built into every tool. When a command fails, KMac catches the error output, sends it to Claude with context about what was attempted, and presents a suggested fix command. Handles shell environments like nvm and rvm automatically. You choose to apply the fix, retry, or skip.

---

### 2. Docker Management

A full Docker operations center that connects directly to the Docker Engine API via unix socket — no CLI output parsing, no polling. Nine tools covering monitoring, crash analysis, cleanup, and AI-assisted troubleshooting.

**Health Dashboard** (`kmac docker dashboard`) — live view of every running container with CPU%, memory usage, network I/O, health check status, and uptime. Shows Docker engine version, host CPU/RAM, and color-coded CPU alerts (yellow >50%, red >80%).

**Health Report** (`kmac docker health`) — a focused status report with color-coded thresholds for disk and memory pressure. Outputs a progress bar for host disk, a per-container table, Docker disk breakdown (images, volumes, build cache), alerts section, and clickable port links for web-facing containers.

```bash
kmac docker health               # Terminal report with color coding
kmac docker health --json        # Structured JSON for APIs and automation
kmac docker health --history     # 24h trend data with ASCII sparkline chart
```

| Status | Disk | Memory | Indicator |
|--------|------|--------|-----------|
| Healthy | <75% | <75% | 🟢 Green |
| Warning | 75-85% | 75-90% | 🟡 Yellow |
| Severe | 85-90% | — | 🟠 Orange |
| Critical | >90% | >90% (OOM risk) | 🔴 Red |

**Web Dashboard** (`kmac docker web`) — opens a dark-themed, mobile-responsive browser UI at `/docker-dashboard`. Status cards for running containers, disk usage, and alert count. Per-container table with health badges, CPU/memory gauges, and clickable port links. Docker disk pie chart. 60-minute trending graph (disk, CPU, memory) via Chart.js. One-click cleanup buttons with confirmation dialogs. Auto-refreshes every 10 seconds.

**Crash Detective** (`kmac docker crashes`) — inspects all exited containers via the Engine API. Categorizes each by exit code: OOM killed (exit 137), SIGKILL, SEGFAULT (139), application error (1), or clean exit (0). Shows the container name, image, exit timestamp, and a human-readable reason. Offers to view logs or restart.

**Disk Monitor** (`kmac docker disk`) — host disk bar graph, Docker resource table (`docker system df`), top 10 largest images sorted by size, volume details, and a count of reclaimable dangling images, unused volumes, and stopped containers with one-click prune.

**Compose Manager** (`kmac docker compose`) — lists active Docker Compose projects with status and config file paths. View logs, stop, restart, or start new projects from a compose file.

**MCP Toolkit** (`kmac docker mcp`) — integrates with Docker Desktop's Model Context Protocol. Search 300+ servers in the MCP catalog, browse categories, create and manage profiles, and connect AI clients (Cursor, Claude Desktop, VS Code). Includes AI-assisted troubleshooting that gathers Docker diagnostics and sends them to Claude for analysis.

**Quick Cleanup** (`kmac docker clean`) — interactive prune menu. Choose to clean stopped containers, unused images, unused volumes, build cache older than one week, or a full system prune. Each option explains what will be removed and asks for confirmation.

**Auto-Cleanup Scheduler** (`kmac docker scheduler`) — installs a cleanup script and schedules it via `crontab` for weekly (Sunday 2 AM) or daily (3 AM) execution. Logs results to `~/.docker-cleanup.log`. Shows current schedule status and last run timestamp.

---

### 3. Storage Manager

Disk space analysis, AI-powered file identification, and cleanup tools designed for macOS — with iCloud Drive integration for migrating large directories off local storage.

**Overview** (`kmac storage overview`) — disk usage bar graph with percentage, used/total/free space, and APFS purgeable space (macOS-specific reclaimable storage that the system manages automatically).

**Directory Scan** (`kmac storage scan`) — breaks down storage by major directories (Desktop, Downloads, Documents, Library, Projects, Applications, etc.) with animated progress spinners during scan. Displays size bars relative to the largest directory. Runs `du` in parallel with per-directory timeouts to handle large trees like `~/Library`.

**Big Files** (`kmac storage big`) — finds the largest files across your home directory and `~/.cursor`. Sends the file list to Claude Haiku for AI analysis — each file gets a plain-English description of what it is, a safety rating (SAFE TO DELETE / CAUTION / KEEP), and an actionable tip. Falls back to pattern-matching descriptions when offline. Presents numbered files for interactive actions: delete specific files (`d 1,3,5`), back up to iCloud and delete (`b 1,3,5`), or bulk-delete all SAFE files (`D`).

**Cleanup** (`kmac storage clean`) — one-click removal of common disk waste: Homebrew cache, npm cache, pip cache, Xcode derived data, macOS system logs, application caches, and `.DS_Store` files. Shows a real-time progress spinner with the current target being cleaned and bytes freed.

**iCloud Migration** (`kmac storage icloud`) — moves selected directories to iCloud Drive and creates symlinks in their original locations so apps continue to work transparently. Shows available iCloud storage before proceeding.

**Node Modules** (`kmac storage node`) — scans for `node_modules` directories with a spinner showing directories found. Lists each with size and last-modified date. Select which to delete.

---

### 4. KMac Pilot — Remote AI Agent Control

Run AI coding agents on your Mac and control them from anywhere — your phone, your couch, another machine. Three interfaces to the same backend: a Telegram bot, a REST/WebSocket API server, and a native iOS app.

**Telegram Bot** (`kmac pilot start`) — a long-polling daemon that connects to the Telegram Bot API. Full agent lifecycle management:

| Command | What it does |
|---------|-------------|
| `/task my-project "add dark mode"` | Start Claude Code or Cursor Agent on a task |
| `/ask "how should I handle auth?"` | Send a follow-up question to the running agent |
| `/status` | Check progress with elapsed time and output preview |
| `/stop` | Halt the current agent |
| `/diff` | Review git changes the agent made |
| `/approve "looks good"` | Commit the agent's work with a message |
| `/reject` | Revert all changes |
| `/projects` | Browse your project directories |
| `/tree my-project` | View file tree |
| `/cat my-project src/main.ts` | Read a file |
| `/run ls -la` | Execute a shell command on your Mac |
| `/agent cursor` | Switch between Claude Code and Cursor Agent |

Includes heartbeat streaming — periodic status updates with elapsed time and output preview so you can monitor progress without polling.

**API Server** (`kmac pilot server start`) — Python aiohttp backend running on port 7890 with auto-generated token auth. Provides REST endpoints for system info, project discovery, file browsing, git operations, Docker management, and shell execution. Multi-session agent management via PTY-based streaming — run multiple agents concurrently with real-time output over WebSocket. ANSI escape code stripping for clean terminal output. Command execution uses an allowlist + blocklist security model (blocks destructive commands like `rm -rf /`, `sudo`, fork bombs, and piping curl to shell).

**iOS App** (KMacPilot) — native SwiftUI companion built with XcodeGen. Connects to the API server and provides:
- Dashboard with system info, uptime, active agent, and session count
- Start tasks on any discovered project with Claude Code or Cursor Agent
- Live terminal output as agents work (WebSocket streaming with auto-scroll)
- File browser with syntax-highlighted code viewer
- Git status, diff viewer, commit and revert
- Shell command execution on remote Mac
- Docker container management
- Settings with persistent server credentials and auto-reconnect

```bash
brew install xcodegen
cd ios/KMacPilot && xcodegen generate && open KMacPilot.xcodeproj
```

---

### 5. Developer Workflow Tools

Everyday utilities that speed up common development tasks.

**Project Launcher** (`p` / `kmac project`) — fuzzy-find your projects with fzf, showing branch name and last commit timestamp. Pick a project, then choose an action: open in Claude Code, Cursor Agent, VS Code, Finder, or just `cd` into it. Works without fzf via a numbered menu fallback.

```bash
kmac project                   # Interactive picker
kmac project MyApp             # Go straight to a project
kmac project -c MyApp          # Open in Claude Code
kmac project -x MyApp          # Open with Cursor Agent
```

**Claude Code** (`e` / `kmac sessions`) — launch Claude Code on any project, or browse and resume past conversations. Lists recent sessions with timestamps. Resume the most recent, search by keyword, or pick from a list.

```bash
kmac sessions                  # Interactive picker
kmac sessions last             # Resume most recent
kmac sessions search "auth"    # Find by keyword
```

**Kill Port** (`k` / `kmac killport`) — find and kill processes listening on a port. Run with no args to list all listening ports with process name, PID, and command. Supports multiple ports and `--dry-run` to preview what would be killed.

```bash
kmac killport 3000             # Kill whatever's on port 3000
kmac killport 3000 8080        # Kill multiple ports
kmac killport --dry-run 3000   # Preview without killing
kmac killport                  # List all listening ports
```

**Remote Terminal** (`r`) — starts a browser-accessible terminal session on your Mac using ttyd, exposed through ngrok with Caddy as a TLS-terminating reverse proxy. Credentials are stored in macOS Keychain. Includes QR code generation for easy mobile access. Runs inside tmux so sessions survive disconnects.

**Network Info** (`n`) — displays local IP, public IP (via ifconfig.me), Wi-Fi SSID, default gateway, and a table of listening ports with process names.

---

### 6. Secrets & Integration Hub

A private credential vault that turns KMac into your personal command center — securely storing API keys for AI models, cloud providers, MCP servers, and any service you integrate with.

**Secrets & Keys** (`.` / `kmac secrets`) — a full-featured secret management system with three backends:

- **macOS Keychain** (default) — hardware-backed, OS-managed, unlocked by your login password. Secrets survive reboots and app reinstalls. The most secure option on macOS.
- **Encrypted File Vault** — AES-256-CBC encryption via `openssl` with PBKDF2 key derivation (100,000 iterations). Protected by a master password. Stored at `~/.config/kmac/vault.enc`. Portable — sync via iCloud, git, or USB to other machines.
- **Docker Vault** — a containerized, isolated key-value store. Runs a lightweight Python server inside a Docker container with data encrypted in a Docker volume (`kmac-vault-data`). Only listens on `127.0.0.1` — never exposed to the network. Portable — back up or migrate the volume to move between machines. Ideal for users who already run Docker and want OS-independent secret storage.

Secrets are *never* written as plaintext to disk or stored in environment files. All KMac tools look up credentials through the vault automatically.

```bash
kmac secrets                   # Interactive credential manager
kmac secrets list              # Show all integrations with status
kmac secrets set anthropic     # Store your Anthropic API key
kmac secrets set github        # Store a GitHub token
kmac secrets export            # Load all credentials into shell env
kmac secrets add               # Register a new custom integration
kmac secrets backend           # Switch between Keychain, encrypted file, and Docker vault
kmac secrets docker-start      # Start the Docker vault container
kmac secrets docker-stop       # Stop the Docker vault container
kmac secrets docker-status     # Check if Docker vault is running
```

**Pre-configured integrations** across 6 categories:

| Category | Integrations |
|----------|-------------|
| AI & LLMs | Anthropic (Claude), OpenAI, Google AI (Gemini), Groq |
| DevOps & Code | GitHub, GitLab, npm |
| Docker & Containers | Docker Hub |
| Infrastructure | ngrok, Remote Terminal, Telegram Bot, Pilot Server |
| Cloud & Hosting | AWS (access + secret key), Vercel, Supabase |
| Services & APIs | Slack webhook, Sentry DSN, SendGrid |

**Add your own** — register any API key, token, or secret as a custom integration:

```bash
kmac secrets add
# → Service name: my-saas-api
# → Category: [1-8]
# → Env variable: MY_SAAS_API_KEY
# → Description: My SaaS platform token
# → Paste value (hidden): ****
```

Custom integrations appear in the dashboard alongside built-in ones. They export to environment variables just like everything else, so any CLI tool or MCP server can pick them up.

**Docker Vault management** — the backend menu (option 5) provides lifecycle controls: start/stop the container, rebuild the image, backup the volume to a tarball (`~/kmac-vault-backup-*.tar.gz`), restore from a backup, or destroy everything. Volume backups are fully portable — move them to another machine, restore, and your secrets come with you.

**Backward compatible** — existing Keychain entries from older KMac versions are automatically migrated to the new naming scheme on first run.

**Dotfile Backup** (`b` / `kmac dotbackup`) — backs up `.zshrc`, `.gitconfig`, `.gitignore_global`, `.vimrc`, `.tmux.conf`, and Claude/Cursor agent configs to the toolkit's `dotfiles/` directory (which syncs via iCloud or git). Shows a diff preview before overwriting. Restore with safety `.bak` copies. The `hook` subcommand installs an auto-backup that runs every time you exit your shell.

```bash
kmac dotbackup                 # Backup with diff preview
kmac dotbackup restore         # Restore to a new Mac
kmac dotbackup diff            # Show what changed since last backup
kmac dotbackup hook            # Install auto-backup on shell exit
```

**Health Check** (`?` / `kmac doctor`) — verifies that all dependencies are installed (with version numbers), environment variables are set, Keychain entries exist, toolkit paths are valid, and shell integration is configured. Reports issue count with clear pass/fail indicators.

**Update Check** (`u` / `kmac update`) — checks for outdated Homebrew packages, npm globals (including Claude Code), and dotfile freshness. Animated spinner during version checks. Caches results for 4 hours to avoid redundant network calls. If a brew or npm update fails, offers AI-assisted diagnosis. Can actually run updates with `--update`.

**Bootstrap Mac** (`B`) — new-machine setup in one command. Export your current Brewfile (captures every brew, cask, and tap), install from a Brewfile on a fresh Mac, apply macOS preferences (Dock auto-hide, key repeat speed, Finder path bar, screenshot location), or run the full bootstrap (all of the above plus the toolkit installer).

**New Mac Setup** (`scripts/setup-mac`) — end-to-end bootstrap for a fresh Mac. Installs Homebrew, Oh My Zsh with plugins, runs the KMac installer, restores your backed-up dotfiles, installs Brewfile packages, and launches the vault guided setup for API keys — all in one script.

```bash
git clone https://github.com/ksarrafi/KMAC-CLI.git ~/Projects/KMac-CLI
bash ~/Projects/KMac-CLI/scripts/setup-mac
```

---

### 7. Plugin System & Extensibility

Extend the toolkit without touching core code. Drop an executable script into `plugins/` with three header comments and it appears in the interactive menu automatically:

```bash
#!/bin/bash
# TOOLKIT_NAME: SSL Monitor
# TOOLKIT_DESC: Check certificate expiry across domains
# TOOLKIT_KEY: 9

# your code here
```

- `TOOLKIT_NAME` — display name in the menu (required)
- `TOOLKIT_DESC` — one-line description shown next to the name
- `TOOLKIT_KEY` — single-character hotkey (validated against builtins to prevent collisions)

Plugins also work as CLI subcommands: `kmac ssl-monitor` will find and execute `plugins/ssl-monitor` or `plugins/ssl-monitor.sh`.

The AI Tool Builder (`kmac make`) generates plugins in this format automatically — describe what you want, iterate with AI, and it installs the result as a plugin with a menu key or as a script with a CLI subcommand.

Included plugins:
- **wifi-password** — show the current Wi-Fi network password from Keychain
- **cleanup** — free disk space by clearing caches, logs, Trash, and Docker resources

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  kmac (CLI)                                                     │
│  toolkit.sh → subcommand router OR interactive TUI menu         │
│                                                                 │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌───────────────┐  │
│  │ AI Tools │  │ Docker   │  │ Storage  │  │ Pilot         │  │
│  │ ask      │  │ docker   │  │ storage  │  │ _pilot-bot.sh │  │
│  │ review   │  │ docker-  │  │          │  │ _pilot-lib.sh │  │
│  │ aicommit │  │  health  │  │          │  │ pilot (CLI)   │  │
│  │ toolmaker│  │          │  │          │  │               │  │
│  └──────────┘  └──────────┘  └──────────┘  └───────┬───────┘  │
│       │              │             │                │          │
│  ┌────┴──────────────┴─────────────┴────────────────┴───────┐  │
│  │  _ui.sh  _vault.sh  _auth-helper.sh  _ai-fix.sh        │  │
│  └──────────────────────────────────────────────────────────┘  │
└────────────────────────────────────┬────────────────────────────┘
                                     │
┌────────────────────────────────────┴────────────────────────────┐
│  server/ (Python aiohttp)          port 7890                    │
│  app.py ─┬─ session_manager.py     PTY agent streaming          │
│          ├─ docker_ops.py          Container/image operations   │
│          ├─ docker_dashboard.py    Health API + web UI          │
│          ├─ projects.py            Deep git repo discovery      │
│          ├─ git_ops.py             Diff, approve, reject        │
│          ├─ system_ops.py          Disk, memory, processes      │
│          └─ static/                Web dashboards               │
└────────────────────────────────────┬────────────────────────────┘
                                     │
┌────────────────────────────────────┴────────────────────────────┐
│  ios/KMacPilot/ (SwiftUI)                                       │
│  Dashboard · Sessions · Terminal · Files · Git · Docker · Shell  │
└─────────────────────────────────────────────────────────────────┘
```

## Project Structure

```
KMac-CLI/
├── toolkit.sh              Main entry — interactive menu + subcommand router
├── install.sh              Idempotent installer (detects iCloud vs git clone)
├── aliases.sh              Shell aliases and functions (sourced by .zshrc)
├── env.template            Environment variable template
├── startup-hook.sh         Background update check on shell start
├── Brewfile                Homebrew package manifest for Bootstrap
├── VERSION                 Single source of truth for version
├── CHANGELOG.md
├── scripts/
│   ├── _ui.sh              Shared UI — colors, title_box, pause, spinners
│   ├── _vault.sh           Triple-backend secret vault (Keychain + AES-256 + Docker)
│   ├── _auth-helper.sh     Claude API auth (vault → env fallback)
│   ├── _ai-fix.sh          AI self-healing — catches errors, suggests fixes
│   ├── _pilot-lib.sh       Pilot shared constants and helpers
│   ├── _pilot-bot.sh       Telegram long-poll bot daemon
│   ├── pilot               Pilot CLI (start/stop/config/server/status)
│   ├── docker              Docker Manager — Engine API + MCP + Compose
│   ├── docker-health       Docker health report (--json, --history)
│   ├── storage             Storage Manager — disk analysis + AI + iCloud
│   ├── secrets             Credential manager + integration hub
│   ├── ask                 Ask Claude from the terminal
│   ├── review              AI code review on git diffs
│   ├── aicommit            AI commit message generator
│   ├── toolmaker           AI tool builder — describe → build → install
│   ├── sessions            Claude session browser and resume picker
│   ├── project             fzf project launcher with IDE integration
│   ├── killport            Kill process by port
│   ├── dotbackup           Dotfile backup/restore/diff to iCloud
│   ├── update-check        Outdated tool checker with AI error diagnosis
│   ├── claudeme            Claude Code session launcher
│   ├── cursoragent         Quick Cursor Agent tasks
│   ├── remote-terminal.sh  Browser-based terminal (ttyd + ngrok + caddy)
│   ├── setup-mac           New Mac bootstrap (Homebrew, Oh My Zsh, dotfiles, vault)
│   ├── release             Version bump, git tag, and GitHub Release creator
│   ├── aicoder             AICoder Enterprise Framework launcher (subagent support)
│   ├── install-aicoder     AICoder global installer
│   └── create-aicoder.sh   Create global 'aicoder' command
├── server/
│   ├── app.py              aiohttp REST + WebSocket — auth, routing, WS
│   ├── config.py           Token management, project dirs, host/port
│   ├── session_manager.py  Multi-agent PTY streaming with ANSI stripping
│   ├── agent_manager.py    Agent lifecycle and session coordination
│   ├── docker_ops.py       Container/image operations via Docker CLI
│   ├── docker_dashboard.py Health monitoring API + in-memory history
│   ├── projects.py         Deep git repo discovery (3 levels)
│   ├── git_ops.py          Diff stats, approve/reject, log helpers
│   ├── system_ops.py       Disk, memory, processes, network, services
│   ├── static/
│   │   └── docker-dashboard.html   Web health dashboard (Chart.js)
│   ├── vault/
│   │   ├── Dockerfile              Docker vault container image
│   │   └── vault_server.py         Encrypted key-value store (REST API)
│   └── requirements.txt
├── ios/KMacPilot/          Native SwiftUI iOS companion app
│   ├── project.yml         XcodeGen project spec
│   └── Sources/            App, models, services, views
├── plugins/                User plugins (auto-detected by menu)
└── dotfiles/               Backed-up dotfiles and Claude agent configs
```

## API Endpoints

The Python server exposes a REST + WebSocket API for the iOS app, web dashboards, and automation.

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/ping` | Health check (no auth) |
| GET | `/api/system` | Hostname, uptime, load, active agent |
| GET | `/api/projects` | List discovered git repositories |
| GET | `/api/files/tree` | File tree for a project |
| GET | `/api/git/diff` | Diff stats for active project |
| POST | `/api/git/approve` | Commit staged changes |
| GET | `/api/sessions` | List agent sessions |
| POST | `/api/sessions` | Start a new agent session |
| GET | `/api/sessions/{id}/output` | Stream session output |
| GET | `/api/docker/containers` | List all containers with stats |
| GET | `/api/docker/health` | Full health snapshot (containers, disk, alerts) |
| GET | `/api/docker/history?minutes=60` | Historical trending data |
| POST | `/api/docker/cleanup` | Prune operations (containers, images, volumes, cache, all) |
| GET | `/docker-dashboard` | Web health dashboard UI |
| POST | `/api/run` | Execute shell command (allowlisted) |
| WS | `/ws` | Real-time session output streaming |

All endpoints (except `/api/ping`, `/ws`, `/docker-dashboard`) require `Authorization: Bearer <token>`.

## Configuration

**Secrets** — via the interactive manager or CLI:
```bash
kmac secrets                    # Interactive menu (press '.' from toolkit)
kmac secrets set anthropic      # Set Anthropic key
kmac secrets set openai         # Set OpenAI key
kmac secrets add                # Register any custom API key
kmac secrets export             # Load all into current shell
kmac secrets backend            # Switch between Keychain, encrypted vault, or Docker
```

**Environment:**
```bash
cp env.template env.sh   # Edit with your settings (gitignored)
```

**Pilot setup:**
```bash
kmac pilot config        # Telegram bot token, project scan directories
```

## Dependencies

**Core** (ships with macOS): Bash 3.2+, Python 3, curl, security (Keychain)

**Recommended** (via Homebrew):
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

## Design Decisions

- **Bash 3.2** — macOS ships with Bash 3.2 (not 5+). No associative arrays, no namerefs, no `mapfile`. All scripts respect this constraint.
- **Triple-backend vault** — secrets are stored in macOS Keychain (hardware-backed), an AES-256-CBC encrypted file (portable), or a Docker container vault (isolated, volume-portable). The `_vault.sh` library provides a unified API (`vault_get`, `vault_set`) so scripts don't need to know which backend is active. Secrets never touch disk as plaintext. The Docker backend runs a lightweight Python REST server inside a container with data encrypted in a named volume — ideal for users who want OS-independent, containerized secret storage with volume backup/restore portability.
- **Docker Engine API** — direct unix socket calls via `curl --unix-socket` instead of parsing `docker` CLI output. Faster, more reliable, structured JSON.
- **No heavy dependencies** — the core toolkit needs nothing beyond what macOS provides. Optional tools enhance UX but aren't required.
- **Plugin protocol** — three comment headers in a script. That's it. No registration, no config files, no compilation.
- **Portable** — works from a git clone or synced from iCloud Drive. The installer detects which and configures paths accordingly.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on code style, adding tools, the plugin protocol, and submitting PRs.

## License

[MIT](LICENSE) — KMac-CLI Contributors
