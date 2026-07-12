# KMac Platform Guide — Which Tool to Use?

**KMac has multiple interfaces. This guide helps you pick the right one for your needs.**

---

## Quick Decision Tree

```
Do you want to...                               Use...
─────────────────────────────────────────────────────
Ask Claude a quick question?                    Bash CLI
  (from terminal, scriptable)                   ↓ kmac ask "..."

Ask Claude repeatedly in a session?             Interactive mode
  (multiple questions, back-and-forth)          ↓ kmac ask

Do code review, commits, AI fixes?              Bash CLI / Menu
  (terminal workflows)                          ↓ kmac review, kmac aicommit

Manage Docker, servers, or services?            Bash CLI / Menu
  (infrastructure tasks)                        ↓ kmac docker health

Need a visual interface?                        KMac MenuBar (macOS)
  (see status at a glance, click actions)       ↓ Launch from Applications

Access KMac from your iPhone?                   iOS App
  (remote monitoring, quick actions)            ↓ App Store

Need programmatic access?                       Python Server + API
  (build tools on top of KMac)                  ↓ See SERVER_GUIDE.md
```

---

## Detailed Platform Breakdown

### 1. Bash CLI (Primary — Start Here)

**What it is:** Terminal interface. Single keystroke or direct commands.

**When to use:**
- You want CLI integration (scripts, aliases, piping)
- You're in a terminal already
- You want to automate tasks
- You need speed (no GUI load time)

**Examples:**
```bash
kmac ask "explain this error"
kmac aicommit                    # Generate commit message
kmac review                      # Code review from diff
kmac docker health              # Check Docker status
kmac vault set anthropic KEY    # Store secret safely
```

**Launch:**
```bash
kmac              # Open menu
kmac ask "..."    # Direct command
```

**Pros:**
- Fastest (no GUI overhead)
- Scriptable (pipe data in/out)
- Works over SSH
- Minimal dependencies

**Cons:**
- Text-only (no visual feedback)
- 40+ commands to learn

**Good for:** Developers, terminal-first workflows, automation

---

### 2. Interactive Menu (Built into Bash CLI)

**What it is:** Press `kmac`, navigate with single-letter keys.

**When to use:**
- First time discovering features
- Exploring available commands
- Need a guided workflow

**Launch:**
```bash
kmac
```

Then press:
- **`a`** — Ask Claude
- **`v`** — Code review
- **`c`** — AI commit
- **`d`** — Docker manager
- **`?`** — Show help

**Pros:**
- Visual menu (easy discovery)
- Single keypress navigation
- Status bar shows running services
- Built-in help system

**Cons:**
- Can't automate
- Not scriptable

**Good for:** Learning, occasional users, quick status checks

---

### 3. KMac MenuBar App (macOS GUI)

**What it is:** Native macOS app. Lives in your menu bar. Visual interface.

**When to use:**
- You want visual status at a glance
- You prefer clicking over typing commands
- You're doing repeated workflows

**Status indicators:**
- CPU, memory, disk usage
- Docker container count
- Git branch/uncommitted changes
- Remote terminal status

**Features:**
- One-click actions (start Docker, check health, ask Claude)
- Keyboard shortcuts
- Notifications for high CPU/disk
- Settings panel

**Launch:**
- Open Applications → KMac-MenuBar
- Add to Dock for quick access

**Pros:**
- Visual (status always visible)
- Quick one-click actions
- Runs in background
- Native macOS experience

**Cons:**
- macOS only
- Not scriptable
- Separate from CLI (different window)

**Good for:** Status monitoring, occasional quick actions, visual learners

---

### 4. iOS App (iPhone/iPad)

**What it is:** Native iOS app. Monitor and control from your iPhone.

**When to use:**
- You're away from your Mac
- You need remote health checks
- You want notifications

**Features:**
- Real-time Mac health (CPU, memory, disk)
- Ask Claude (remote questions)
- View logs and alerts
- Control Docker/services (with auth)

**Setup:** Requires server component running on your Mac. See iOS_APP_GUIDE.md

**Pros:**
- Access from anywhere
- Phone notifications
- Lightweight
- Watch-compatible

**Cons:**
- Requires setup (server + auth)
- Phone-sized interface
- Network-dependent

