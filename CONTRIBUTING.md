# Contributing to KMac-CLI

Thanks for your interest in contributing!

## Getting Started

1. Fork the repo and clone your fork
2. Run `bash install.sh` to set up
3. Make your changes
4. Test by running `kmac` or the specific script you modified
5. Submit a pull request

## Adding a New Tool

Create an executable script in `scripts/`:

```bash
#!/bin/bash
# my-tool — one-line description
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/_ui.sh"

# Your code here
```

Then add a menu entry in `toolkit.sh` and a CLI subcommand in the case statement.

## Adding a Plugin

Drop a script in `plugins/` with the required headers:

```bash
#!/bin/bash
# TOOLKIT_NAME: My Plugin
# TOOLKIT_DESC: What it does
# TOOLKIT_KEY: 3

echo "Hello!"
```

Plugins appear automatically in the menu.

## Code Style

- Bash 3.2 compatible (macOS default) — no associative arrays, no `declare -A`
- Use `_ui.sh` for colors and formatting (don't hardcode ANSI codes)
- Use `_auth-helper.sh` for Claude API calls
- Prefer `local` variables in functions
- Use `echo -e` with color variables from `_ui.sh`

## What Not to Commit

- `env.sh` (contains API keys)
- `deploy.sh` (local deployment script)
- Xcode user data (`xcuserdata/`)
- `.venv/`, `node_modules/`, `__pycache__/`

## Reporting Issues

Open a GitHub issue with:
- macOS version
- Bash version (`bash --version`)
- Steps to reproduce
- Expected vs actual behavior

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
