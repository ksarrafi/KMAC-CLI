# KMac FAQ — Answers to Common Questions

**If you're stuck, search this page. Most problems are covered.**

---

## Getting Started

### "I installed KMac but `kmac` command doesn't work"

**Problem:** Bash can't find the kmac command.

**Solution:**
1. Reload your shell: `source ~/.zshrc`
2. If still not found, check the install:
   ```bash
   which kmac
   # Should show: /Users/username/.local/bin/kmac or /usr/local/bin/kmac
   ```
3. If empty, reinstall:
   ```bash
   brew tap ksarrafi/kmac
   brew install kmac
   ```

---

### "I see 'API key not configured' error"

**Problem:** Claude commands fail because your API key isn't set.

**Solution:**
1. Get a free API key: https://console.anthropic.com/dashboard/keys
2. Store it in the vault:
   ```bash
   kmac vault set anthropic sk-ant-your-key-here
   ```
3. Or set it in your shell:
   ```bash
   export ANTHROPIC_API_KEY="sk-ant-your-key-here"
   ```
4. Try the command again: `kmac ask "test"`

**To avoid this every time:**
Add to your `~/.zshrc`:
```bash
export ANTHROPIC_API_KEY="sk-ant-your-key-here"
```

---

### "Which install method should I use?"

**Quick answer:** Use Homebrew.

```bash
brew tap ksarrafi/kmac
brew install kmac
```

**Why?**
- Easiest (one command)
- Auto-updates
- Works on any Mac (not tied to home directory)

**Alternative installs:**
- **Git clone:** If you want latest dev version or plan to contribute
- **iCloud Drive:** If you sync dotfiles across multiple Macs

---

## Commands & Features

### "What's the difference between `kmac ask` and `kmac review`?"

| Command | What It Does | Input | Output |
|---------|-------------|-------|--------|
| **ask** | Ask Claude anything | Your question (free text) | Claude's analysis |
| **review** | AI code review | Your git diff | Structured feedback |
| **aicommit** | Generate commit message | Your staged changes | Conventional commit message |

**When to use each:**
- `kmac ask "why is my disk full?"` — General question
- `kmac review` — Before committing code
- `kmac aicommit` — After staging files

---

### "I pressed ? and nothing happened"

**Problem:** Help menu didn't open or is showing health check.

