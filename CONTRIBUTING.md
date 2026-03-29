# Contributing to KMac-CLI

Thanks for your interest in contributing! KMac-CLI is an open-source macOS toolkit and we welcome pull requests.

## Branching Strategy

```
main ─────●────────●────────●──── (stable releases, tagged)
           \      /          \
            \    /            \
  feature/x  ──●    feature/y  ──● (your work)
```

- **`main`** is the stable branch. Every commit on `main` should be release-quality.
- **Feature branches** are where all work happens. Branch off `main`, PR back to `main`.
- **Tags** mark releases: `v2.4.0`, `v2.5.0`, etc. Created by maintainers only.

## How to Contribute

### 1. Fork & Clone

```bash
gh repo fork ksarrafi/KMAC-CLI --clone
cd KMAC-CLI
```

### 2. Create a Feature Branch

```bash
git checkout -b feature/my-cool-feature
```

Name your branch descriptively:
- `feature/wifi-analyzer` — new feature
- `fix/docker-health-crash` — bug fix
- `docs/update-readme` — documentation
- `refactor/vault-cleanup` — code improvement

### 3. Make Your Changes

Follow these conventions:

**Bash (scripts)**
- Must work with **Bash 3.2** (macOS default). No associative arrays, no namerefs, no `mapfile`.
- Source `_platform.sh` for cross-platform operations.
- Source `_hooks.sh` if the script needs to emit lifecycle hooks.
- Source `_ui.sh` for colors, `title_box`, `pause`, `spinner`, and other helpers.
- Source `_vault.sh` for credential access — never hardcode `security` commands.
- For Keychain access, use `platform_keychain_*` helpers instead of calling `security` directly.
- Use `ui_success`, `ui_warn`, `ui_fail` for one-line feedback.
- Use `spinner "label" command args` for operations that take time.
- Menu options: green letter keys, `m` for back, consistent indentation.
- No `set -e` in interactive scripts (each tool handles its own errors).

**Python (server)**
- Python 3.9+ for the API server.
- Use `aiohttp` for async routes.
- JSON responses for all API endpoints.

**TypeScript (assistant, orchestrator)**
- TypeScript strict mode for `assistant/` and `orchestrator/` services.
- Run with `tsx` (no build step needed for development).
- Express.js for HTTP/REST, native `ws` for WebSocket.
- Config stored in `~/.config/kmac/<service>/`.
- PID files in `~/.config/kmac/<service>/` for process management.
- Each service has a bash wrapper in `scripts/` (e.g., `scripts/assistant`, `scripts/orchestrator`).

**General**
- No secrets, credentials, or machine-specific paths in committed code.
- Test on macOS before submitting (this is a macOS-first toolkit).
- Run `bash -n <script>` to syntax-check before committing.

### 4. Test

```bash
# Run the full test suite (60 smoke tests)
bash tests/run-tests.sh

# Syntax-check all scripts
for f in scripts/* toolkit.sh; do bash -n "$f" 2>/dev/null || echo "FAIL: $f"; done

# Run the toolkit
bash toolkit.sh

# Test a specific script
bash scripts/docker-health --json
bash scripts/secrets list
bash scripts/software list
```

GitHub Actions CI runs automatically on push and pull requests to `main`, with jobs on macOS and Ubuntu plus ShellCheck.

### 5. Commit

Write clear commit messages:

```
Add WiFi signal strength analyzer

New plugin that shows real-time WiFi signal quality,
channel utilization, and suggests optimal channels.
Displays as an ASCII bar chart in the terminal.
```

### 6. Push & Open a PR

```bash
git push -u origin feature/my-cool-feature
gh pr create --title "Add WiFi analyzer plugin" --body "..."
```

Target your PR at `main`. Include:
- What you changed and why
- How to test it
- Screenshots if it's UI-related

## Adding a Plugin

The easiest way to contribute is by adding a plugin. Create a file in `plugins/`:

```bash
#!/bin/bash
# TOOLKIT_NAME: My Plugin
# TOOLKIT_DESC: What it does in one line
# TOOLKIT_KEY: 9

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../scripts" && pwd)"
source "$SCRIPT_DIR/_ui.sh"

title_box "My Plugin" "🔧"
# Your code here
```

Plugins can also declare lifecycle hooks (comma-separated):

```bash
# TOOLKIT_HOOKS: post-commit,on-startup
```

Available hooks: `pre-commit`, `post-commit`, `pre-review`, `post-review`, `on-error`, `on-startup`, `on-exit`, `pre-deploy`, `post-deploy`, `session-start`, `session-end`.

Plugins are auto-discovered by the menu. The `TOOLKIT_KEY` is the shortcut key (pick an unused one).

## Version Bumping (Maintainers)

Releases are managed with git tags and GitHub Releases:

```bash
scripts/release 2.5.1   # Bumps VERSION, updates Homebrew formula, creates git tag v2.5.1
git push origin main && git push origin v2.5.1
```

The toolkit reads its version from `git describe --tags` at runtime, falling back to the `VERSION` file for non-git installs (like ZIP downloads).

## Code of Conduct

Be respectful. Write clear code. Help each other out.

## Questions?

Open an issue or start a discussion on GitHub.
