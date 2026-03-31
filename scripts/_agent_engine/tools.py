"""Tool definitions and async execution for the Claude tool_use protocol."""

import asyncio
import logging
import os

from .config import DANGEROUS_PATTERNS, DANGEROUS_PREFIXES

log = logging.getLogger("kmac-agent")

TOOLS = [
    {
        "name": "bash",
        "description": (
            "Execute a shell command and return stdout+stderr. Use for "
            "running programs, git, system commands, package management, "
            "or any terminal task."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "command": {"type": "string", "description": "Shell command"}
            },
            "required": ["command"],
        },
    },
    {
        "name": "read_file",
        "description": "Read a file's contents with line numbers.",
        "input_schema": {
            "type": "object",
            "properties": {
                "path": {"type": "string", "description": "File path"},
                "offset": {
                    "type": "integer",
                    "description": "Start line (1-indexed)",
                },
                "limit": {
                    "type": "integer",
                    "description": "Max lines to return",
                },
            },
            "required": ["path"],
        },
    },
    {
        "name": "write_file",
        "description": "Create or overwrite a file.",
        "input_schema": {
            "type": "object",
            "properties": {
                "path": {"type": "string", "description": "File path"},
                "content": {"type": "string", "description": "Full content"},
            },
            "required": ["path", "content"],
        },
    },
    {
        "name": "edit_file",
        "description": (
            "Find and replace an exact string in a file. old_string must "
            "be unique. Always read_file first to see current content."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "path": {"type": "string", "description": "File to edit"},
                "old_string": {"type": "string", "description": "Exact text to find"},
                "new_string": {"type": "string", "description": "Replacement text"},
            },
            "required": ["path", "old_string", "new_string"],
        },
    },
    {
        "name": "list_dir",
        "description": "List files and directories at a path.",
        "input_schema": {
            "type": "object",
            "properties": {
                "path": {
                    "type": "string",
                    "description": "Directory (default: cwd)",
                },
                "depth": {
                    "type": "integer",
                    "description": "Max depth (default: 2)",
                },
            },
        },
    },
    {
        "name": "grep_search",
        "description": (
            "Search for a regex pattern across files. Returns matching "
            "lines with paths and line numbers. Uses ripgrep if available."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "pattern": {"type": "string", "description": "Regex pattern"},
                "path": {
                    "type": "string",
                    "description": "Search directory (default: cwd)",
                },
                "include": {
                    "type": "string",
                    "description": "File glob, e.g. '*.py'",
                },
            },
            "required": ["pattern"],
        },
    },
]


def _trunc(text: str, limit: int = 80000) -> str:
    if len(text) <= limit:
        return text
    half = limit // 2
    cut = len(text) - limit
    return text[:half] + f"\n\n... ({cut} chars truncated) ...\n\n" + text[-half:]


async def execute(name: str, inp: dict, timeout: int = 120):
    """Execute a tool. Returns (result_text, display_preview)."""
    try:
        if name == "bash":
            return await _bash(inp, timeout)
        if name == "read_file":
            return _read_file(inp)
        if name == "write_file":
            return _write_file(inp)
        if name == "edit_file":
            return _edit_file(inp)
        if name == "list_dir":
            return await _list_dir(inp)
        if name == "grep_search":
            return await _grep(inp)
        return f"Unknown tool: {name}", f"Unknown tool: {name}"
    except Exception as e:
        msg = f"Error ({name}): {e}"
        return msg, msg


def _check_dangerous(cmd: str) -> str | None:
    """Return a warning message if the command looks dangerous, else None."""
    lower = cmd.lower().strip()
    for pat in DANGEROUS_PATTERNS:
        if pat.lower() in lower:
            return f"BLOCKED: dangerous command detected ({pat})"
    for prefix in DANGEROUS_PREFIXES:
        if lower.startswith(prefix.lower()):
            return f"BLOCKED: dangerous command prefix ({prefix})"
    return None


async def _bash(inp, timeout):
    cmd = inp["command"]
    warning = _check_dangerous(cmd)
    if warning:
        log.warning("Blocked dangerous command: %s", cmd[:100])
        return warning, warning
    try:
        proc = await asyncio.create_subprocess_shell(
            cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdout, stderr = await asyncio.wait_for(
            proc.communicate(), timeout=timeout
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
        return _trunc(full), preview
    except asyncio.TimeoutError:
        return "Error: command timed out", "Error: timed out"


def _read_file(inp):
    path = inp["path"]
    with open(path, "r") as f:
        all_lines = f.readlines()
    offset = max(0, inp.get("offset", 1) - 1)
    limit = inp.get("limit", len(all_lines))
    sel = all_lines[offset : offset + limit]
    numbered = "".join(
        f"{offset + i + 1:>6}|{ln}" for i, ln in enumerate(sel)
    )
    return _trunc(numbered), f"{len(sel)} of {len(all_lines)} lines"


def _write_file(inp):
    path, content = inp["path"], inp["content"]
    parent = os.path.dirname(path)
    if parent:
        os.makedirs(parent, exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        f.write(content)
    os.replace(tmp, path)
    lc = content.count("\n") + (
        1 if content and not content.endswith("\n") else 0
    )
    msg = f"Wrote {lc} lines to {path}"
    return msg, msg


def _edit_file(inp):
    path, old, new = inp["path"], inp["old_string"], inp["new_string"]
    with open(path, "r") as f:
        content = f.read()
    n = content.count(old)
    if n == 0:
        return (
            f"Error: old_string not found in {path}",
            "old_string not found",
        )
    if n > 1:
        return (
            f"Error: old_string found {n} times — must be unique",
            f"found {n} times",
        )
    content = content.replace(old, new, 1)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        f.write(content)
    os.replace(tmp, path)
    return f"Edited {path}", f"edited {path}"


async def _list_dir(inp):
    path = inp.get("path", ".")
    depth = inp.get("depth", 2)
    cmd = (
        f"find '{path}' -maxdepth {depth} -not -path '*/.*' "
        "2>/dev/null | sort | head -100"
    )
    proc = await asyncio.create_subprocess_shell(
        cmd,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    stdout, _ = await asyncio.wait_for(proc.communicate(), timeout=10)
    out = stdout.decode().strip()
    return out or "(empty)", out[:500] if out else "(empty)"


async def _grep(inp):
    pattern, path = inp["pattern"], inp.get("path", ".")
    include = inp.get("include", "")
    rg_check = await asyncio.create_subprocess_shell(
        "command -v rg",
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    await rg_check.communicate()
    if rg_check.returncode == 0:
        cmd = f"rg -n --max-count 50 --no-heading"
        if include:
            cmd += f" -g '{include}'"
        cmd += f" '{pattern}' '{path}'"
    else:
        cmd = f"grep -rn"
        if include:
            cmd += f" --include='{include}'"
        cmd += f" '{pattern}' '{path}' | head -50"
    proc = await asyncio.create_subprocess_shell(
        cmd,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    stdout, _ = await asyncio.wait_for(proc.communicate(), timeout=30)
    out = stdout.decode().strip()
    lines = out.split("\n") if out else []
    preview = "\n".join(lines[:20])
    if len(lines) > 20:
        preview += f"\n... ({len(lines) - 20} more)"
    return _trunc(out) if out else "No matches found.", preview or "No matches."
