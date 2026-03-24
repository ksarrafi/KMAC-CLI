# Changelog

## 2.9.0 — 2026-03-22

### Automated Release Pipeline
- **GitHub Actions release workflow** — Tests on both macOS and Ubuntu, creates GitHub Release with auto-generated notes, computes tarball sha256, updates Homebrew formula in both the main repo and the tap repo automatically on tag push

### ShellCheck Clean
- **All 53 scripts pass ShellCheck** — Fixed quoting, unused variables, word splitting, and other warnings across the entire codebase
- **`.shellcheckrc`** — Added for `source-path` resolution so `shellcheck -x` works from repo root

### Plugin Ecosystem
- **4 new plugins**: `docker-notify` (container health alerts), `git-guardian` (pre-commit secret scanning), `project-stats` (repo metrics), `tmux-session` (session manager)
- **`plugins/REGISTRY.md`** — Plugin registry with documentation, hook reference, and authoring guide
- **7 total plugins** with proper `TOOLKIT_*` headers and hook integration

### Homebrew Tap
- **`ksarrafi/homebrew-kmac`** — Dedicated Homebrew tap repository so `brew tap ksarrafi/kmac && brew install kmac` works
- **Automated tap sync** — Release workflow pushes formula updates to the tap repo

### Remote Access
- **`kmac remote-access`** — Secure remote access to Pilot server from anywhere
- **Three tunnel methods**: Tailscale (recommended, mesh VPN), Cloudflare Tunnel (custom domains), ngrok (quick testing)
- **Commands**: setup, start, stop, restart, status, url, qr (QR code for iOS app)
- Integrated into `kmac` CLI and installer

## 2.8.0 — 2026-03-22

### Server Deployment Infrastructure

- **Docker Compose** — Full production stack (`docker-compose.yml`): Pilot API server, encrypted vault, Caddy reverse proxy with auto-TLS
- **Server Dockerfile** — Python 3.12 Alpine image for the Pilot API with non-root user, health checks
- **`kmac server` command** — Unified lifecycle management: start, stop, restart, status, logs, token, install, docker-up, docker-down
- **macOS launchd service** — `com.kmac.pilot.plist` for auto-start on login via `kmac server install`
- **Linux systemd service** — `kmac-pilot.service` with security hardening (ProtectSystem, NoNewPrivileges, PrivateTmp)
- **Caddy reverse proxy** — TLS termination, WebSocket support, security headers, JSON logging
- **Docker vault service** — Systemd unit for managing the vault container on Linux
- **Documentation** — Deployment guide in README + QUICKSTART with all three deployment modes

## 2.7.0 — 2026-03-22

### Deep Security Hardening (5-round audit, zero remaining issues)

**CRITICAL fixes:**
- Vault: OpenSSL password no longer visible in `ps` — uses `-pass stdin` / `-pass env:` instead of `-pass "pass:..."`
- Software manager: all `eval` replaced with type-safe dispatchers for install/check
- AI fix: auto-run removed entirely — copy-to-clipboard only

**HIGH fixes:**
- Server: eliminate ALL `create_subprocess_shell` — `system_ops.py` fully rewritten with `create_subprocess_exec` and Python parsing
- Server: `tail=0` parameter no longer bypasses output limits (Python `[-0:]` quirk)
- Server: sensitive prompts no longer broadcast to all WebSocket clients
- Server: prompt size limits (100KB) and leading-dash rejection for CLI argv injection
- Server: `agent_manager.ask()` now has 120s timeout with kill+wait
- Server: `agent_manager` output lines capped at 10,000
- Server: WebSocket clients list protected by `asyncio.Lock`
- Server: generic error messages in all API responses (no `str(e)` / `str(exc)`)
- Bash: plugin subcommand path traversal blocked (`/` and `..` rejected)
- Bash: `safe_run` requires user confirmation before sending logs to AI
- Bash: `kill -- -"$pid"` replaced with `kill "$pid"` (no accidental group kill)
- Bash: Telegram `tg_send` uses `--data-urlencode` for proper encoding
- Bash: `pilot_agent_cmd` deprecated (shell string injection risk)
- Bash: `create-aicoder` writes to `$HOME/bin` not `/usr/local/bin`
- iOS: ALL `try?` replaced with `do/catch` + user-visible error messages (20+ call sites)
- iOS: empty `catch {}` blocks eliminated
- Config: removed dangerous Claude allowlist entries (`pip install`, `npm i`, `source ~/.zshrc`)
- Vault: rate-limit map LRU eviction (prevents unbounded memory growth)

