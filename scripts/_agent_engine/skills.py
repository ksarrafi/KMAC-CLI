"""Skills system — SKILL.md files injected into the system prompt.

Skills are markdown files that teach the agent when and how to use tools.
They live in:
  1. The current workspace: .kmac/skills/  or .skills/
  2. Shared directory: ~/.cache/kmac/agent/skills/
  3. Agent-specific: ~/.cache/kmac/agent/agents/<name>/skills/

Each SKILL.md file is injected as a system prompt section.
"""

import logging
import os
from pathlib import Path

from .config import AGENT_HOME, DB_DIR

log = logging.getLogger("kmac-agent")


def find_skill_files(agent_name: str = "default", workspace: str = ".") -> list[Path]:
    """Find all SKILL.md files for a given agent, in priority order."""
    paths = []

    workspace_dirs = [
        Path(workspace) / ".kmac" / "skills",
        Path(workspace) / ".skills",
        Path(workspace) / ".cursor" / "skills",
    ]
    for d in workspace_dirs:
        if d.is_dir():
            paths.extend(sorted(d.rglob("SKILL.md")))
            paths.extend(sorted(d.rglob("*.skill.md")))

    shared_dir = AGENT_HOME / "skills"
    if shared_dir.is_dir():
        paths.extend(sorted(shared_dir.rglob("SKILL.md")))
        paths.extend(sorted(shared_dir.rglob("*.skill.md")))

    agent_skills = DB_DIR / agent_name / "skills"
    if agent_skills.is_dir():
        paths.extend(sorted(agent_skills.rglob("SKILL.md")))
        paths.extend(sorted(agent_skills.rglob("*.skill.md")))

    seen = set()
    unique = []
    for p in paths:
        key = str(p.resolve())
        if key not in seen:
            seen.add(key)
            unique.append(p)
    return unique


def load_skills(agent_name: str = "default", workspace: str = ".") -> list[dict]:
    """Load all skills, returning list of {name, path, content}."""
    skills = []
    for path in find_skill_files(agent_name, workspace):
        try:
            content = path.read_text(encoding="utf-8", errors="replace")
            if not content.strip():
                continue
            name = path.parent.name if path.name == "SKILL.md" else path.stem.replace(".skill", "")
            skills.append({
                "name": name,
                "path": str(path),
                "content": content.strip(),
            })
        except Exception:
            log.debug("Failed to load skill: %s", path, exc_info=True)
    return skills


def build_skills_prompt(agent_name: str = "default", workspace: str = ".") -> str:
    """Build the skills section for the system prompt."""
    skills = load_skills(agent_name, workspace)
    if not skills:
        return ""

    parts = [f"\n--- Skills ({len(skills)} loaded) ---"]
    for skill in skills:
        parts.append(f"\n### Skill: {skill['name']}\n{skill['content']}")
    return "\n".join(parts)


def list_skills_info(agent_name: str = "default", workspace: str = ".") -> list[dict]:
    """List skills with metadata (for display, not for prompt)."""
    skills = load_skills(agent_name, workspace)
    info = []
    for s in skills:
        lines = s["content"].split("\n")
        desc = ""
        for line in lines:
            line = line.strip()
            if line and not line.startswith("#"):
                desc = line[:100]
                break
        info.append({
            "name": s["name"],
            "path": s["path"],
            "lines": len(s["content"].split("\n")),
            "description": desc,
        })
    return info
