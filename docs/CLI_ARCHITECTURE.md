# KMac CLI Architecture: Bash Toolkit vs Swift CLI

**This clarifies the "which CLI?" confusion: KMac has two command-line interfaces. This guide explains when to use each.**

---

## Quick Answer

**Use Bash Toolkit (Official):**
```bash
kmac ask "question"      # Recommended for everyone
kmac review --staged
kmac aicommit
```

**Swift CLI is in development:**
- Not recommended for daily use yet
- Available at `kmac-cli/` directory for contributors
- Will eventually replace Bash toolkit once feature-parity achieved

---

## The Two CLIs Explained

| Aspect | Bash Toolkit (Current) | Swift CLI (Future) |
|--------|----------------------|-------------------|
| **Status** | ✅ Production-ready | 🔧 In development |
| **Where** | `/scripts/` (symlink to `~/bin/kmac`) | `kmac-cli/Package.swift` (build from source) |
| **Install** | `brew install kmac` or `bash install.sh` | Manual Swift build (not recommended) |
| **Features** | All 40+ commands | Subset (under development) |
| **Recommended** | YES — use this | NO — for contributors only |
| **Cross-platform** | macOS + Linux | macOS only (currently) |
| **Development** | Bash (easy to modify) | Swift (type-safe, compiled) |

---

## Why Two CLIs?

### Historical Context

**Bash Toolkit (Current):**
- Started as shell scripts for personal automation
- Grew into full toolkit (40+ commands)
- Portable, easy to modify, works anywhere Bash runs
- Used in production by KMac users

**Swift CLI (Planned):**
- Started as experiment to explore type safety + compilation
- Goal: replace Bash with compiled, faster, more maintainable CLI
- Would integrate with native macOS apps (KMac-MenuBar, iOS app)
- **Status:** Prototype phase. Not feature-complete yet.

### Migration Path

```
Now (2026-07)      ~2026-Q3          ~2026-Q4
────────────────────────────────────────────
Bash Toolkit       Bash Toolkit      Swift CLI
(all 40+ cmds)  +  (all 40+ cmds)    (all features)
                   
                   Swift becomes
                   feature-parity
```

**For most users:** No change needed. You'll keep using `kmac ask`, `kmac review`, etc. The transition will be transparent.

---

## Detailed Comparison

### Bash Toolkit

**Location:** `~/.local/bin/kmac` (symlink) → `$TOOLKIT_DIR/toolkit.sh`

**Install:**
```bash
# Via Homebrew (easiest)
brew tap ksarrafi/kmac
brew install kmac

# Via git clone
git clone https://github.com/ksarrafi/KMAC-CLI.git ~/Projects/KMac-CLI
cd ~/Projects/KMac-CLI && bash install.sh
```

**Architecture:**
```
toolkit.sh (main entry)
├── scripts/ask         (Ask Claude)
├── scripts/review      (Code review)
├── scripts/aicommit    (Commit message)
├── scripts/docker      (Docker manager)
├── scripts/project     (Project launcher)
├── scripts/storage     (Disk analysis)
└── scripts/vault       (Secret management)
```

**Why it's good:**
- Easy to inspect/modify (shell scripts)
- No compilation needed
- Works on macOS + Linux
- Battle-tested in production
- 40+ commands, all working

**Why it's limited:**
- Shell scripts are slower than compiled
- No type safety (easy to break)
- Hard to integrate with native apps (iOS, macOS UI)
- Not portable to Windows easily

---

### Swift CLI (Future)

**Location:** `kmac-cli/Package.swift`

**Status:** ❌ Not recommended yet. Missing 50% of features.

**Architecture:**
```
kmac-cli/Package.swift (Swift package)
├── Sources/KMacCore/
│   ├── SystemMonitor.swift
│   ├── ProcessRunner.swift
│   ├── ClaudeAPI.swift
│   ├── FixExecutor.swift
│   └── Logger.swift
└── KMacSharedFramework/
    (shared components with iOS app)
```

**Why it's planned:**
- Compiled = faster startup (50-100ms vs 200-500ms)
- Type-safe = fewer bugs
- Shareable with iOS app (same code)
- Native macOS integration
- Eventually: could have native CLI UI (instead of text)

**Why it's not ready:**
- Missing: research, assistant, orchestrator, pilot, PDAC, plugins
- Need: Swift equivalents of bash helper functions
- Need: Plugin system redesign (currently bash-only)
- Need: Feature parity before production recommendation

---

## If You Find Both Installed

