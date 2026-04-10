# Tron swarm-style reviews

**Swarm** here means **multiple review “lanes”** combined into one repeatable workflow. Tron **blueprints** run steps **in order** inside a **single Iso** (one container). For true parallelism, open several terminals or run multiple `kmac tron run` commands in the background.

## Bundled blueprints

| File | Purpose |
|------|---------|
| `scripts/_tron/blueprints/kmac-check.json` | Full gate: `bash -n`, ShellCheck (CI file set), `tests/run-tests.sh` |
| `scripts/_tron/blueprints/swarm-review.json` | Quick scan: TODO/FIXME grep, largest scripts, reminder for `kmac tron check` |
| `scripts/_tron/blueprints/example.json` | Minimal example |

## Commands

```bash
kmac tron check                           # Comprehensive check (uses kmac-check.json)
kmac tron swarm                           # Runs swarm-review.json in current repo
kmac tron blueprint path/to/custom.json   # Your own blueprint
```

## Iso image tools

The Iso image includes **ShellCheck**, **rsync**, **git**, **jq**, **ripgrep** (`rg`), and **grep** for fast scans inside Docker.

## Pilot server tests

Python smoke tests for the aiohttp app live in `server/test_smoke.py` (see `CONTRIBUTING.md`).
