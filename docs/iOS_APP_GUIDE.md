# KMac Pilot iOS App Guide

Control your Mac's AI coding agents from anywhere with the native KMac Pilot iOS app.

---

## Features

### 🎛️ **Dashboard**
- Real-time system stats (hostname, uptime, load average)
- Active agent session indicator
- Quick access to all features

### 🚀 **Task Management**
- Browse all discovered projects on your Mac
- Start Claude Code or Cursor Agent tasks remotely
- Live terminal output with auto-scroll
- Task progress monitoring with elapsed time

### 📁 **File Browser**
- Navigate project file trees
- Syntax-highlighted code viewer
- Quick file access for context

### 🔀 **Git Operations**
- View git status and diff stats
- Review changes before committing
- Commit or revert agent changes
- Git log viewer

### 🐳 **Docker Management**
- View running containers
- Start/stop containers
- Container logs viewer
- Health status indicators

### 💻 **Shell Execution**
- Run commands on your remote Mac
- Real-time command output
- Command history
- Safe command allowlist

### ⚙️ **Settings**
- Persistent server connection
- Auto-reconnect on app launch
- Secure credential storage in iOS Keychain
- Connection test with health check

---

## Installation

### Prerequisites

**On Your Mac:**
1. KMac-CLI installed and configured
2. API server running:
   ```bash
   kmac pilot server start
   ```
3. Server accessible (local network or remote tunnel)

**Development Tools:**
- Xcode 15.0+
- XcodeGen (install via Homebrew)
- iOS 17.0+ simulator or device

### Build from Source

```bash
# 1. Install XcodeGen
brew install xcodegen

# 2. Navigate to iOS app directory
cd ~/Projects/KMac-CLI/ios/KMacPilot

# 3. Generate Xcode project
xcodegen generate

# 4. Open in Xcode
open KMacPilot.xcodeproj

# 5. Select target device/simulator and run (Cmd+R)
```

### Project Structure

```
ios/KMacPilot/
├── project.yml                 # XcodeGen spec
├── KMacPilot.xcodeproj/        # Generated Xcode project
└── KMacPilot/
    ├── KMacPilotApp.swift      # App entry point
    ├── Models/
    │   └── Models.swift        # Data structures
    ├── Services/
    │   ├── AppState.swift      # Global app state
    │   ├── APIClient.swift     # REST API client
    │   └── WebSocketClient.swift  # Real-time updates
    └── Views/
        ├── ConnectView.swift       # Server connection
        ├── DashboardView.swift     # Home screen
        ├── MainTabView.swift       # Tab navigation
        ├── SessionsView.swift      # Agent sessions list
        ├── SessionDetailView.swift # Session output
        ├── ProjectsView.swift      # Project browser
        ├── ProjectDetailView.swift # Project actions
        ├── TaskStartSheet.swift    # Task creation
        ├── TerminalView.swift      # Terminal output
        ├── FileBrowserView.swift   # File navigation
        ├── SettingsView.swift      # App settings
        └── ToolkitView.swift       # Feature menu
```

---

## Setup & Configuration

### 1. Start the API Server

On your Mac:

```bash
# Quick start (foreground)
kmac pilot server start

# Or install as auto-start service
kmac pilot server install

# Get server URL and token
kmac pilot server status
```

Output:
```
🟢 KMac Pilot Server running
   PID: 12345
   Port: 7890
   URL: http://192.168.1.100:7890
   Token: Nzk4NjE2MzQ1MjE4NzY5Mzk4...
```

### 2. Configure Remote Access (Optional)

For access outside your local network:

```bash
# Setup remote tunnel (choose one)
kmac remote-access setup        # Tailscale, Cloudflare, or ngrok

# Start tunnel
kmac remote-access start

# Get connection info with QR code
kmac remote-access qr           # Scan with iOS camera
```

### 3. Connect iOS App

**First Launch:**
1. Open KMac Pilot app
2. Enter server URL: `http://192.168.1.100:7890`
3. Paste token from `kmac pilot server status`
4. Tap **Connect**

