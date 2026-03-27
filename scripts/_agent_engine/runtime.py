"""Agent runtime — conversation loop with Claude API and tool dispatch."""

import json
import logging
import os
import platform
import subprocess
import urllib.request
import urllib.error

from . import tools
from .config import (
    DEFAULT_SYSTEM_PROMPT, MAX_TOKENS, MAX_TOOL_ROUNDS, API_TIMEOUT,
    MODEL_SHORTCUTS,
)

log = logging.getLogger("kmac-agent")


def get_api_key() -> str:
    """Resolve API key from env, vault, or Keychain."""
    key = os.environ.get("ANTHROPIC_API_KEY", "")
    if key and "your-" not in key and "placeholder" not in key.lower():
        return key
    for svc in ("toolkit-anthropic", "kmac-anthropic"):
        try:
            r = subprocess.run(
                ["security", "find-generic-password", "-s", svc, "-w"],
                capture_output=True, text=True, timeout=5,
            )
            if r.returncode == 0 and r.stdout.strip():
                return r.stdout.strip()
        except Exception:
            continue
    return ""


def build_system_prompt(agent_config: dict, memories=None) -> str:
    """Assemble full system prompt from agent config + env + memories."""
    parts = []
    custom = (agent_config.get("system_prompt") or "").strip()
    parts.append(custom if custom else DEFAULT_SYSTEM_PROMPT)

    try:
        os_ver = (
            f"macOS {platform.mac_ver()[0]}"
            if platform.system() == "Darwin"
            else platform.platform()
        )
    except Exception:
        os_ver = "unknown"

    cwd = os.getcwd()
    git_info = ""
    try:
        br = subprocess.run(
            ["git", "branch", "--show-current"],
            capture_output=True, text=True, timeout=3, cwd=cwd,
        )
        if br.returncode == 0 and br.stdout.strip():
            tl = subprocess.run(
                ["git", "rev-parse", "--show-toplevel"],
                capture_output=True, text=True, timeout=3, cwd=cwd,
            )
            repo = os.path.basename(tl.stdout.strip()) if tl.returncode == 0 else "?"
            git_info = f"\n- Git: {repo} ({br.stdout.strip()})"
    except Exception:
        pass

    parts.append(
        f"\nEnvironment:\n- OS: {os_ver}\n- Shell: "
        f"{os.environ.get('SHELL', 'unknown')}\n- CWD: {cwd}{git_info}"
    )

    ctx = (agent_config.get("context") or "").strip()
    if ctx:
        parts.append(f"\nAgent context:\n{ctx}")

    if memories:
        mem = "\n".join(f"- {m['content']}" for m in memories[:10])
        parts.append(f"\nRelevant knowledge:\n{mem}")

    return "\n".join(parts)


