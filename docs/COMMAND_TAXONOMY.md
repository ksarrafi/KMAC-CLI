# KMac Command Taxonomy

**Every KMac command fits one of 5 categories. Use this to find what you need.**

---

## Categories at a Glance

| Category | Purpose | Example | Use When |
|----------|---------|---------|----------|
| **Query** | Get information about your Mac | `kmac ask`, `kmac docker health` | You want to understand something |
| **Modify** | Change code, configs, or system state | `kmac aicommit`, `kmac heal` | You want to make a change |
| **Serve** | Run a server or background service | `kmac server start`, `kmac pdac start` | You need a always-on service |
| **Manage** | Configure settings, credentials, extensions | `kmac vault set`, `kmac software install` | You're setting up or configuring |
| **Utility** | Low-level helpers and debugging | `kmac killport 3000`, `kmac storage scan` | You're troubleshooting or cleaning |

---

## 1. Query Commands (Get Information)

**These commands ask questions and return answers. Non-destructive.**

| Command | What It Does | Example |
|---------|-------------|---------|
| **ask** | Ask Claude anything | `kmac ask "why is my CPU high?"` |
| **review** | AI code review of your git changes | `kmac review --staged` |
| **docker health** | Check Docker container status | `kmac docker health` |
| **docker crashes** | See recent container crashes | `kmac docker crashes` |
| **network** | Show local/public IP, Wi-Fi, gateway | `kmac network` |
| **storage scan** | Analyze disk usage by folder | `kmac storage scan` |
| **status** / `?` | System health (CPU, memory, disk) | `kmac ?` |
| **sessions list** | View recent Claude sessions | `kmac sessions list` |
| **user-monitors list** | Show configured health monitors | `kmac user-monitors list` |
| **research** (view) | Check status of autonomous experiments | `kmac research status` |
| **pdac** (query) | Database query tool | `kmac pdac open` |

**Pattern:** Can be run repeatedly; won't break anything.

---

## 2. Modify Commands (Make Changes)

**These commands change code, files, or configuration. Use with caution.**

| Command | What It Does | Example | Destructive? |
|---------|-------------|---------|--|
| **aicommit** | Generate & commit staged changes with AI message | `kmac aicommit` | ✗ Reversible (git reset) |
| **heal** | AI-powered bash script repair and reload | `kmac heal scriptname` | ⚠️ Backup before applying |
| **houseclean** | Safe automated disk cleanup (caches + Docker prune) | `kmac houseclean run` | ⚠️ Deletes caches |
| **storage icloud** | Migrate old files to iCloud Drive | `kmac storage icloud` | ⚠️ Moves files |
| **dotbackup** | Backup/restore dotfiles + config | `kmac dotbackup` | ✗ Reversible (restore mode) |
| **software install** | Install developer tools | `kmac software install node` | ✗ Reversible (uninstall) |
| **setup-mac** | Bootstrap new Mac with config | `kmac setup-mac` | ⚠️ Major setup |
| **research init** | Start new autonomous experiment project | `kmac research init` | ✗ Creates folder |
| **ollama-setup install** | Install Ollama + download models | `kmac ollama-setup install` | ✗ Reversible |

**Pattern:** Most are reversible; some delete cached data. See `--dry-run` flags.

---

## 3. Serve Commands (Run Servers)

**These commands start background services. Typically long-running.**

| Command | Service | Purpose | Example |
|---------|---------|---------|---------|
| **server start** | KMac Pilot Server | Remote Mac control, API access | `kmac server start` |
| **pdac start** | PDAC Database UI | Query tool with web interface | `kmac pdac start` |
| **remote-access setup** | ngrok tunnel + ttyd | Remote terminal access | `kmac remote-access setup` |
| **resource-watch daemon** | Background watchdog | Monitor CPU/disk, alert on spike | `kmac resource-watch daemon` |
| **assistant start** | Claude Agent | Multi-turn session gateway | `kmac assistant start` |
| **ollama serve** | Local LLM server | Run local AI models | `kmac ollama-setup models` |
| **docker-compose up** | Full stack | All KMac services in Docker | See `server` for docker-up |

**Pattern:** Use `stop` / `restart` / `status` / `logs` to manage. Usually optional.

---

## 4. Manage Commands (Configure)

**These commands set up and configure. Used once, then forgotten.**

| Command | Configures | Example |
|---------|------------|---------|
| **vault set** / **vault get** | Store/retrieve API keys and secrets | `kmac vault set anthropic sk-ant-...` |
| **secrets** | Credential picker and test integrations | `kmac secrets` (interactive) |
| **vault** | Triple-backend secret management | `kmac vault backend docker` |
| **install** | Bootstrap KMac tooling on new Mac | `kmac install` |
| **software install** | Developer tool installation | `kmac software install git` |
| **ollama-setup** | Local LLM configuration | `kmac ollama-setup` |
| **project** (add) | Add new project to launcher | `kmac project -a path/to/project` |
| **setup-mac** | Full Mac bootstrap (one-time) | `kmac setup-mac` |
| **dotbackup restore** | Restore config to new Mac | `kmac dotbackup restore` |

**Pattern:** Run once during setup; rarely again. Safe to re-run.

---

## 5. Utility Commands (Low-Level)

**These commands help with debugging, cleanup, and special tasks.**