**Connection Types:**
- **Local Network:** `http://192.168.1.x:7890` (fastest)
- **Tailscale:** `http://100.x.x.x:7890` (secure mesh VPN)
- **Cloudflare:** `https://your-domain.com` (custom domain)
- **ngrok:** `https://abc123.ngrok.io` (temporary testing)

**Quick Connect via QR:**
1. Run: `kmac remote-access qr`
2. Scan QR with iOS camera
3. Opens app with pre-filled credentials

---

## Usage Guide

### Starting a Task

1. **Tap Projects tab** → browse your Mac's project directories
2. **Select a project** → tap to open project detail view
3. **Tap "Start Task"** button
4. **Fill in task sheet:**
   - Agent: Claude Code or Cursor Agent
   - Task: "Add dark mode toggle to settings"
5. **Tap Start** → agent begins working
6. **View live output** in terminal view with auto-scroll

### Monitoring Progress

**Sessions Tab:**
- View all active agent sessions
- Tap session to see live terminal output
- Output updates in real-time via WebSocket
- Elapsed time counter
- Agent type badge (Claude/Cursor)

**Terminal View:**
- Auto-scroll to bottom
- Manual scroll lock (tap to disable auto-scroll)
- Clear text rendering (ANSI codes stripped)
- Copy output with long-press

### Reviewing Changes

**Git Tab:**
1. View git status (modified, added, deleted files)
2. Tap "View Diff" → see all changes with stats
3. Review changes made by the agent
4. Choose:
   - **Commit** → save changes with message
   - **Revert** → discard all changes
   - **Back** → continue working

### Managing Docker

**Docker Tab:**
- View all containers (running/stopped)
- Color-coded status indicators:
  - 🟢 Green: Running
  - 🔴 Red: Stopped
  - 🟡 Yellow: Restarting
- Tap container → Start/Stop actions
- Pull to refresh

### Shell Commands

**Shell Tab:**
1. Enter command in text field
2. Tap **Run** or press return
3. View output in scrollable text view
4. History: previous commands saved
5. **Allowlist enforcement:**
   - Safe: `ls`, `git status`, `docker ps`
   - Blocked: `rm -rf`, `sudo`, fork bombs

---

## Troubleshooting

### Connection Issues

**"Failed to connect to server"**
- ✅ Verify server is running: `kmac pilot server status`
- ✅ Check network: can you ping the IP?
- ✅ Firewall: allow port 7890
- ✅ URL format: `http://` or `https://` prefix required

**"Unauthorized"**
- ✅ Token expired: regenerate with `kmac pilot server token`
- ✅ Token mismatch: copy exact token (no spaces)
- ✅ Server restarted: new token generated automatically

**"Connection lost"**
- ✅ Auto-reconnect: app attempts every 5 seconds
- ✅ Manual: pull down on any tab to force reconnect
- ✅ Check server logs: `kmac pilot server logs`

### WebSocket Issues

**"Terminal output not updating"**
- ✅ WebSocket connection: check Settings → Connection Status
- ✅ Restart session: stop and start agent task
- ✅ Server logs: `docker logs kmac-pilot` if using Docker

### Performance

**"App is slow"**
- ✅ Reduce output: large terminal buffers slow rendering
- ✅ Restart session: clears output buffer
- ✅ Network: use local network instead of tunnel when possible

**"High memory usage"**
- ✅ Sessions accumulate output: stop old sessions
- ✅ Clear app cache: delete and reinstall (data in Keychain persists)

---

## Security

### Authentication

**Bearer Token:**
- 256-bit random token generated on server start
- Stored securely in iOS Keychain
- Transmitted via Authorization header
- WebSocket auth via first message (not URL)

**Token Security:**
- Never logged or displayed in plain text
- Masked in UI (shows first 8 chars only)
- Expires on server restart (new token generated)
- No password required (token-based auth only)

### Network Security

**Local Network:**
- Traffic unencrypted (HTTP)
- Safe on trusted networks only
- Server binds to `0.0.0.0:7890` (all interfaces)

**Remote Access:**
- **Tailscale:** Encrypted mesh VPN (recommended)
- **Cloudflare:** TLS termination via Caddy
- **ngrok:** TLS tunnel (temporary testing)