def _call_claude_sync(messages, system, model, api_key):
    """Blocking Claude API call (meant to be run in an executor)."""
    body = json.dumps({
        "model": model,
        "max_tokens": MAX_TOKENS,
        "system": system,
        "tools": tools.TOOLS,
        "messages": messages,
    }).encode()
    req = urllib.request.Request(
        "https://api.anthropic.com/v1/messages",
        data=body,
        headers={
            "Content-Type": "application/json",
            "x-api-key": api_key,
            "anthropic-version": "2023-06-01",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=API_TIMEOUT) as resp:
            return json.loads(resp.read())
    except urllib.error.HTTPError as e:
        try:
            return json.loads(e.read().decode())
        except Exception:
            return {"error": {"message": f"HTTP {e.code}"}}
    except Exception as e:
        return {"error": {"message": str(e)}}


async def process_message(message, agent_config, session_messages,
                          memory_db, agent_name="default"):
    """Run the agent loop for one user turn.  Yields streaming events."""
    import asyncio

    api_key = get_api_key()
    if not api_key:
        yield {
            "type": "error",
            "message": "No Anthropic API key. Run: kmac secrets set anthropic",
        }
        return

    model = agent_config.get("model", "claude-sonnet-4-6")

    memories = []
    try:
        memories = memory_db.search_memories(agent_name, message, limit=5)
    except Exception:
        pass

    system = build_system_prompt(agent_config, memories)
    session_messages.append({"role": "user", "content": message})

    loop = asyncio.get_event_loop()

    for round_num in range(MAX_TOOL_ROUNDS):
        model_short = model.split("-")[1] if "-" in model else model
        yield {
            "type": "status",
            "text": "Thinking" if round_num == 0 else "Working",
            "model": model_short,
        }

        response = await loop.run_in_executor(
            None, _call_claude_sync, session_messages, system, model, api_key,
        )

        if "error" in response:
            err = response["error"]
            msg = err.get("message", str(err)) if isinstance(err, dict) else str(err)
            yield {"type": "error", "message": msg}
            break

        content = response.get("content", [])
        stop_reason = response.get("stop_reason", "end_turn")
        session_messages.append({"role": "assistant", "content": content})

        tool_results = []
        for block in content:
            btype = block.get("type")
            if btype == "text" and block.get("text", "").strip():
                yield {"type": "text", "content": block["text"]}
            elif btype == "tool_use":
                yield {
                    "type": "tool_call",
                    "tool": block["name"],
                    "input": block["input"],
                }
                result, preview = await tools.execute(
                    block["name"], block["input"]
                )
                yield {
                    "type": "tool_output",
                    "tool": block["name"],
                    "preview": preview,
                }
                tool_results.append({
                    "type": "tool_result",
                    "tool_use_id": block["id"],
                    "content": str(result),
                })

        if stop_reason == "tool_use" and tool_results:
            session_messages.append({"role": "user", "content": tool_results})
            continue
        break

    yield {"type": "done"}

    if len(session_messages) >= 4 and memory_db:
        try:
            log.info("Auto-memory: extracting from %d messages", len(session_messages))
            await _extract_memories(
                session_messages, agent_name, memory_db, api_key
            )
        except Exception:
            log.warning("Auto-memory extraction failed", exc_info=True)


_MEMORY_PROMPT = """\
Review this conversation and extract 0-3 key facts worth remembering long-term.
Only extract genuinely useful facts: project decisions, user preferences, environment details,
architecture choices, deployment targets, credentials locations, etc.
Do NOT extract transient information, greetings, or things that are obvious.
If nothing is worth remembering, return an empty array.

Return ONLY a JSON array of strings, e.g.: ["fact 1", "fact 2"]
Return [] if nothing is worth saving."""


async def _extract_memories(messages, agent_name, memory_db, api_key):
    """Post-conversation: ask a cheap model to identify persistent facts."""
    import asyncio

    recent = messages[-8:]
    convo = "\n".join(
        f"{m['role']}: {m['content'] if isinstance(m['content'], str) else '[tool interaction]'}"
        for m in recent
        if isinstance(m, dict) and m.get("role") in ("user", "assistant")
        and isinstance(m.get("content"), str)
    )
    if len(convo) < 50:
        log.info("Auto-memory: conversation too short (%d chars), skipping", len(convo))
        return

    extract_model = MODEL_SHORTCUTS.get("haiku", "claude-haiku-4-5")
    body = json.dumps({
        "model": extract_model,
        "max_tokens": 512,
        "system": _MEMORY_PROMPT,
        "messages": [{"role": "user", "content": convo}],
    }).encode()
    req = urllib.request.Request(
        "https://api.anthropic.com/v1/messages",
        data=body,
        headers={
            "Content-Type": "application/json",
            "x-api-key": api_key,
            "anthropic-version": "2023-06-01",
        },
    )
    loop = asyncio.get_event_loop()
    try:
        def _call():
            with urllib.request.urlopen(req, timeout=30) as resp:
                return json.loads(resp.read())
        response = await loop.run_in_executor(None, _call)
    except Exception as exc:
        log.info("Auto-memory: API call failed: %s", exc)
        return

    text = ""
    for block in response.get("content", []):
        if block.get("type") == "text":
            text += block["text"]

    text = text.strip()
    # Strip markdown code fences if present
    if "```" in text:
        import re
        match = re.search(r'```(?:json)?\s*\n?(.*?)\n?\s*```', text, re.DOTALL)
        if match:
            text = match.group(1).strip()

    # Find the JSON array
    bracket_start = text.find("[")
    bracket_end = text.rfind("]")
    if bracket_start >= 0 and bracket_end > bracket_start:
        text = text[bracket_start:bracket_end + 1]

    try:
        facts = json.loads(text)
    except (json.JSONDecodeError, ValueError):
        log.info("Auto-memory: could not parse response: %s", text[:100])
        return

    if not isinstance(facts, list):
        return

    if not facts:
        log.info("Auto-memory: nothing worth remembering")
        return

    for fact in facts[:3]:
        if isinstance(fact, str) and len(fact) > 10:
            existing = memory_db.search_memories(agent_name, fact, limit=3)
            if any(fact.lower() in m["content"].lower() or
                   m["content"].lower() in fact.lower()
                   for m in existing):
                continue
            memory_db.add_memory(agent_name, fact, "auto", "conversation")
            log.info("Auto-memory saved: %s", fact[:60])
