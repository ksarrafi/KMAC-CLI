# Changelog

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
