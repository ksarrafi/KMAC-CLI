"""Plugin system — load user-defined tools from the plugins directory.

Each plugin is a directory containing:
  - tool.json  — Claude tool schema (name, description, input_schema)
  - run.sh     — Executable that receives JSON input on stdin, outputs result on stdout

Example plugin structure:
  ~/.cache/kmac/agent/plugins/kubectl/
    tool.json
    run.sh
"""

import asyncio
import json
import logging
import os
from pathlib import Path

from .config import AGENT_HOME

log = logging.getLogger("kmac-agent")

PLUGIN_DIR = AGENT_HOME / "plugins"


def _load_plugin(plugin_path: Path) -> dict | None:
    """Load a single plugin from its directory."""
    schema_file = plugin_path / "tool.json"
    runner = None
    for name in ("run.sh", "run.py", "run"):
        candidate = plugin_path / name
        if candidate.exists():
            runner = candidate
            break

    if not schema_file.exists() or not runner:
        return None

    try:
        with open(schema_file) as f:
            schema = json.load(f)
        if "name" not in schema or "input_schema" not in schema:
            log.warning("Plugin %s: missing name or input_schema", plugin_path.name)
            return None
        schema["_runner"] = str(runner)
        schema["_plugin"] = True
        return schema
    except Exception:
        log.warning("Plugin %s: failed to load", plugin_path.name, exc_info=True)
        return None


def load_all() -> list[dict]:
    """Load all plugins from the plugins directory."""
    plugins = []
    if not PLUGIN_DIR.exists():
        return plugins
    for d in sorted(PLUGIN_DIR.iterdir()):
        if d.is_dir():
            p = _load_plugin(d)
            if p:
                plugins.append(p)
                log.info("Loaded plugin: %s", p["name"])
    return plugins


def get_tool_schemas(plugins: list[dict]) -> list[dict]:
    """Return clean tool schemas (without internal metadata) for the API."""
    schemas = []
    for p in plugins:
        schema = {k: v for k, v in p.items() if not k.startswith("_")}
        schemas.append(schema)
    return schemas


async def execute_plugin(plugin: dict, inp: dict, timeout: int = 120) -> tuple[str, str]:
    """Execute a plugin's runner script with JSON input."""
    runner = plugin.get("_runner", "")
    if not runner or not os.path.exists(runner):
        return "Plugin runner not found", "runner not found"

    input_json = json.dumps(inp)
    try:
        proc = await asyncio.create_subprocess_exec(
            "bash", runner,
            stdin=asyncio.subprocess.PIPE,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdout, stderr = await asyncio.wait_for(
            proc.communicate(input=input_json.encode()),
            timeout=timeout,
        )
        out = (stdout or b"").decode("utf-8", errors="replace")
        err = (stderr or b"").decode("utf-8", errors="replace")
        full = out + err
        if not full.strip():
            full = f"(exit code {proc.returncode})"
        lines = full.rstrip("\n").split("\n")
        preview = "\n".join(lines[:20])
        if len(lines) > 20:
            preview += f"\n... ({len(lines) - 20} more lines)"
        return full[:80000], preview
    except asyncio.TimeoutError:
        return "Plugin timed out", "timed out"
    except Exception as e:
        msg = f"Plugin error: {e}"
        return msg, msg