**MEDIUM fixes:**
- Server: directory listing capped at 2,000 items; tree walk capped at 2,000 nodes
- Server: Docker dashboard history race condition fixed with `asyncio.Lock`
- Server: Docker dashboard `minutes` parameter clamped (1-1440)
- Server: `config.py` handles invalid PORT env gracefully
- Server: narrowed broad `except Exception` to specific exception types across all files
- Bash: `mkdir -p && chmod` operator precedence fixed (toolkit.sh, startup-hook.sh)
- Bash: PID file TOCTOU hardened (read+validate before kill)
- Bash: `install.sh` uses `"$HOME/bin/"` consistently (no unquoted `~/bin/`)
- Bash: startup-hook.sh removes zsh syntax from bash fallback path
- Bash: `aliases.sh` uses `python3`, adds `--` to docker xargs
- Bash: `_pilot-lib.sh` atomic JSON writes via mktemp+mv
- Bash: `remote-terminal.sh` chmod 600 on Caddyfile, proper PID printf
- Bash: `_hooks.sh` array-based hook name iteration
- Bash: `scripts/docker` removes shell interpolation from Python `-c` calls
- iOS: `TerminalView` guards against `scrollTo(-1)` crash
- iOS: `ConnectView` placeholder changed to `https://`
- iOS: `FileBrowserView` stable Identifiable ID

## 2.6.0 — 2026-03-22

### Security Hardening (comprehensive audit — 4 rounds, zero remaining issues)

**CRITICAL fixes:**
- Pilot `/run`: reject shell metacharacters, execute as array instead of `bash -c` — prevents command chaining bypass
- AI self-healing: disabled auto-run of AI-suggested commands — copy-only for safety
- Vault registry: all Python calls use env vars + heredocs — eliminates code injection
- `create-aicoder.sh`: resolved binary path instead of trusting CWD `./aicoder`
- Software manager: replaced all `eval` with type-safe dispatchers for install/check
- All `curl | sh` installer patterns: download to temp file + user confirmation first

**HIGH fixes:**
- Server `resolve_project`: validate names, realpath containment — blocks `..` path traversal
- Server `/api/run`: reject dangerous flags (`--exec`, `--upload-pack`, `-c`, `--config`, `--privileged`)
- Server: clamp git log count (max 200) and docker log tail (max 10,000)
- Server: require Bearer auth for Docker dashboard (was unauthenticated)
- Server: resolve file paths once (TOCTOU fix), generic error messages (no info leaks)
- Server: WebSocket client cap (100), subscription cap (50), command type validation
- Server: `await proc.wait()` after all `proc.kill()` calls (no zombie processes)
- Server: timing-safe token comparison with `hmac.compare_digest`
- iOS: WebSocket auth via first message instead of URL query parameter (no token in logs/proxies)
- iOS: `@MainActor` isolation on ALL `Task` blocks that touch UI state (20+ views fixed)
- iOS: Keychain write error handling, sanitized log messages
- Vault Docker: non-root user, pinned `cryptography==44.0.0`, volume ownership

**MEDIUM fixes:**
- Vault: per-deployment random PBKDF2 salt (not static), `chmod 600` on encrypted files
- Hooks: reject unknown hooks, validate no `|` in handler paths
- Platform: safe `osascript` via argv (no string interpolation injection)
- Pilot: reject glob metacharacters in project names for `find -name`
- `install.sh`: `compgen -G` instead of unquoted `ls` for iCloud detection
- `toolkit.sh`: integer `read -t` timeout for Bash 3.2 compatibility
- CI: skip fork PR test execution, pinned checkout SHA
- Claude settings: removed broad `find`/`ln` from allowlist
- Software registry: fixed Gemini package name (was wrong vendor)
- `startup-hook.sh`: safe iCloud path resolution via loop

**LOW fixes:**
- All `/tmp/` references migrated to `~/.cache/kmac/` (storage, toolmaker, docker-health, safe_run)
- Docker aliases use `xargs` pipe pattern
- Boolean variable patterns use explicit `[[ "$var" == true ]]`
- Vault token cache uses `is not None` check
- Server: logged swallowed exceptions, removed token prefix from startup output
- Ollama: model name validation (`^[A-Za-z0-9._:/-]+$`)
- `setup-mac`: explicit Homebrew env exports instead of `eval`
- `update-check`: quoted `$NPM_BIN` in command positions

## 2.5.0 — 2026-03-22