**You likely have:**
1. Bash Toolkit (from Homebrew or git) — in `~/.local/bin/` or `~/Projects/KMac-CLI/`
2. Swift CLI (from git clone) — in `kmac-cli/` directory (not installed globally)

**What to do:**
- **Use:** `kmac` (Bash) for all commands
- **Ignore:** `kmac-cli/` for now (it's a work-in-progress)
- **Optional:** If you're a contributor, you can build and test Swift CLI:
  ```bash
  cd kmac-cli && swift build
  ./.build/debug/kmac --help
  ```

---

## Common Questions

### "Which one should I install?"

**Answer:** If you're using Homebrew, you already have the right one:
```bash
brew tap ksarrafi/kmac
brew install kmac
```

This installs the Bash Toolkit. Done. Nothing else needed.

### "Can I use both?"

**Answer:** Yes, they won't conflict. But you'd need to:
1. Install Bash Toolkit (official): `brew install kmac`
2. Build Swift CLI manually: `cd kmac-cli && swift build`
3. Use Swift CI by path: `./.build/debug/kmac` or add to PATH

**You probably don't want to do this unless you're testing.**

### "Will my commands break when Bash switches to Swift?"

**Answer:** No. Commands will stay the same:
```bash
# Works now (Bash)
kmac ask "question"

# Will still work after switch (Swift)
kmac ask "question"
```

The switch is internal; user-facing commands never change.

### "Should I wait for Swift version?"

**Answer:** No. Use the Bash Toolkit now. It's production-ready and feature-complete. The Swift version is for future optimization and integration, not because Bash is broken.

### "Is the Bash Toolkit dying?"

**Answer:** No. The Bash Toolkit will remain in the repo and be maintained during the Swift transition. The goal is:
- Q3 2026: Swift CLI reaches feature parity
- Q4 2026: Both available; Bash becomes "legacy but maintained"
- 2027+: Swift is primary; Bash kept as fallback

### "Can I contribute to Swift CLI?"

**Answer:** Yes! See `kmac-cli/README.md` and `docs/CONTRIBUTING.md`. The Swift CLI is actively being built and contributions are welcome:
- Missing commands (research, assistant, pilot)
- Plugin system redesign
- Testing & bug fixes
- Documentation

---

## Technical Details

### Shared Components

Both Bash and Swift CLIs will eventually use `KMacSharedFramework`:

```
KMacSharedFramework/
├── Logger.swift         (used by both)
├── ProcessRunner.swift  (used by both)
├── ClaudeAPI.swift      (used by both)
├── FixExecutor.swift    (used by both)
└── SystemMonitor.swift  (used by both)
```

This means:
- **Now:** Bash has its own implementations; Swift uses SharedFramework
- **Future:** Bash will migrate to SharedFramework too
- **Result:** Same behavior; reduced duplication

### Why this matters

When you run `kmac status`, you'll get:
- **Bash version:** Runs native Bash, reads from `~/.kmac/` config
- **Swift version:** Runs compiled Swift, reads from same `~/.kmac/` config
- **Same data:** Status output identical (both read same system info)

---

## Decision Tree

```
Do I have KMac installed?
├─ YES (via Homebrew or git install.sh)
│  └─ Use: `kmac ask "..."` (Bash Toolkit, recommended)
│
├─ NO
│  └─ Install: `brew install kmac`
│     Then use: `kmac ask "..."`
│
└─ I'm a contributor/experimenter
   ├─ Test Bash: `kmac` (already installed)
   ├─ Test Swift: `cd kmac-cli && swift build && ./.build/debug/kmac`
   └─ Help with: Missing Swift features, plugin system, testing
```

---

## Checklist: You're Using the Right CLI If...

- [ ] You installed via Homebrew or `bash install.sh`
- [ ] You run `kmac ask "question"` (not a compiled path)
- [ ] Commands work (review, aicommit, docker, etc.)
- [ ] Help shows: `Press ? for help | Type kmac ask to skip menu`
- [ ] Vault/secrets work: `kmac vault list`

If all yes → You're using Bash Toolkit. Perfect. Don't worry about Swift CLI yet.

---

## When to Revisit This

**Check back if:**
- You want to contribute to the Swift CLI
- You're building from git and see conflicting CLI paths
- You're on the macOS 14+ and want native integration (future)
- You hit a performance issue (want to test Swift version)

**Otherwise:** Don't worry. The Bash Toolkit is production-ready and will remain your primary interface for the foreseeable future.

---

**Bottom line:** Use `kmac` as you normally do. Everything works. The Swift CLI is a future optimization, not a replacement for a broken tool.