**Best Practice:**
- Use Tailscale for persistent remote access
- Use Cloudflare with custom domain for teams
- Use local network when at home/office

### Command Execution

**Allowlist Security:**
- Server enforces command allowlist
- Blocks: `rm -rf`, `sudo`, `dd`, `fork bombs`
- Blocks: `curl | sh`, `wget | bash`
- Blocks: `--exec`, `--upload-pack` flags
- Safe: `ls`, `git`, `docker`, `cat`, `grep`

**User Responsibility:**
- Review commands before running
- Don't execute untrusted scripts
- Use read-only operations when possible

---

## Development

### Building & Testing

**Debug Build:**
```bash
# In Xcode
# Scheme: KMacPilot (Debug)
# Device: iPhone 15 Simulator
# Run: Cmd+R
```

**Release Build:**
```bash
# 1. Update version in project.yml
# 2. Regenerate project
xcodegen generate

# 3. Archive in Xcode
# Product → Archive
# Distribute App → Ad Hoc / App Store
```

### Code Signing

**For Simulator:** No code signing required

**For Device:**
1. Apple Developer account required
2. Set DEVELOPMENT_TEAM in `project.yml`:
   ```yaml
   DEVELOPMENT_TEAM: "YOUR_TEAM_ID"
   CODE_SIGN_IDENTITY: "Apple Development"
   CODE_SIGNING_REQUIRED: YES
   ```
3. Regenerate: `xcodegen generate`
4. Xcode will handle provisioning profiles

### Architecture

**SwiftUI + MVVM:**
- Views: Pure SwiftUI, no business logic
- AppState: Global state with `@Published` properties
- Services: API/WebSocket clients, network layer
- Models: Codable structs for API responses

**Concurrency:**
- `@MainActor` isolation for all UI updates
- `Task {}` blocks for async operations
- WebSocket callbacks dispatch to main queue

**State Management:**
- Single AppState instance (EnvironmentObject)
- All views observe AppState changes
- No local state in views (presentational only)

### Key Technologies

- **SwiftUI:** Declarative UI framework
- **Combine:** Reactive programming (minimal usage)
- **URLSession:** REST API client
- **NWWebSocket:** Native WebSocket (iOS 13+)
- **Security:** iOS Keychain for credential storage

---

## FAQ

**Q: Can I use this on iPad?**  
A: Currently iPhone-only. iPad support requires layout adjustments but is technically feasible.

**Q: Does it work over cellular?**  
A: Yes, if using Tailscale, Cloudflare, or ngrok. Local network requires WiFi.

**Q: Can I control multiple Macs?**  
A: Yes, configure different server URLs in Settings. Switch by reconnecting.

**Q: Is the API server secure?**  
A: Token-based auth provides reasonable security. Use TLS tunnels (Tailscale/Cloudflare) for production.

**Q: Can I contribute to the iOS app?**  
A: Yes! See [CONTRIBUTING.md](../CONTRIBUTING.md) for guidelines. PRs welcome.

**Q: Battery impact?**  
A: Minimal when idle. WebSocket connection uses ~1-2% battery per hour.

**Q: Offline mode?**  
A: No offline mode currently. Requires server connection.

---

## Roadmap

### Planned Features
- 🔜 Push notifications for task completion
- 🔜 Biometric authentication (Face ID / Touch ID)
- 🔜 iPad layout with multi-column views
- 🔜 Dark mode support (system theme)
- 🔜 Offline mode with sync
- 🔜 Multiple server profiles (quick switch)
- 🔜 Shortcuts app integration
- 🔜 Widget for session status

### Contributions Welcome
- File browser improvements (syntax themes, search)
- Terminal enhancements (color support, copy selection)
- Git operations (branch switching, pull/push)
- Docker advanced features (exec, networks, volumes)

---

## Support

**Issues:** [GitHub Issues](https://github.com/ksarrafi/KMAC-CLI/issues)  
**Documentation:** [Main README](../README.md)  
**Server Setup:** [QUICKSTART](../QUICKSTART.md)

---

**Last Updated:** April 12, 2026  
**App Version:** 1.0.0  
**Requires:** iOS 17.0+, KMac-CLI v3.0.0+