### New: Software Manager (`kmac software` / `I` in menu)
- Interactive installer with 5 categories: Dev Essentials, AI & Coding Agents, Editors & Apps, Infrastructure, Shell & Productivity
- 30+ tools: git, python, node, rust, fzf, bat, claude, chatgpt, gemini, ollama, aider, copilot, cursor, vscode, docker, kubectl, terraform, oh-my-zsh, starship, zoxide, atuin
- Status dashboard showing installed/missing with version numbers
- Install individually, by category, or all missing at once
- Search and update capabilities
- CLI access: `kmac software list`, `kmac software install <name>`, `kmac software update`

### New: Plugin API v2 — Lifecycle Hooks
- **Hook engine** (`_hooks.sh`): 11 lifecycle hooks for extending toolkit behavior
  - `pre-commit`, `post-commit` — wired into `aicommit`
  - `pre-review`, `post-review` — wired into `review`
  - `on-startup`, `on-exit` — wired into main menu loop
  - `on-error` — wired into `tool_error`
  - `pre-deploy`, `post-deploy`, `session-start`, `session-end` — available for plugins
- **Plugin auto-registration**: plugins declare `# TOOLKIT_HOOKS: post-commit,on-startup` in headers
- **API**: `hooks_register`, `hooks_emit`, `hooks_list`, `hooks_clear`
- **Example plugin**: `git-stats.sh` — shows commit streak and active files on startup and after commits

### New: Cross-Platform Linux Support
- **Platform abstraction** (`_platform.sh`): detects OS, distro, and package manager
- Wrapper functions: clipboard, notifications, keychain (secret-tool on Linux), local IP, file age, sed
- Vault updated: uses `secret-tool` on Linux instead of macOS Keychain
- Software installer routes `brew` commands to `apt`/`dnf`/`pacman` on Linux
- Startup hook uses cross-platform `stat` for file age

### New: Test Suite & CI
- **60 smoke tests** across 8 test files covering toolkit, UI, vault, software, plugins, dotbackup, install
- **Bash test runner** (`tests/run-tests.sh`): assert helpers, per-file subtotals, summary, no external dependencies
- **GitHub Actions CI** (`.github/workflows/ci.yml`): runs on push/PR to main, matrix: macOS + Ubuntu
- **ShellCheck** validation on key scripts

### New: WebSocket Client Commands (Server)
- Full two-way communication replacing the placeholder `_ws_reader`
- Auth: first message must be `{"type": "auth", "token": "..."}` 
- Commands: `ping`, `subscribe`/`unsubscribe`, `session.input`, `session.start`, `session.stop`, `session.list`, `system.status`, `exec`
- System metrics broadcast every 30 seconds to subscribed clients
- Session output streaming to subscribed clients
- `session_manager.py`: added `write_stdin` for PTY input from WebSocket

### New: Ollama Local AI Manager (`kmac ollama` / `o` in menu)
- Full setup flow: install Ollama, start server, pull models with RAM-based recommendations
- Model catalog: 13 popular models (Llama 3.2, Code Llama, Mistral, Mixtral, Phi-3, Gemma 2, Qwen 2.5, DeepSeek Coder, StarCoder 2, nomic-embed)
- Interactive model management: pull, remove, list installed with sizes
- Quick chat launcher with model picker
- Server management: start, status check
- CLI: `kmac ollama install`, `kmac ollama models`, `kmac ollama chat`, `kmac ollama status`

### New: Homebrew Tap
- **Formula** (`homebrew/Formula/kmac.rb`): `brew install ksarrafi/tap/kmac`
- Recommended deps: fzf, bat, jq
- HEAD install support for bleeding edge
- **Release script** (`scripts/release`): automates VERSION bump, formula update, git tag creation

### Fixed
- **dotbackup hook**: no longer uses `BASH_SOURCE` inside zsh `zshexit()` — resolves path at install time
- **startup-hook.sh**: no longer hardcodes iCloud path — resolves toolkit dir dynamically (env var → script location → iCloud → common paths)


## 2.4.0 — 2026-03-22

### New: Triple-Backend Secrets Vault
- **Credential Manager** (`kmac secrets`): full-featured secret management with 3 backends
  - macOS Keychain (hardware-backed, default on macOS)
  - Encrypted File Vault (AES-256-CBC, portable, syncable)
  - Docker Vault (containerized REST API, volume-portable)
- **Integration Registry**: 19 pre-configured services across 6 categories (AI, DevOps, Cloud, Infra, Docker, Services)
- **Custom integrations**: register any API key, token, or secret with a category and env var mapping
- **Guided setup**: browser auto-open to signup pages, step-by-step instructions, key validation via API calls
- **Auto-export**: vault credentials loaded into environment on toolkit startup — all tools use the vault automatically
- **Backward compatible**: legacy Keychain entries auto-migrated to new naming scheme

