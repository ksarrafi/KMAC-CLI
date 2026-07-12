# Your First 5 Minutes with KMac

**Get from "just installed" to "I see it working" in 5 minutes. No background reading.**

---

## Step 1: Verify Installation (1 min)

Type this in your terminal:

```bash
kmac
```

You should see the KMac menu with a logo, status bar (showing services), and 30+ command options.

**If you see "command not found: kmac":**
- Run: `source ~/.zshrc` (reload your shell)
- Try again

**Success:** Menu appears. ✓

---

## Step 2: Try Your First Command (2 min)

Run this exact command:

```bash
kmac ask "what are my top 3 active processes?"
```

Claude will analyze your system and respond with your top CPU-using processes.

**What just happened:**
- KMac sent your system info to Claude (the AI)
- Claude analyzed it and returned insights
- No data was stored; this is a one-time question

**If you get "API key not configured":**
1. Get a free API key: https://console.anthropic.com/dashboard/keys
2. Set it: `export ANTHROPIC_API_KEY='sk-ant-your-key'` (paste your actual key)
3. Try the command again

**Success:** Claude responded with system analysis. ✓

---

## Step 3: Try the Menu (1 min)

Type:

```bash
kmac
```

The menu appears. Press these keys (no Enter needed):

- **`a`** — Ask Claude a question (like step 2, but interactive)
- **`?`** — Health check (shows your CPU, disk, memory)
- **`v`** — Code review (if you're in a git repo with staged changes)

Try one. After each, press any key to return to the menu. Press **`0`** to exit.

**Success:** You navigated the menu. ✓

---

## You're Done! 🎉

You've installed KMac and used Claude. You now know:

- **`kmac`** opens the menu
- **`kmac ask "question"`** asks Claude anything
- **`?`** shows your system health
- **`0`** exits

---

## Next Steps

**Want to use it more?**

- Read **PLATFORM_GUIDE.md** (2 min) — Explains which tool to use for what
- Read **README.md** (10 min) — All features at a glance
- Read **VAULT_GUIDE.md** — How to safely store API keys and secrets

**Want code review, commits, or Docker commands?**

These use the same menu. Just press `v` (review), `c` (commit), or `d` (Docker). Each has its own sub-menu.

**Setup is optional.** You can:

- Skip the menu and use commands directly: `kmac aicommit`, `kmac review`, `kmac docker health`
- Add Claude API key to `~/.zshrc` so you don't need to set it each time (see step 2)
- Set up automatic monitoring (see VAULT_GUIDE.md)

---

**Stuck?** See README.md Troubleshooting section or try `kmac ask "why is this not working?"`

**Enjoy.** 🚀
