# Standardizing kmac with Claude Code primitives

kmac is the **deterministic tool layer**; Claude Code is the driver. Here's how
each Claude Code primitive maps onto it. The skill (SKILL.md) is the core — it
teaches any session to use kmac. Hooks and loops are opt-in.

## Skill (done)
`SKILL.md` in this directory. Auto-loads when the user mentions a Mac
health/storage/Docker problem. No setup beyond having the skill installed under
`~/.claude/skills/kmac-health/`.

## Hooks (opt-in) — guaranteed automation the harness enforces

### A. Inject live system health at session start
Add to `~/.claude/settings.json` (or project `.claude/settings.json`):

```json
{
  "hooks": {
    "SessionStart": [
      {
        "hooks": [
          { "type": "command",
            "command": "kmac-cli status --json" }
        ]
      }
    ]
  }
}
```
Claude then begins each session already knowing your CPU/mem/disk and any
critical issues — no need to ask.

### B. Guard against destructive disk commands (safety)
A `PreToolUse` hook on `Bash` can inspect the command and block obviously
dangerous ones (e.g. `rm -rf` of broad paths) before they run. Use this if you
let agents run shell freely.

## Loops — proactive monitoring without a daemon

Run a recurring check from a session:

```
/loop 30m kmac-cli status --json
```
Each tick re-reads health; if `health` is `critical`, the agent can surface it
or (with your go-ahead) run the matching playbook. Good for "watch this while I
work."

## launchd daemon — true always-on (outside any session)
For unattended monitoring even with no Claude session open, the repo ships
`health-daemon.plist` / `health-monitor.sh`. Load it with `launchctl` to have the
OS run periodic checks and notify on thresholds.

## The division of labor
- **kmac playbooks** = execution. Deterministic, free, repeatable.
- **Claude Code (skill)** = judgment/routing. Picks the right playbook, handles
  novel problems, talks to you.
- **Hooks** = guarantees (always check at start, always guard destructive cmds).
- **Loops / daemon** = time (proactive, not just on-demand).

Don't reimplement the AI orchestration inside kmac — let Claude Code drive via
the skill.