### New: Docker Health Monitoring
- **CLI** (`kmac docker-health`): real-time container stats (CPU%, memory%), host disk usage, color-coded alerts
- **Web Dashboard** (`/docker-dashboard`): Chart.js graphs, container list, disk breakdown, quick cleanup actions
- **History tracking** (`--history`): 24-hour trend data with ASCII sparklines
- **JSON output** (`--json`): structured health data for automation and API consumption

### UX Overhaul
- **First-run welcome wizard**: guided onboarding with health check, API key setup (opens browser, validates keys), quick tour
- **Redesigned main menu**: Code Review and Smart Commit moved to Dev section, Sessions removed, rotating tips in footer
- **Shared UI library** (`_ui.sh`): spinner, spin_while, confirm, section, menu_option, progress indicators, random tips
- **Standardized 12 scripts**: title_box headers, consistent colors, error formatting across ask, sessions, killport, dotbackup, claudeme, cursoragent, project, docker-health, remote-terminal, pilot, update-check, docker
- **Fixed bugs**: broken back handlers in docker crashes and update-check menus, `local` outside functions in project/ask, hardcoded iCloud paths in aliases.sh and project
- **Portable aliases**: aliases.sh uses `$_KMAC_ALIAS_DIR` instead of hardcoded iCloud glob paths
- **Health check** now shows vault backend, configured integration count, and key status via vault API

## 2.3.0 — 2026-03-19

### New: KMac Pilot — Remote AI Agent Control
- **Telegram Bot**: Start and monitor Claude Code / Cursor Agent tasks from your phone
  - `/task`, `/ask`, `/status`, `/stop`, `/agent`, `/projects`, `/tree`, `/cat`, `/run`
  - `/log`, `/diff`, `/approve`, `/reject` for reviewing agent output and git changes
  - Heartbeat streaming: periodic status updates with elapsed time and output preview
  - Agent switching between Claude Code and Cursor Agent
- **API Server** (`pilot server start`): Python aiohttp REST + WebSocket backend on port 7890
  - Token-based auth (auto-generated, stored in `~/.config/kmac-pilot/`)
  - Multi-session agent management — run multiple agents concurrently
  - PTY-based real-time output streaming (no more buffered output)
  - Claude stream-json parsing: shows tool usage, text, results, cost/timing
  - ANSI escape code stripping for clean terminal output
  - File browsing, git operations, Docker management, system monitoring
  - Command execution with allowlist + blocklist security
- **iOS App** (KMacPilot): Native SwiftUI app
  - Dashboard with system info and active agent sessions
  - Start tasks on any project with Claude Code or Cursor Agent
  - Live terminal output as agents work (WebSocket streaming)
  - File browser with syntax-highlighted code viewer
  - Git status, diff viewer, commit/revert
  - Shell command execution on remote Mac
  - Docker container management
  - Auto-reconnect and persistent server credentials

### New: `kmac` Command
- Type `kmac` anywhere to launch the toolkit (alias for `toolkit`)
- Symlinked to `~/bin/kmac` for PATH-based access
- Works with all subcommands: `kmac pilot start`, `kmac ask "..."`, etc.
- Installer adds `kmac` alias to `.zshrc` and `.bashrc` (including retroactive upgrades)

### Improved: Project Discovery
- Deep scanning: auto-discovers git repos up to 3 levels deep in configured scan dirs
- Multiple scan directories: comma-separated in setup wizard
- Skips Backup/Archive directories to avoid listing old copies
- Path deduplication when scan dirs overlap
- Both bash (`_pilot-lib.sh`) and Python (`server/projects.py`) implementations

### Improved: Security Hardening
- Path traversal prevention in file tree API
- Command injection prevention: allowlist + `subprocess_exec` (no shell) for `/api/run`
- Docker ops use arg lists instead of shell interpolation
- Container ID validation with regex
- WebSocket token URL-encoded via URLComponents
- Auth token masked in server startup logs
- Placeholder API key stripping (`your-api-key-here` → unset)

### Improved: Error Handling
- All POST API handlers catch malformed JSON bodies
- Integer query params (`count`, `tail`) catch `ValueError`
- Config file handles corrupted JSON gracefully
- Session manager logs PTY exceptions instead of silently swallowing
- `stop_session` handles `None` process/pid without crashing
- iOS `scrollTo` guards against empty arrays
- iOS `APIClient` uses optional URL construction (no force unwraps)
- iOS `AppState.disconnect()` clears all state

### Fixed
- `toolkit.sh` resolves symlinks correctly (fixes `kmac` from `~/bin`)
- `project_scan_dirs` now expands `~` paths with `os.path.expanduser()`
- `memory_info` strips whitespace before `isdigit()` check
- `WebSocketClient.isConnected` set after handshake, not before
- Removed unused `aiofiles` from requirements.txt
- Removed blocking `subprocess.getoutput()` calls in async handlers

