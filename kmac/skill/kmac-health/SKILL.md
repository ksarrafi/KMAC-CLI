---
name: kmac-health
description: Diagnose and fix macOS system-health issues (high disk usage, low memory, high CPU, Docker problems, general "my Mac is slow/full") using the kmac toolkit. Use whenever the user reports a Mac performance/storage/Docker problem or asks to check or clean up their system. Prefer kmac's deterministic playbooks over ad-hoc shell commands.
---

# kmac-health

`kmac-cli` is a local macOS system-health tool. It exposes a live system snapshot
and a set of **deterministic playbooks** — vetted, repeatable fixes for known
problems. Prefer it over inventing shell commands: a playbook does the exact same
safe thing every time, with no guesswork.

Binary: `kmac-cli` (on PATH at `~/.local/bin/kmac-cli`).

## 1. Always start by reading the live snapshot

```bash
kmac-cli status --json
```

Returns `{cpu, memory, disk, health, issues[], timestamp}` (percentages). Use the
actual numbers — don't assume. `health` is `healthy | warning | critical`.

## 2. For known problems, use a playbook (preferred path)

List them:

```bash
kmac-cli playbooks --json     # [{id,title,summary,destructive}]
```

Run one. `inspect` runs first (read-only, shows what/how much); destructive
playbooks require confirmation:

```bash
kmac-cli run <id> --json            # destructive => returns needs-confirmation + inspect
kmac-cli run <id> --json --yes      # apply (only after the USER agrees)
```

`<id>` matches loosely: `kmac-cli run docker` resolves to `docker-restart`.
Shortcuts: `kmac-cli clean` (disk-cleanup), `kmac-cli docker` (docker-restart).

### Current playbooks
- **disk-cleanup** (destructive): reclaims Xcode DerivedData, Homebrew cache, and
  Trash. Use for high disk usage. Always show the user the `inspect` output (sizes)
  before running with `--yes`.
- **docker-restart**: quits and relaunches Docker Desktop. Use when Docker is
  wedged or containers are unhealthy.

## 3. Workflow

1. Run `kmac-cli status --json`. Report the issue in plain terms.
2. If a playbook matches the issue, run its `inspect` (run without `--yes`), show
   the user what it would do / reclaim, get agreement, then run with `--yes`.
3. Re-check `kmac-cli status --json` to confirm improvement.
4. **Only if no playbook fits**, fall back to crafting macOS-specific commands
   yourself (this is the expensive path). Never run broad destructive commands
   (`rm -rf` of large/unknown paths, disk erase) — inspect with `du -sh` first.

## Rules
- macOS only — never suggest Linux tools (apt, yum, journalctl, systemctl).
- Deterministic playbooks first; LLM-crafted commands last.
- Confirm with the user before any destructive action; show the `inspect` first.
- A new repeatable fix should become a playbook in the kmac repo
  (`Sources/KMacCore/Playbook.swift`), not a one-off command.
