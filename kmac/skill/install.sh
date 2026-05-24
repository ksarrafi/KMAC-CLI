#!/usr/bin/env bash
# Installs the kmac Claude Code skill by symlinking it into ~/.claude/skills,
# so the repo copy stays the single source of truth (edits propagate live).
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)/kmac-health"
DEST="$HOME/.claude/skills/kmac-health"

mkdir -p "$HOME/.claude/skills"
ln -sfn "$SRC" "$DEST"
echo "Linked $DEST -> $SRC"
echo "Restart Claude Code (or start a new session) to pick up the skill."
