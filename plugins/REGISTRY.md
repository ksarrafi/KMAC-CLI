# KMac Plugin Registry

## Built-in Plugins

| Plugin | Description | Hooks | Version |
|--------|-------------|-------|---------|
| [git-stats](git-stats.sh) | Git repository statistics and insights | post-commit, on-startup | 1.0.0 |
| [git-guardian](git-guardian.sh) | Scan staged files for leaked secrets | pre-commit | 1.0.0 |
| [cleanup](cleanup.sh) | System cleanup (caches, logs, temp files) | — | 1.0.0 |
| [wifi-password](wifi-password.sh) | Show saved WiFi passwords | — | 1.0.0 |
| [docker-notify](docker-notify.sh) | Alert on unhealthy/restarting containers | on-startup | 1.0.0 |
| [project-stats](project-stats.sh) | Code statistics and repo health metrics | on-startup | 1.0.0 |
| [tmux-session](tmux-session.sh) | Quick tmux session manager | — | 1.0.0 |

## Creating a Plugin

### Header Format

Every plugin needs these comment headers at the top. **Discovery** (`toolkit.sh`) reads `TOOLKIT_*` lines; optional `AUTHOR` / `VERSION` are for humans only.

```bash
#!/bin/bash
# TOOLKIT_NAME: My Plugin
# TOOLKIT_DESC: Short description of what it does
# TOOLKIT_KEY: 8
# AUTHOR: Your Name
# VERSION: 1.0.0
# TOOLKIT_HOOKS: pre-commit,on-startup  (optional, comma-separated)
```

`TOOLKIT_KEY` is optional: if omitted, the menu assigns a numeric shortcut. Keys must not collide with built-in menu letters.

### Available Hooks

| Hook | Trigger |
|------|---------|
| `pre-commit` | Before AI commit |
| `post-commit` | After AI commit |
| `pre-review` | Before code review |
| `post-review` | After code review |
| `on-error` | When a command fails |
| `on-startup` | When toolkit loads |
| `on-exit` | When toolkit exits |
| `pre-deploy` | Before deployment |
| `post-deploy` | After deployment |
| `session-start` | Agent session begins |
| `session-end` | Agent session ends |

### Plugin Structure

When a hook runs, the first argument is the hook name (e.g. `on-startup`). Handle it in your `case` statement alongside interactive subcommands.

```bash
#!/bin/bash
# TOOLKIT_NAME: Example
# TOOLKIT_DESC: Example plugin
# TOOLKIT_KEY: 8
# TOOLKIT_HOOKS: on-startup

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../scripts/_ui.sh"

my_function() {
    ui_title "My Plugin"
    echo "Hello from my plugin!"
}

case "${1:-}" in
    on-startup) my_function ;;
    run|"")     my_function ;;
    help)       echo "Usage: kmac my-plugin [run]" ;;
    *)          echo "Unknown command: $1"; exit 1 ;;
esac
```

### Installation

Drop your `.sh` file into `plugins/` and it's automatically discovered.
Plugins are accessible via `kmac <plugin-name>` (derived from filename without `.sh`).

### Best Practices

1. Always source `_ui.sh` for consistent terminal output
2. Source `_platform.sh` if you need OS detection
3. Use `case` for subcommand routing
4. Keep plugins focused — one purpose per plugin
5. Validate inputs and fail gracefully
6. Add a `help` subcommand