## 2.2.0 — 2026-03-14

### New: AI Tool Maker (`+` or `toolkit make`)
- Describe what you want in plain English, AI builds a production-quality bash script
- Interactive iterate loop: review code, tell AI what to change, test run, or open in $EDITOR
- Auto-installs as a plugin (with menu key) or script (with subcommand)
- Syntax validation before install
- Code preview with bat (syntax-highlighted) or cat -n
- Accessible from menu (`+`), CLI (`toolkit make "description"`), or aliases (`toolkit build`)

## 2.1.0 — 2026-03-14

### New: AI Self-Healing
- Tools now automatically detect failures and offer AI-powered diagnosis
- `_ai-fix.sh` helper sends errors to Claude, gets a fix command, and offers to run it
- `safe_run` wrapper catches tool failures without swallowing output
- Update-check offers AI diagnosis when brew/npm commands fail

### New: AI Spinner
- Animated braille spinner (`⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏`) with color cycling shows whenever AI is working
- Context-aware labels: "Thinking", "Reviewing", "Writing commit", "Diagnosing", "Summarizing"
- Shows model tag (sonnet/haiku/opus) so you know which model is running

### Improved: Menu Consistency
- All submenus now use single-keypress input (no Enter needed)
- Standardized "Back" label and `> ` prompt across every submenu
- `pause()` is now "Press any key to continue" (single keypress)

### Improved: dotbackup
- Complete rewrite — was truncated at 33 lines, now fully functional
- Subcommands: backup, restore, diff, hook
- Diff preview before overwriting, .bak safety copies on restore
- Claude/Cursor config backup via rsync
- Auto-exports Brewfile during backup
- `hook` subcommand installs zshexit auto-backup

### Improved: Update Check
- Animated spinner during version checks (no more blank screen)
- brew/npm updates now stream output live instead of capturing silently
- AI diagnosis on update failures

### Improved: Plugin System
- Plugins now support `TOOLKIT_KEY` header for letter-based menu shortcuts
- wifi-password (w) and cleanup (C) updated with key headers

### Improved: Versioning
- VERSION file is now single source of truth (not hardcoded)
- `toolkit --version` shows version, install path, script/plugin count
- `toolkit whatsnew` shows latest changelog section
- Enhanced `toolkit --help` with grouped commands and descriptions

### Fixed
- `pause()` was printing raw escape codes (`\033[2m`) instead of styled text
- `safe_run` was capturing all output into a variable (blank screen until command finished)
- Interactive tools (update-check, dotbackup) were broken when wrapped in output capture

## 2.0.0 — 2026-03-14

### Added
- Status Dashboard — live service status (Remote Terminal, Docker, ngrok) in menu banner
- Show QR / Connection Info — reprint remote terminal URL + QR without restarting
- AI Power Tools
  - `ask` — instant Claude CLI answers, pipe-friendly, model shortcuts
  - `review` — AI code review on git diffs (staged, unstaged, or commit range)
  - `aicommit` — AI-generated commit messages with approve/edit/abort flow
  - `sessions` — Claude session browser and resume picker
  - `project` — fzf project launcher with Claude/Cursor/IDE integration
  - `cask` — quick Cursor Agent tasks from the command line
- Utilities
  - `killport` — find and kill processes by port number
  - `dotbackup` — backup/restore dotfiles + Claude agents to iCloud
  - `update-check` — checks Claude CLI, brew, dotfile freshness
- Secrets Manager — store API keys in macOS Keychain instead of plaintext
- Plugin System — drop executables in `plugins/` with TOOLKIT_NAME header
- Mac Bootstrap — Brewfile export/import, macOS preferences, full setup
- Subcommand CLI — `toolkit ask`, `toolkit review`, `toolkit help`, etc.
- Shell Startup Hook — background update check with subtle terminal alert
- Auto-generated Brewfile — current packages exported for new Mac setup

### Fixed
- Docker aliases (`drm`, `drmi`) now use single quotes (execute at runtime)
- `claudeme` models updated to current: sonnet-4-6, opus-4-6, haiku-4-5
- `ttyd` now runs with `--writable` flag for mobile keyboard input

### Plugins included
- `wifi-password` — show current Wi-Fi password from Keychain
- `cleanup` — free disk space (caches, logs, trash, Docker prune)

## 1.0.0 — 2026-03-14 (initial)
- Interactive menu with Docker Manager, Remote Terminal, Claude, AICoder
- iCloud sync, portable installer, aliases, env template