**Good for:** Remote monitoring, notifications, on-the-go access

---

### 5. Python Server + REST API (Advanced)

**What it is:** Backend API server. Programmatic access to KMac features.

**When to use:**
- You're building tools on top of KMac
- You need programmatic health checks
- You're integrating with other systems

**API endpoints:**
```
GET  /api/health         → System health (CPU, memory, disk)
POST /api/ask            → Ask Claude a question
GET  /api/docker         → Docker status
POST /api/vault/get      → Retrieve stored secrets
```

**Setup:** See SERVER_GUIDE.md (not covered in first 5 minutes)

**Pros:**
- Language-agnostic (use from any language)
- Enables custom integrations
- Can run on remote machine

**Cons:**
- Requires server setup
- Need API knowledge
- More complex

**Good for:** Integrations, custom tools, multi-machine setups

---

## Platform Comparison Matrix

| Feature | Bash CLI | Menu | MenuBar App | iOS App | Server API |
|---------|----------|------|------------|---------|-----------|
| **Speed** | ⚡⚡⚡ Fast | ⚡⚡ Medium | ⚡ Slow | ⚡ Varies | ⚡ Varies |
| **Visual** | ❌ Text | ✅ Menu | ✅✅ Full UI | ✅ Full | ✅ Web |
| **Scriptable** | ✅✅✅ | ❌ | ❌ | ❌ | ✅✅ |
| **One-click** | ❌ | ✅ | ✅✅ | ✅✅ | ❌ |
| **Learning curve** | Medium | Low | Low | Low | High |
| **macOS only?** | ❌ | ❌ | ✅ | ✅ | ❌ |
| **Offline?** | ✅ | ✅ | ✅ (mostly) | ❌ | ✅ |

---

## Recommended Workflows

### "I Just Installed — Where Do I Start?"
1. Run `kmac` once (see the menu)
2. Press `?` (health check)
3. Press `a` (ask Claude something)
4. Exit with `0`

See: **FIRST_5_MINUTES.md**

### "I'm a Terminal-First Developer"
- Use Bash CLI exclusively
- Alias: `alias kask='kmac ask'`
- Use in scripts: `kmac review --staged | mail ...`

Read: **README.md** (CLI section)

### "I Want Status Visible Without Opening Anything"
- Launch MenuBar app
- It stays in menu bar showing CPU/disk/services
- Click when you need action

Read: **KMac-MenuBar/SETUP_GUIDE.md**

### "I Need to Monitor My Mac Remotely"
- Set up server (see SERVER_GUIDE.md)
- Install iOS app
- Receive notifications when CPU/disk high

Read: **iOS_APP_GUIDE.md**

### "I'm Integrating KMac Into My Tool"
- Use Python Server API
- Query `/api/health`, `/api/docker`, etc.
- Build custom dashboards

Read: **SERVER_GUIDE.md**

---

## Common Misconceptions

**"Do I need to install all of these?"**
No. Start with Bash CLI. Add others only if you need them.

**"Bash CLI and MenuBar are separate programs?"**
They share the same underlying scripts and secrets. Bash CLI is faster; MenuBar is visual.

**"I need the server to use the CLI?"**
No. Server is optional and only needed for remote access or API integration.

**"Are they all kept in sync?"**
The MenuBar app and CLI share the same vault (secrets) and configs. Status checks are independent.

---

## Migration Path

```
Day 1: Start with Bash CLI
       kmac ask "..."
       Explore menu with: kmac

Day 3: Add MenuBar if you want visual status
       Install: Open Applications → KMac-MenuBar

Week 1: Try direct commands (no menu)
       kmac aicommit
       kmac review
       kmac docker health

Week 2: Set up iOS app if you need remote access
       See iOS_APP_GUIDE.md

Month 1: Only then consider server API (if you need it)
        See SERVER_GUIDE.md
```

---

## Questions?

- **How do I use X from CLI?** → See README.md
- **How do I set up the server?** → See SERVER_GUIDE.md
- **How do I install the iOS app?** → See iOS_APP_GUIDE.md
- **How do I troubleshoot?** → See README.md Troubleshooting

---

**Start here:** Run `kmac ask "hello"` right now. It takes 10 seconds. 🚀