| Command | Purpose | Example |
|---------|---------|---------|
| **killport** | Find and kill process on a port | `kmac killport 3000` |
| **docker cleanup** | Prune Docker objects safely | `kmac docker cleanup` |
| **houseclean inspect** | Preview what will be cleaned | `kmac houseclean inspect` |
| **storage big** | Show largest folders/files | `kmac storage big` |
| **network info** | Show connectivity details | `kmac network info` |
| **release** | Create version tag and update Homebrew formula | `kmac release 3.4.0` |
| **pdac-mcp** | Run schema MCP for Cursor/Claude Desktop | `kmac pdac-mcp` |
| **resource-watch check** | Manual health check | `kmac resource-watch check` |
| **doctbackup diff** | See what's changed since last backup | `kmac dotbackup diff` |

**Pattern:** Special-purpose; usually one-off usage.

---

## Finding Commands by Task

**What do you want to do?**

| Task | Category | Commands |
|------|----------|----------|
| **Ask Claude a question** | Query | `kmac ask` |
| **Get code review** | Query | `kmac review [--staged]` |
| **Generate commit message** | Modify | `kmac aicommit` |
| **Check system health** | Query | `kmac ?` or `kmac status` |
| **Manage Docker** | Query/Modify/Serve | `kmac docker [health/crashes/cleanup]` |
| **Store API key safely** | Manage | `kmac vault set anthropic <key>` |
| **Clean up disk space** | Modify | `kmac houseclean run` |
| **Analyze storage usage** | Query | `kmac storage scan` |
| **Find process on port** | Utility | `kmac killport 3000` |
| **Start remote Mac control** | Serve | `kmac server start` |
| **Autonomous experiment** | Query/Modify/Serve | `kmac research [init/run/status]` |
| **Launch a project** | Manage | `kmac project [ProjectName]` |
| **Backup dotfiles** | Modify | `kmac dotbackup` |
| **Fix failing script** | Modify | `kmac heal scriptname` |
| **View conversation history** | Query | `kmac sessions list` |
| **Open database tool UI** | Serve | `kmac pdac open` |
| **Run local LLM** | Serve | `kmac ollama-setup install` |

---

## Command Naming Patterns

**Once you know the pattern, you can guess command names:**

### Pattern 1: `kmac <action> <target>`
```
kmac ask "question"           ← ask (action) + question (target)
kmac docker health            ← docker (action) + health (target)
kmac review --staged          ← review (action) + staged (target)
kmac vault set anthropic key  ← vault (action) + set (subaction) + name + value
```

### Pattern 2: `kmac <tool> <command>`
```
kmac server start             ← server (tool) + start (command)
kmac pdac open                ← pdac (tool) + open (command)
kmac research init            ← research (tool) + init (command)
kmac ollama-setup install     ← ollama-setup (tool) + install (command)
```

### Pattern 3: `kmac <noun>` (minimal)
```
kmac ?                        ← health check
kmac status                   ← system status
kmac network                  ← network info
```

**Principle:** Shorter = more common. Longer = more specific.

---

## Quick Command Finder

**If you know what you want, find it here:**

**I want to... ask Claude**
→ `kmac ask "your question"` or `kmac ask` (interactive)

**I want to... review my code**
→ `kmac review` (uncommitted) or `kmac review --staged` (only staged)

**I want to... generate a commit message**
→ `kmac aicommit` or `kmac aicommit --staged`

**I want to... check my system**
→ `kmac ?` (quick) or `kmac status` (detailed)

**I want to... manage Docker**
→ `kmac docker health` (status) or `kmac docker cleanup` (clean) or `kmac docker crashes` (debug)

**I want to... store a secret**
→ `kmac vault set <name> <value>` (e.g., `kmac vault set anthropic sk-ant-...`)

**I want to... clean disk space**
→ `kmac houseclean run` (auto-clean) or `kmac storage scan` (analyze) or `kmac storage big` (show biggest)

**I want to... find what's using a port**
→ `kmac killport 3000`

**I want to... set up remote access**
→ `kmac server start` (API) or `kmac remote-access setup` (terminal)

**I want to... run local AI**
→ `kmac ollama-setup install`

**I want to... view conversation history**
→ `kmac sessions list` or `kmac sessions last`

**I want to... bootstrap a new Mac**
→ `kmac setup-mac` or `kmac dotbackup restore`

---

## By Frequency of Use

**Most Common (Use Daily):**
```
kmac ask           → ask Claude questions
kmac aicommit      → generate commits
kmac ?             → check system health
kmac docker health → Docker status
```

**Regular Use (Weekly):**
```
kmac review        → code review
kmac storage scan  → disk analysis
kmac houseclean    → cleanup
kmac vault set     → configure secrets
```

**Occasional (Setup/Maintenance):**
```
kmac server start      → remote access
kmac setup-mac         → new Mac bootstrap
kmac software install  → install tools
kmac dotbackup         → backup config
kmac research          → experiments
```

**Rare (Debugging/Special):**
```
kmac killport          → find process
kmac heal              → fix scripts
kmac pdac-mcp          → Cursor integration
kmac resource-watch    → detailed monitoring
```

---

## Notes

- All commands support `--help` for details
- Most are idempotent (safe to re-run)
- Use `--dry-run` flags when available to preview changes
- Query commands never modify your system
- Modify commands are mostly reversible (git, dotfiles) or safe (caches, Docker)

---

**Still confused?** Run `kmac ask "how do I ..."` and Claude will guide you. That's what it's for. 🚀
