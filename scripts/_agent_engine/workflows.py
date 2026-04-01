"""Workflow engine — load and execute structured workflow templates (ClawFlows equivalent).

Workflows are JSON files that define multi-step task sequences. Each step can:
  - Run a tool call
  - Ask the agent (via the engine)
  - Conditionally branch based on output
  - Set/read variables

Workflow locations:
  1. Built-in: scripts/_agent_engine/workflows/
  2. User: ~/.cache/kmac/agent/workflows/
  3. Project: .kmac/workflows/
"""

import asyncio
import json
import logging
import os
import re
from pathlib import Path

from .config import AGENT_HOME

log = logging.getLogger("kmac-agent")

BUILTIN_DIR = Path(__file__).parent / "workflows"
USER_DIR = AGENT_HOME / "workflows"


def list_workflows(workspace: str = ".") -> list[dict]:
    """List all available workflows."""
    workflows = []
    seen = set()

    for source, directory in [
        ("builtin", BUILTIN_DIR),
        ("user", USER_DIR),
        ("project", Path(workspace) / ".kmac" / "workflows"),
    ]:
        if not directory.is_dir():
            continue
        for fp in sorted(directory.glob("*.json")):
            if fp.stem in seen:
                continue
            seen.add(fp.stem)
            try:
                data = json.loads(fp.read_text())
                workflows.append({
                    "id": fp.stem,
                    "name": data.get("name", fp.stem),
                    "description": data.get("description", ""),
                    "source": source,
                    "path": str(fp),
                    "steps": len(data.get("steps", [])),
                })
            except Exception:
                log.debug("Bad workflow: %s", fp, exc_info=True)

    return workflows


def load_workflow(workflow_id: str, workspace: str = ".") -> dict | None:
    for directory in [
        Path(workspace) / ".kmac" / "workflows",
        USER_DIR,
        BUILTIN_DIR,
    ]:
        fp = (directory / f"{workflow_id}.json").resolve()
        if not fp.is_relative_to(directory.resolve()):
            log.warning("Blocked workflow path traversal: %s", workflow_id)
            continue
        if fp.exists():
            return json.loads(fp.read_text())
    return None


async def execute_workflow(
    workflow_id: str,
    variables: dict | None = None,
    tool_runner=None,
    agent_runner=None,
    workspace: str = ".",
) -> dict:
    """Execute a workflow. Returns {status, results, variables, log}."""

    wf = load_workflow(workflow_id, workspace)
    if not wf:
        return {"status": "error", "error": f"Workflow not found: {workflow_id}"}

    ctx = {
        "variables": dict(variables or {}),
        "results": {},
        "log": [],
        "status": "running",
    }
    ctx["variables"].setdefault("workspace", workspace)

    steps = wf.get("steps", [])
    i = 0
    while i < len(steps):
        step = steps[i]
        step_id = step.get("id", f"step_{i}")
        step_type = step.get("type", "tool")

        ctx["log"].append(f"[{step_id}] starting ({step_type})")

        try:
            if step_type == "tool":
                result = await _run_tool_step(step, ctx, tool_runner)
            elif step_type == "agent":
                result = await _run_agent_step(step, ctx, agent_runner)
            elif step_type == "set":
                result = _run_set_step(step, ctx)
            elif step_type == "check":
                result, jump = _run_check_step(step, ctx, steps)
                if jump is not None:
                    ctx["log"].append(f"[{step_id}] branching to step {jump}")
                    i = jump
                    continue
            elif step_type == "log":
                msg = _interpolate(step.get("message", ""), ctx)
                ctx["log"].append(f"[{step_id}] {msg}")
                result = msg
            else:
                result = f"Unknown step type: {step_type}"

            ctx["results"][step_id] = str(result)
            ctx["log"].append(f"[{step_id}] done")

        except Exception as e:
            ctx["log"].append(f"[{step_id}] ERROR: {e}")
            ctx["results"][step_id] = f"error: {e}"
            if step.get("on_error") == "abort":
                ctx["status"] = "failed"
                ctx["log"].append(f"Workflow aborted at {step_id}")
                return ctx
            if step.get("on_error") == "skip":
                pass

        i += 1

    ctx["status"] = "completed"
    return ctx


def _interpolate(text: str, ctx: dict) -> str:
    """Replace {{var}} with context values."""
    def _repl(m):
        key = m.group(1).strip()
        if key in ctx["variables"]:
            return str(ctx["variables"][key])
        if key in ctx["results"]:
            return str(ctx["results"][key])
        return m.group(0)
    return re.sub(r'\{\{(\w+)\}\}', _repl, text)


async def _run_tool_step(step: dict, ctx: dict, tool_runner) -> str:
    tool_name = step.get("tool", "bash")
    raw_input = step.get("input", {})
    inp = {}
    for k, v in raw_input.items():
        inp[k] = _interpolate(str(v), ctx) if isinstance(v, str) else v

    if tool_runner:
        result, _ = await tool_runner(tool_name, inp)
        return result

    from . import tools
    result, _ = await tools.execute(tool_name, inp)
    return result


async def _run_agent_step(step: dict, ctx: dict, agent_runner) -> str:
    prompt = _interpolate(step.get("prompt", ""), ctx)
    if not agent_runner:
        return "No agent runner available"
    return await agent_runner(prompt)


def _run_set_step(step: dict, ctx: dict) -> str:
    for k, v in step.get("variables", {}).items():
        val = _interpolate(str(v), ctx) if isinstance(v, str) else v
        ctx["variables"][k] = val
    return f"Set {len(step.get('variables', {}))} variables"


def _run_check_step(step: dict, ctx: dict, steps: list) -> tuple[str, int | None]:
    """Evaluate a condition and optionally jump."""
    var = step.get("variable", "")
    value = str(ctx["variables"].get(var, ctx["results"].get(var, "")))
    op = step.get("operator", "contains")
    expected = _interpolate(step.get("value", ""), ctx)

    matched = False
    if op == "contains":
        matched = expected.lower() in value.lower()
    elif op == "equals":
        matched = value == expected
    elif op == "not_empty":
        matched = bool(value.strip())
    elif op == "empty":
        matched = not value.strip()
    elif op == "regex":
        matched = bool(re.search(expected, value))

    if matched:
        goto = step.get("then_goto")
    else:
        goto = step.get("else_goto")

    jump = None
    if goto:
        for idx, s in enumerate(steps):
            if s.get("id") == goto:
                jump = idx
                break

    result = f"check {var} {op} '{expected}': {matched}"
    return result, jump