**Solution:**
- Make sure you're in the main menu: `kmac` (no arguments)
- Press `?` (question mark, not Shift+?)
- You should see either:
  - **Interactive help menu** (if it's your first run or after update)
  - **fzf search** (if fzf is installed) — type to search
  - **Category browser** (fallback)

**If still nothing:**
- Try `kmac help` (command line version)
- Try `kmac D` (dependencies menu) to check if system is healthy

---

### "How do I use interactive Claude mode?"

**Problem:** You want multi-turn conversation, not just one question.

**Solution:**
```bash
kmac ask
# System loads...
❯ first question
# Claude responds...
❯ follow-up question  
# Claude responds...
❯ another question
❯ exit
```

**Or use specific model:**
```bash
kmac ask -m opus -i
# -m opus = use best model
# -i = interactive mode
```

---

### "Why is `kmac status` not showing anything?"

**Problem:** Command runs but shows no output.

**Solution:**
1. Try `kmac ?` instead (quick health check)
2. Or use: `kmac ask "what's my system status?"`
3. If neither works, check API key:
   ```bash
   kmac vault get anthropic
   # Should show your API key (first 10 chars only)
   ```

---

## Docker & Infrastructure

### "Docker commands don't work; 'Docker not running'"

**Problem:** Docker daemon isn't running.

**Solution:**
1. Start Docker:
   ```bash
   open -a Docker
   # Waits ~30 seconds to start
   ```
2. Check it's running:
   ```bash
   kmac docker health
   # Should show running containers
   ```

**To auto-start Docker on login:**
- Open Docker preferences → General → "Start Docker Desktop when you login"

---

### "I'm running out of disk space"

**Problem:** Disk is 85%+ full.

**Solution:**
1. See what's using space:
   ```bash
   kmac storage scan
   kmac storage big
   ```
2. Clean up safely:
   ```bash
   kmac houseclean run
   # Removes caches + dangling Docker images (never touches volumes)
   ```
3. Migrate old files:
   ```bash
   kmac storage icloud
   # Moves old files to iCloud (keeps shortcuts locally)
   ```

---

### "Docker cleanup failed / 'permission denied'"

**Problem:** Cleanup can't remove some Docker objects.

**Solution:**
1. Make sure Docker is running: `open -a Docker`
2. Try again with admin context:
   ```bash
   sudo kmac docker cleanup
   ```
3. Or inspect what's stuck:
   ```bash
   docker ps -a
   docker images
   # See what's taking space
   ```

---

## Secrets & Configuration

### "Where are my secrets stored?"

**Answer:** Depends on your vault backend.

```bash
# Check current backend
kmac vault backend
# Shows: keychain, file, or docker
```

**Locations:**
- **Keychain:** In macOS Keychain (locked by your login password)
- **File:** `~/.config/kmac/vault.enc` (AES-256 encrypted)
- **Docker:** Running in local Docker container `kmac-vault`

---

### "I lost my master password (encrypted file vault)"

**Problem:** You used encrypted file backend and forgot the master password.

**Solution:**
1. Reset the vault:
   ```bash
   rm ~/.config/kmac/vault.enc
   ```
2. Recreate it with new password:
   ```bash
   kmac vault set anthropic sk-ant-your-new-key
   # Prompts for new master password
   ```
3. Re-enter all your API keys

**Better approach:** Use Keychain backend (no master password needed).

---

### "I want to switch vault backends"

**Steps:**
1. Check current: `kmac vault backend`
2. Export current (if not Keychain):
   ```bash
   kmac secrets export
   # Saves to secrets-backup.json
   ```
3. Switch backend:
   ```bash
   kmac vault backend keychain
   # Or: file, docker
   ```
4. Re-import if needed:
   ```bash
   kmac secrets import secrets-backup.json
   ```

---

## System Health & Monitoring

### "Health check says missing dependencies"

**Problem:** `kmac ?` (health check) shows red X marks.

**Solution:**
1. See what's missing:
   ```bash
   kmac D
   # Shows all deps with install hints
   ```
2. Install missing (optional ones):
   ```bash
   brew install fzf      # For faster help search
   brew install jq       # For JSON parsing
   brew install bat      # For code display
   ```
3. Required deps that are missing will block features

---

### "Memory/CPU is high in menu status bar"

**Problem:** You see red colors in system stats.

**Solution:**
1. Check what's using it:
   ```bash
   kmac ask "what's using my CPU?"
   # Claude analyzes top processes
   ```
2. Kill a specific process:
   ```bash
   kmac killport 3000
   # Kills process on port 3000
   ```
3. Check running services:
   ```bash
   kmac docker health
   kmac server status
   ```

---

## Advanced & Troubleshooting

### "I want to reset everything and start fresh"

**Steps:**
1. Backup current config:
   ```bash
   kmac dotbackup
   ```
2. Remove KMac data:
   ```bash
   rm -rf ~/.config/kmac
   rm -rf ~/.cache/kmac
   ```
3. Reinstall:
   ```bash
   brew reinstall kmac
   ```
4. Reconfigure:
   ```bash
   kmac vault set anthropic sk-ant-...
   kmac vault set github ghp_...
   ```

---

### "Commands work but they're really slow"

**Problem:** `kmac ask` takes 10+ seconds.

**Likely causes:**
1. **Network latency:** Claude API is slow (check https://status.anthropic.com)
2. **First run:** First command builds cache (subsequent ones faster)
3. **Heavy system:** CPU/memory maxed out; try `kmac houseclean run`

**Solutions:**
1. Check network: `kmac network`
2. Run in background: `kmac ask "..." &`
3. Use faster model: `kmac ask -m haiku "quick question"`

---

### "I'm getting authentication errors with GitHub/Docker"

**Problem:** Commands fail with auth errors.

**Solution:**
1. Check token is set:
   ```bash
   kmac vault get github
   # Should show token (first 10 chars)
   ```
2. Regenerate token:
   - GitHub: https://github.com/settings/tokens
   - Docker: `docker login`
3. Update vault:
   ```bash
   kmac vault set github ghp_your-new-token
   kmac vault set docker ...  # if applicable
   ```

---

### "fzf doesn't work / help is slow"

**Problem:** Help search is sluggish or fzf not available.

**Solution:**
1. Install fzf:
   ```bash
   brew install fzf
   ```
2. Test it:
   ```bash
   kmac ?
   # Should show "Fast search" option now
   ```
3. If still slow, check system:
   ```bash
   kmac ?
   # Then press h for health check
   ```

---

## Multi-Mac & Sync

### "How do I sync KMac across multiple Macs?"

**Option 1: iCloud (recommended)**
```bash
# Clone to iCloud
git clone ~/KMac-CLI ~/Library/CloudStorage/iCloudDrive/Scripts/toolkit

# On other Mac
bash ~/Library/CloudStorage/iCloudDrive/Scripts/toolkit/install.sh
```

**Option 2: Dotfiles backup**
```bash
kmac dotbackup       # On Mac 1
kmac dotbackup restore  # On Mac 2
```

**Option 3: Manual sync**
```bash
# Export settings
kmac vault backend file  # Use encrypted file backend
# Then sync ~/.config/kmac across machines
```

---

### "I have KMac on two Macs; configs got out of sync"

**Problem:** Vault/settings differ between machines.

**Solution:**
1. Export from Mac A:
   ```bash
   kmac vault export > kmac-config.json
   ```
2. Transfer file to Mac B (via iCloud, email, etc.)
3. Import on Mac B:
   ```bash
   kmac vault import kmac-config.json
   ```

---

## Platform-Specific Issues

### "I'm on Linux; does KMac work?"

**Answer:** Mostly. With caveats.

**What works:**
- All CLI commands (ask, review, aicommit, docker, etc.)
- Python server and web UI
- Remote access

**What doesn't:**
- macOS-specific: Keychain vault backend
- iOS app (only on iPhone)
- Menu bar app (only on macOS)

**Install on Linux:**
```bash
git clone https://github.com/ksarrafi/KMAC-CLI.git
cd KMAC-CLI
bash install.sh
# Select encrypted file or Docker vault backend (not Keychain)
```

---

### "I'm on an M1/M2 Mac; are there compatibility issues?"

**Answer:** No. KMac works fine on ARM Macs.

**What might be slow:**
- Docker with Intel images (gets translated via Rosetta)
- Some older tools that aren't ARM-native

**Solution:**
```bash
# Check if tools are native ARM
kmac software list
# Reinstall non-native tools:
brew reinstall --cask docker
```

---

## Still Stuck?

**Try these in order:**

1. **Check health:**
   ```bash
   kmac doctor
   ```

2. **Check API key:**
   ```bash
   kmac vault get anthropic
   ```

3. **Ask Claude directly:**
   ```bash
   kmac ask "how do I [your problem]?"
   ```

4. **Check logs:**
   ```bash
   ls ~/.config/kmac/logs/
   tail -50 ~/.config/kmac/logs/*.log
   ```

5. **Search this FAQ:**
   - Use browser find (Ctrl+F or Cmd+F)
   - Or search GitHub issues: https://github.com/ksarrafi/KMAC-CLI/issues

6. **Open an issue:**
   - Include: your OS, KMac version (`kmac --version`), steps to reproduce
   - Paste: output from `kmac doctor`

---

## Version & Updates

### "What version am I running?"

```bash
kmac --version
# Shows: KMac v3.3.0 [components...]
```

### "How do I update?"

```bash
# Via Homebrew
brew upgrade kmac

# Via git
cd ~/Projects/KMac-CLI
git pull origin main
bash install.sh

# Check what changed
kmac --whatsnew
```

---

## Tips & Tricks

### "How do I make KMac faster to access?"

1. **Keyboard shortcut** (macOS):
   - System Settings → Keyboard → Shortcuts → Custom
   - Add: Run `open -a Terminal && echo 'kmac'`

2. **Alias in shell:**
   ```bash
   alias k="kmac"
   # Now just type: k ask "question"
   ```

3. **Spotlight** (if using menu bar app):
   - Cmd+Space → type "kmac" → Enter

### "Can I script KMac in a CI/CD pipeline?"

**Yes:**
```bash
# In GitHub Actions, GitLab CI, etc:
export ANTHROPIC_API_KEY=${{ secrets.ANTHROPIC_API_KEY }}

# Run commands
kmac review HEAD~1..HEAD
kmac aicommit

# Capture output
result=$(kmac ask "is this safe?")
echo "$result"
```

---

## Quick Links

- **Installation:** See [FIRST_5_MINUTES.md](FIRST_5_MINUTES.md)
- **All commands:** See [COMMAND_TAXONOMY.md](COMMAND_TAXONOMY.md)
- **How to do things:** See [COOKBOOK.md](COOKBOOK.md)
- **Vault setup:** See [VAULT_GUIDE.md](VAULT_GUIDE.md)
- **GitHub:** https://github.com/ksarrafi/KMAC-CLI

---

**Last updated:** 2026-07-12  
**Found a question that should be here?** File an issue or PR! 🙌
