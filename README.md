# KMac-CLI

**Your Mac's command center — AI tools, Docker ops, and remote agent control in one keystroke.**

![macOS](https://img.shields.io/badge/macOS-13%2B-blue)
![Linux](https://img.shields.io/badge/Linux-Ubuntu%20|%20Fedora%20|%20Arch-orange)
![Bash](https://img.shields.io/badge/Bash-3.2%2B-green)
![License](https://img.shields.io/badge/License-MIT-yellow)
![Docker](https://img.shields.io/badge/Docker-MCP%20Ready-2496ED)
![Python](https://img.shields.io/badge/Python-3.10%2B-3776AB)
![Tests](https://img.shields.io/badge/Tests-60%20passing-brightgreen)
![Homebrew](https://img.shields.io/badge/Homebrew-brew%20install%20kmac-FBB040)

---

KMac-CLI is a portable macOS & Linux toolkit that puts AI coding assistants, Docker infrastructure, storage management, and remote agent control behind a single interactive terminal menu — or as direct CLI commands. It's built entirely in Bash (3.2-compatible) with a Python API server and a native iOS companion app. Install via Homebrew with `brew tap ksarrafi/kmac && brew install kmac`, or clone from GitHub as below.

### Quick Start
- **New to KMac?** Start here → [**Your First 5 Minutes**](docs/FIRST_5_MINUTES.md) (5-min walkthrough)
- **Which tool to use?** → [**Platform Guide**](docs/PLATFORM_GUIDE.md) (CLI vs menu vs app)
- **How do I do X?** → [**Cookbook**](docs/COOKBOOK.md) (task-focused recipes)
- **Looking for a command?** → [**Command Taxonomy**](docs/COMMAND_TAXONOMY.md) (by category or task)
- **Confused about two CLIs?** → [**CLI Architecture**](docs/CLI_ARCHITECTURE.md) (Bash vs Swift; which to use)
- **Want everything?** → Continue below for full feature list

Type `kmac` and you get this:

```
    ██╗  ██╗ ███╗   ███╗  █████╗   ██████╗
    ██║ ██╔╝ ████╗ ████║ ██╔══██╗ ██╔════╝
    █████╔╝  ██╔████╔██║ ███████║ ██║
    ██╔═██╗  ██║╚██╔╝██║ ██╔══██║ ██║
    ██║  ██╗ ██║ ╚═╝ ██║ ██║  ██║ ╚██████╗
    ╚═╝  ╚═╝ ╚═╝     ╚═╝ ╚═╝  ╚═╝  ╚═════╝
        portable macOS toolkit                       v2.9.0

  ┌ services ──────────────────────────────────────────┐
  │  ● Remote Terminal   ● Docker (8)   ○ ngrok        │
  └────────────────────────────────────────────────────┘

    AI & Research              Dev                       Infra
    a  Ask Claude             p  Project Launcher       d  Docker Manager
    o  Ollama (Local AI)      e  Claude Code            r  Remote Terminal
    +  AI Toolmaker           x  Cursor Agent           P  Pilot (remote)
    R  Research (autorun)     v  Code Review            n  Network Info
    A  KMac Assistant         c  Smart Commit           k  Kill Port
    O  KMac Orchestrator      G  Skill Optimizer

    System
    S  Storage Manager        u  Check Updates          b  Backup Dotfiles
    V  Vault Manager          .  Secrets & Keys         i  Install / Bootstrap
    I  Software Manager       ?  Health Check           /  Aliases

    0  Exit
```

Every key is one keypress — no Enter needed. Or skip the menu entirely and use CLI commands like `kmac ask "..."`, `kmac docker health`, or `kmac pilot start`.

**NEW: Live Reload** — Press `~` (tilde) in the main menu to reload all scripts without exiting. Perfect for development or after pulling updates. See changes immediately without restarting.

## Install

```bash
# Via Homebrew
brew tap ksarrafi/kmac
brew install kmac

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

**Ollama Local AI** (`o` / `kmac ollama`) — install, configure, and manage Ollama for running LLMs locally on your Mac or Linux machine. Full setup flow with RAM-based model recommendations (1b for 8GB, 3b for 16GB, 8b for 32GB+). Catalog of 13 popular models including Llama 3.2, Code Llama, Mistral, Mixtral, Phi-3, Gemma 2, Qwen 2.5, DeepSeek Coder, and StarCoder 2. Interactive model management with pull, remove, and chat. Server controls built in.

```bash
kmac ollama                     # Interactive menu
kmac ollama install             # Install + pull recommended model
kmac ollama models              # Manage models (pull/remove/list)
kmac ollama chat                # Chat with a local model
kmac ollama status              # Check server + model status
```

**AI Self-Healing** — built into every tool. When a command fails, KMac catches the error output, sends it to Claude with context about what was attempted, and presents a suggested fix command. Handles shell environments like nvm and rvm automatically. You choose to apply the fix, retry, or skip.

**KMac Assistant** (`A` / `kmac assistant`) — a personal AI gateway that runs as an always-on TypeScript service. Features a WebSocket control plane, Claude agent with tool use (bash, file ops, grep, web fetch, system info), persistent sessions, and multi-channel messaging. Message your AI from Telegram, Discord, or the CLI and get back tool-augmented responses.

```bash
kmac assistant start          # Start the gateway on :7891
kmac assistant chat           # Interactive CLI chat with tool use
kmac ai chat                  # Alias
```

Features: Telegram and Discord channel adapters with chat commands (`/new`, `/status`, `/compact`, `/help`, `/tools`, `/whoami`), skills system (`~/.config/kmac/assistant/skills/`), cron scheduler for recurring tasks, webhook endpoint for external triggers, REST API + WebSocket gateway with OpenClaw-compatible req/res/event protocol.

**KMac Orchestrator** (`O` / `kmac orchestrator`) — a multi-agent task management platform. Dispatch tasks to Claude Code, Cursor Agent, KMac Assistant, or shell commands through a unified API. Built-in cost tracking, approval workflows, and heartbeat monitoring. Runs as a TypeScript service with a web dashboard.

```bash
kmac orchestrator start          # Start on :7892
kmac orchestrator task "migrate auth to MSAL" --agent=claude-code
kmac orchestrator agents         # List registered agents + status
kmac orchestrator costs          # Token/USD spend summary
kmac orchestrator approve <id>   # Approve a pending task
```

**Skill Optimizer** (`G` / `kmac skillopt`) — Karpathy-style autoresearch loop for iteratively improving AI skill files (SKILL.md). Generates test cases, evaluates skill performance with a judge LLM, and refines instructions until a target success rate is met.

```bash
kmac skillopt init <skill-dir>   # Generate eval config for a skill
kmac skillopt run <skill-dir>    # Run optimization loop
kmac skillopt status             # Show all skills + eval scores
```

---

### 2. Docker Management

Docker operations center: Engine API for live monitoring, CLI for compose/cleanup/MCP, and a browser dashboard via the Pilot server. For a deterministic restart, use **`kmac-cli run docker-restart`**; for the full interactive flow with engine wait, use **`kmac docker restart`**.

**Health Dashboard** (`kmac docker dashboard`) — live view of running containers via Engine API: CPU%, memory, network I/O, Docker healthcheck status, and uptime. Shows host OS/kernel and CPU/RAM from `/info` (engine version is validated at connect, not shown in the table).

**Health Report** (`kmac docker health`) — terminal report with color-coded host disk thresholds. Host disk reads **`/System/Volumes/Data`** on modern macOS (not the sealed `/` volume). Per-container table, Docker `system df` breakdown, alerts, and localhost port links.

```bash
kmac docker health               # Terminal report with color coding
kmac docker health --json        # Structured JSON for APIs and automation
kmac docker health --history     # 24h trend (file at ~/.cache/kmac/docker-history.json; needs repeated runs)
```

| Status | Disk | Memory | Indicator |
|--------|------|--------|-----------|
| Healthy | <75% | <75% | 🟢 Green |
| Warning | 75-85% | 75-90% | 🟡 Yellow |
| Severe | 85-90% | — | 🟠 Orange |
| Critical | >90% | >90% (OOM risk) | 🔴 Red |

**Web Dashboard** (`kmac docker web`) — browser UI at `http://localhost:7890/docker-dashboard` (Pilot server). HTML page is unauthenticated; API calls require the pilot token (auto-filled from `~/.config/kmac-pilot/server_token` when opened via `kmac docker web`). Status cards, container table with real healthcheck status, Docker disk table, 60-minute **line** trend chart (Chart.js), prune buttons with confirm. Polls every 10s. In-memory history resets on server restart.

**Crash Detective** (`kmac docker crashes`) — exited containers via Engine API with exit-code categories (OOM 137, SIGKILL, SEGFAULT 139, etc.). View logs or restart interactively.

**Disk Monitor** (`kmac docker disk`) — host disk bar on data volume, `docker system df`, top images, volumes, reclaimable counts with optional prune.

**Compose Manager** (`kmac docker compose`) — `docker compose ls` projects; logs, stop, restart; start from a compose file path.

**MCP Toolkit** (`kmac docker mcp`) — requires Docker Desktop 4.62+ MCP Toolkit (`docker mcp`). Catalog search, profiles, client connect. Hidden from menu if MCP CLI is absent.

**AI Troubleshoot** (`kmac docker troubleshoot`) — gathers Docker diagnostics and sends to Claude (Anthropic key required). **Not** gated on MCP.

**Quick Cleanup** (`kmac docker clean`) — interactive prune menu. Cleans stopped containers, unused images, and build cache. **Never prunes volumes** (they often hold database data). Full safe prune uses `docker system prune -a` without `--volumes`.

**Restart Docker Desktop** (`kmac docker restart`) — quit, relaunch, wait up to 2 minutes for engine readiness.

**Auto-Cleanup Scheduler** (`kmac docker scheduler`) — installs `~/cleanup-docker.sh` and optional `crontab` (weekly/daily). Prunes containers, images, and build cache only — **never volumes**. Unreliable if Mac is asleep.

---

### 3. Storage Manager

Disk space analysis, AI-powered file identification, and cleanup tools designed for macOS — with iCloud Drive integration for migrating large directories off local storage. For canonical safe cleanup, use **`kmac-cli run disk-cleanup`** (the deterministic playbook); `kmac storage` is exploratory and partly interactive.

**Overview** (`kmac storage overview`) — reads `/System/Volumes/Data` for accurate APFS volume stats. Disk usage bar with used/total/free, plus real purgeable bytes from `diskutil` or the Foundation API (macOS reclaimable storage the system can free when needed).

**Directory Scan** (`kmac storage scan`) — parallel `du` across major home directories (Downloads, Documents, Desktop, Projects, Library caches, Docker, etc.) with size bars relative to the largest. Global **120s timeout** kills slow jobs so large trees like `~/Library` do not hang indefinitely.

**Big Files** (`kmac storage big`) — finds files >100MB across home and `~/.cursor`. Groups files by category; Claude Haiku analyzes **categories** (not each file individually) with descriptions, safety ratings (SAFE / CAUTION / KEEP), and tips. Pattern-matching fallback when offline. Numbered per-file actions: delete (`d 1,3,5`), backup to iCloud then delete (`b 1,3,5`), or bulk-delete all SAFE categories (`D`).

**Cleanup** (`kmac storage clean`) — **interactive menu**, not one-click: scans reclaimable caches and build artifacts (Xcode DerivedData, Homebrew, npm, pip, logs, Trash, Docker, simulators, etc.), then numbered quick actions (empty Trash, clear DerivedData, purge caches). Does **not** remove `.DS_Store` files.

**iCloud Migration** (`kmac storage icloud`) — analyzes migration candidates and can move a selected directory to iCloud Drive with a local symlink so apps keep working. Does **not** show iCloud quota. **Risky for dev projects** — git repos and `node_modules` do not sync well to iCloud.

**Node Modules** (`kmac storage node`) — scans for `node_modules` under Projects, Developer, Desktop, and Documents. Lists each with size and last `package.json` date. Only bulk **remove stale (>30 days old)** — no per-directory pick list.

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

See [docs/iOS_APP_GUIDE.md](docs/iOS_APP_GUIDE.md) for complete setup instructions.

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

### 6. Vault Manager — Project Key Organization

**NEW!** A wizard-based vault manager for organizing API keys and secrets by project. Makes it easy to manage keys for multiple projects and export them for AI tools.

**Vault Manager** (`V` / `kmac vault`) — organized, project-based secret management with an intuitive wizard interface:

```bash
kmac vault                    # Interactive vault browser
kmac vault list               # Browse all keys organized by project
kmac vault set                # Add key with wizard (3-step process)
kmac vault project myapp      # Project-specific key manager
kmac vault get myproject:key  # Get a specific key value
```

**Key Features:**

- **3-Step Wizard** — No typing formats! Just answer:
  1. Which project? (choose existing or create new)
  2. What's the key for? (24 common types: OpenAI, Claude, Stripe, Database, etc.)
  3. Enter the value (hidden input)
  - **Retry loops** — Invalid input prompts retry instead of canceling
  - **Format hints** — Shows expected format for common key types
  - **Validation warnings** — Alerts if key format looks incorrect
  
- **Automatic Organization** — Keys auto-group by project namespace:
  ```
  myproject/
    ├─ openai_key            sk-p••••RssA  [2026-04-11 04:30:15]
    ├─ database_url          post••••mydb
  
  staging/
    ├─ stripe_secret         sk_t••••_456  [2026-04-11 04:25:10]
  ```

- **Timestamp Tracking** — Every key stores when it was created/updated

- **Update Protection** — Shows current value and asks for confirmation before overwriting

- **Smart Delete Confirmations** — Full preview before deletion:
  - Shows key name, masked value, and creation timestamp
  - Requires typing 'DELETE' to confirm (prevents accidents)
  - "This action cannot be undone" warning

- **Search & Navigation** — Find keys quickly:
  - Press `/` to search/filter keys
  - Real-time regex search across all keys
  - Keyboard shortcuts: `h` for help, `r` to refresh, `q` to exit

- **Empty State Guidance** — Helpful for first-time users:
  - Clear instructions when vault is empty
  - Suggests common first keys to add
  - Getting started guide right in the interface

- **Export to .env Files** — Perfect for local dev and AI tools:
  ```bash
  kmac vault project myapp
  # Press 'x' to export → creates myapp.env
  # Use with AI: "Here are my keys in myapp.env"
  # Clean up: rm myapp.env
  ```

- **Import from .env** — Bulk import existing keys from `.env` files

- **Project Manager** — Interactive menu per project with:
  - Add/edit/delete keys
  - Export all keys to file
  - Import from .env file
  - Copy to clipboard

**24 Common Key Types:**
- AI: OpenAI, Anthropic (Claude), Google AI, Groq
- Payment: Stripe (secret & publishable)
- Database: PostgreSQL, MongoDB, Redis URLs, passwords
- Auth: JWT secrets, OAuth (client ID & secret)
- Cloud: AWS (access & secret keys), GitHub, GitLab, Docker Hub
- Services: SendGrid, Twilio, webhooks
- Generic: API keys, custom types

**AI-Friendly Workflow:**
```bash
# When AI needs your keys:
kmac vault project myapp
# Press 'x' to export → myapp.env

# Give to AI: "Use the keys in myapp.env"
# When done: rm myapp.env
```

See `docs/VAULT_GUIDE.md` for complete documentation.

---

### 7. Secrets & Integration Hub

A private credential vault that turns KMac into your personal command center — securely storing API keys for AI models, cloud providers, MCP servers, and any service you integrate with.

**Secrets & Keys** (`.` / `kmac secrets`) — a full-featured secret management system with three backends:

- **Docker Vault** (default) — a containerized, isolated key-value store. Runs a lightweight Python server inside a Docker container with data encrypted in a Docker volume (`kmac-vault-data`). Only listens on `127.0.0.1` — never exposed to the network. Portable — back up or migrate the volume to move between machines. Ideal for users who already run Docker and want OS-independent secret storage.
- **macOS Keychain** — hardware-backed, OS-managed, unlocked by your login password. Secrets survive reboots and app reinstalls. The most secure option on macOS.
- **Encrypted File Vault** — AES-256-CBC encryption via `openssl` with PBKDF2 key derivation (100,000 iterations). Protected by a master password. Stored at `~/.config/kmac/vault.enc`. Portable — sync via iCloud, git, or USB to other machines.

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

### 8. Plugin System & Extensibility

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

Plugins can also declare lifecycle hooks via a header comment (comma-separated):

```
# TOOLKIT_HOOKS: post-commit,on-startup
```

**Plugin API v2 — lifecycle hooks.** Eleven hooks are available: `pre-commit`, `post-commit`, `pre-review`, `post-review`, `pre-deploy`, `post-deploy`, `on-error`, `on-startup`, `on-exit`, `session-start`, and `session-end`. They are wired into `aicommit`, `review`, and the toolkit main loop. Failed hooks log warnings and never block the main flow. See **`plugins/REGISTRY.md`** for the full plugin catalog, hook reference, and authoring guide.

**Built-in plugins:** `git-stats` (repo insights), `git-guardian` (pre-commit secret scanning), `docker-notify` (container health alerts), `project-stats` (repo metrics), `tmux-session` (session manager), `cleanup` (system cleanup), `wifi-password`.

Plugins also work as CLI subcommands: `kmac git-guardian` will find and execute `plugins/git-guardian.sh`.

The AI Tool Builder (`kmac make`) generates plugins in this format automatically — describe what you want, iterate with AI, and it installs the result as a plugin with a menu key or as a script with a CLI subcommand.

Included plugins:
- **wifi-password** — show the current Wi-Fi network password from Keychain
- **cleanup** — free disk space by clearing caches, logs, Trash, and Docker resources
- **git-stats** (`git-stats.sh`) — example hook plugin (`post-commit`, `on-startup`)

---

### 9. Software Manager

Interactive software installation and updates from the toolkit menu (`I`) or the CLI. The manager organizes tools into **five categories**: **Dev Essentials**, **AI & Coding Agents**, **Editors & Apps**, **Infrastructure**, and **Shell & Productivity**. It covers **30+ tools** including git, node, python, rust, claude, chatgpt, gemini, ollama, aider, copilot, cursor, vscode, docker, kubectl, terraform, starship, and oh-my-zsh.

Each entry shows **installed vs not installed** status with **version numbers** where available. You can **install individually**, **by entire category**, or **install all missing** in one pass. **Search** and **update** flows help you find packages and refresh what you already have.

**CLI:** `kmac software`, `kmac software list`, `kmac software install claude`, `kmac software update`.

---

### 10. Cross-Platform Support

KMac uses **`scripts/_platform.sh`** as a cross-platform abstraction layer. It **detects the OS** (macOS vs Linux), **Linux distro** (Ubuntu, Fedora, Arch), and **package manager** (Homebrew, apt, dnf, or pacman). **Wrapper functions** unify clipboard access, desktop notifications, credential storage (**macOS Keychain** vs **`secret-tool`** on Linux), local IP discovery, and common file operations.

The **software installer** translates Homebrew-oriented commands to the **native package manager** on Linux. The **vault** uses **`secret-tool`** on Linux instead of macOS Keychain when storing secrets through the platform layer.

---

### 11. Testing & CI

The repo ships **60 smoke tests** across **eight test files**, driven by a **lightweight Bash test runner** with **no extra dependencies**. **GitHub Actions** runs a **matrix** on **macOS and Ubuntu** and includes **ShellCheck**. Run the suite locally:

```bash
bash tests/run-tests.sh
```

---

## Remote Access

Access your KMac Pilot server from anywhere — on the road, from your phone, or another machine:

```bash
kmac remote-access setup       # Choose: Tailscale, Cloudflare, or ngrok
kmac remote-access start       # Start the tunnel
kmac remote-access url         # Print + copy the URL
kmac remote-access qr          # QR code for iOS app connection
kmac remote-access status      # Check tunnel health
```

| Method | Best For | Setup |
|--------|----------|-------|
| **Tailscale** | Always-on personal access | Mesh VPN, no port forwarding |
| **Cloudflare** | Sharing with custom domain | Free tunnel, auto-TLS |
| **ngrok** | Quick testing | One command, instant URL |

---

## Server Deployment

The KMac Pilot server can be deployed three ways:

### Quick Start (local)

```bash
kmac server start              # Auto-creates venv, installs deps, starts server
kmac server status             # Health check + connection info
kmac server token              # Show/copy the Bearer auth token
kmac server logs -f            # Follow server logs
```

### Auto-Start Service

```bash
kmac server install            # launchd on macOS, systemd on Linux
```

- **macOS**: Installs a launchd agent that starts on login
- **Linux**: Installs a systemd user service with security hardening (ProtectSystem, NoNewPrivileges, PrivateTmp)

### Docker Compose (production)

Full stack with TLS reverse proxy:

```bash
kmac server docker-up          # Starts pilot + vault + Caddy
kmac server docker-down        # Stops everything
```

Services:
| Service | Port | Description |
|---------|------|-------------|
| **pilot** | 7890 (internal) | aiohttp API + WebSocket server |
| **vault** | 9999 (internal) | Encrypted secrets store (Fernet/AES) |
| **caddy** | 443, 80 | TLS termination + reverse proxy |

Configure your domain in `deploy/Caddyfile` for automatic Let's Encrypt TLS.

---

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
│  │  _ui.sh  _vault.sh  _auth-helper.sh  _ai-fix.sh  _hooks.sh  _platform.sh │  │
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
│  assistant/ (TypeScript)           port 7891                    │
│  gateway.ts — WebSocket + REST API, Claude tool use, sessions   │
│  channels/ — Telegram, Discord adapters                         │
│  skills.ts — skill loading, cron.ts — scheduled tasks           │
└────────────────────────────────────┬────────────────────────────┘
                                     │
┌────────────────────────────────────┴────────────────────────────┐
│  orchestrator/ (TypeScript)        port 7892                    │
│  server.ts — REST API, task dispatch, agent registry            │
│  agents/ — claude-code, cursor, assistant, shell adapters       │
│  costs.ts, approvals.ts, heartbeat.ts                           │
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
├── .github/
│   └── workflows/
│       └── ci.yml          GitHub Actions CI
├── homebrew/
│   └── Formula/
│       └── kmac.rb         Homebrew formula
├── tests/                  Test suite (8 test files + runner)
├── scripts/
│   ├── _ui.sh              Shared UI — colors, title_box, pause, spinners
│   ├── _vault.sh           Triple-backend secret vault (Keychain + AES-256 + Docker)
│   ├── _auth-helper.sh     Claude API auth (vault → env fallback)
│   ├── _ai-fix.sh          AI self-healing — catches errors, suggests fixes
│   ├── _hooks.sh           Plugin lifecycle hook engine (11 hooks)
│   ├── _platform.sh        Cross-platform abstraction (macOS + Linux)
│   ├── _pilot-lib.sh       Pilot shared constants and helpers
│   ├── _pilot-bot.sh       Telegram long-poll bot daemon
│   ├── pilot               Pilot CLI (start/stop/config/server/status)
│   ├── docker              Docker Manager — Engine API + MCP + Compose
│   ├── docker-health       Docker health report (--json, --history)
│   ├── storage             Storage Manager — disk analysis + AI + iCloud
│   ├── secrets             Credential manager + integration hub
│   ├── software            Software installer & manager (30+ tools)
│   ├── ask                 Ask Claude from the terminal
│   ├── review              AI code review on git diffs
│   ├── aicommit            AI commit message generator
│   ├── toolmaker           AI tool builder — describe → build → install
│   ├── ollama-setup        Ollama local AI manager (install, models, chat)
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
│   ├── server             Server lifecycle manager (start/stop/status/install)
│   ├── remote-access      Secure remote access (Tailscale/Cloudflare/ngrok)
│   ├── assistant           KMac Assistant manager (start|stop|chat|status)
│   ├── orchestrator        KMac Orchestrator manager (start|stop|task|agents|costs)
│   ├── skillopt            Skill Optimizer CLI (init|run|status)
│   └── create-aicoder.sh   Create global 'aicoder' command
├── assistant/              KMac Assistant (TypeScript)
│   ├── package.json
│   ├── tsconfig.json
│   └── src/
│       ├── gateway.ts      WebSocket + REST gateway
│       ├── config.ts       Configuration loader
│       ├── types.ts        Type definitions
│       ├── skills.ts       Skill loading system
│       ├── cron.ts         Scheduled task runner
│       ├── optimizer.ts    Skill Optimizer CLI (Karpathy loop)
│       └── channels/       Telegram, Discord adapters
├── orchestrator/           KMac Orchestrator (TypeScript)
│   ├── package.json
│   ├── tsconfig.json
│   └── src/
│       ├── index.ts        Entry point
│       ├── server.ts       REST API + web dashboard
│       ├── types.ts        Core types
│       ├── config.ts       Configuration
│       ├── tasks.ts        Task store + dispatch
│       ├── costs.ts        Cost tracking
│       ├── approvals.ts    Approval workflow
│       ├── heartbeat.ts    Agent health monitor
│       └── agents/         Adapters (claude-code, cursor, assistant, shell)
├── deploy/
│   ├── Caddyfile            Reverse proxy config (TLS termination)
│   ├── com.kmac.pilot.plist macOS launchd service definition
│   ├── kmac-pilot.service   Linux systemd service (security-hardened)
│   └── kmac-vault.service   Docker vault systemd service
├── docker-compose.yml       Full stack: pilot + vault + Caddy
├── server/
│   ├── Dockerfile           Pilot API server container image
│   ├── .dockerignore        Container build exclusions
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
│   └── git-stats.sh        Example hook plugin (post-commit, on-startup)
└── dotfiles/               Backed-up dotfiles and Claude agent configs
```

## API Endpoints

The Python server exposes a REST + WebSocket API for the iOS app, web dashboards, and automation.

| Method | Path | Description |
|--------|------|-------------|
| GET | `/api/ping` | Health check (no auth) |
| GET | `/health` (Assistant :7891) | Assistant health check |
| GET | `/api/sessions` (Assistant) | List chat sessions |
| POST | `/api/sessions/:id/message` | Send message to session |
| GET | `/api/tools` (Assistant) | List available tools |
| WS | `/ws` (Assistant) | WebSocket gateway |
| GET | `/api/agents` (Orchestrator :7892) | List agents |
| GET | `/api/tasks` (Orchestrator) | List tasks |
| POST | `/api/tasks` (Orchestrator) | Create task |
| GET | `/api/costs` (Orchestrator) | Cost summary |
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
| WS | `/ws` | Real-time two-way communication (auth, subscribe, session control, system metrics, exec) |

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
- **Triple-backend vault** — secrets are stored in a Docker container vault (default, isolated, volume-portable), macOS Keychain (hardware-backed), or an AES-256-CBC encrypted file (portable). The `_vault.sh` library provides a unified API (`vault_get`, `vault_set`) so scripts don't need to know which backend is active. Secrets never touch disk as plaintext. The Docker backend (default since v3.3.0) runs a lightweight Python REST server inside a container with Fernet-encrypted data (AES-128-CBC + HMAC-SHA256) in a named volume — ideal for OS-independent, containerized secret storage with volume backup/restore portability.
- **Docker Engine API** — direct unix socket calls via `curl --unix-socket` instead of parsing `docker` CLI output. Faster, more reliable, structured JSON.
- **No heavy dependencies** — the core toolkit needs nothing beyond what macOS provides. Optional tools enhance UX but aren't required.
- **Plugin protocol** — three comment headers in a script. That's it. No registration, no config files, no compilation.
- **Cross-platform** — `_platform.sh` provides a compatibility layer so the same scripts work on macOS and Linux. It wraps OS-specific operations (clipboard, keychain, notifications, package management) behind unified functions.
- **Lifecycle hooks** — plugins can register for eleven lifecycle events without modifying core code. Failed hooks log warnings but never block the main flow.
- **Tested** — 60 smoke tests run on every push via GitHub Actions across macOS and Ubuntu.
- **Portable** — works from a git clone or synced from iCloud Drive. The installer detects which and configures paths accordingly.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines on code style, adding tools, the plugin protocol, and submitting PRs.

## License

[MIT](LICENSE) — KMac-CLI Contributors
