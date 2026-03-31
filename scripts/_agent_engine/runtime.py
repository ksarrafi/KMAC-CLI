"""Agent runtime — conversation loop with Claude API and tool dispatch."""

import json
import logging
import os
import platform
import subprocess
import urllib.request
import urllib.error

import time

from . import tools
from . import tools_extended
from .config import (
    DEFAULT_SYSTEM_PROMPT, MAX_TOKENS, MAX_TOOL_ROUNDS, API_TIMEOUT,
    MODEL_SHORTCUTS, PROVIDER_PREFIXES, OPENAI_API_URL, OLLAMA_BASE_URL,
    SUMMARIZE_AFTER_MESSAGES, CONTEXT_TOKEN_LIMIT,
    MAX_RETRIES, RETRY_BACKOFF, RETRYABLE_HTTP_CODES,
    MODEL_COSTS, COST_WARNING_THRESHOLD,
    RATE_LIMIT_RPM, RATE_LIMIT_TPM,
)
from .rate_limiter import RateLimiter
from .skills import build_skills_prompt
from .tool_profiles import filter_tools

_rate_limiter = RateLimiter(RATE_LIMIT_RPM, RATE_LIMIT_TPM)

_plugin_registry: list[dict] = []
_mcp_manager = None


def register_plugins(plugins: list[dict]):
    global _plugin_registry
    _plugin_registry = plugins


def register_mcp(mcp_mgr):
    global _mcp_manager
    _mcp_manager = mcp_mgr

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

    agent_name = agent_config.get("name", "default")
    try:
        skills_section = build_skills_prompt(agent_name)
        if skills_section:
            parts.append(skills_section)
    except Exception:
        pass

    return "\n".join(parts)


def _detect_provider(model: str) -> str:
    for prefix, provider in PROVIDER_PREFIXES.items():
        if model.startswith(prefix):
            return provider
    return "anthropic"


def _estimate_cost(model: str, est_input: int) -> float | None:
    """Estimate cost of an API call. Returns dollars or None."""
    costs = MODEL_COSTS.get(model)
    if not costs:
        return None
    inp_cost, out_cost = costs
    est_output = min(est_input // 2, MAX_TOKENS)
    return (est_input * inp_cost + est_output * out_cost) / 1_000_000


def _call_api_sync(messages, system, model, api_key, agent_config=None):
    """Route API call with retry logic. Returns (response_dict, provider)."""
    # Rate limit check
    est_tokens = sum(len(str(m.get("content", ""))) // 4 for m in messages)
    warning = _rate_limiter.wait_if_needed(est_tokens)
    if warning:
        return {"error": {"message": warning}}, "rate_limited"

    provider = _detect_provider(model)

    for attempt in range(MAX_RETRIES + 1):
        if provider == "openai":
            response = _call_openai_sync(messages, system, model)
        elif provider == "ollama":
            response = _call_ollama_sync(messages, system, model.replace("ollama/", ""))
        else:
            response = _call_claude_sync(
                messages, system, model, api_key, agent_config,
            )

        # Record the request for rate limiting
        usage = response.get("usage", {})
        _rate_limiter.record(usage.get("input_tokens", 0) + usage.get("output_tokens", 0))

        if "error" not in response:
            return response, provider

        err = response.get("error", {})
        err_msg = err.get("message", str(err)) if isinstance(err, dict) else str(err)

        retryable = False
        for code in RETRYABLE_HTTP_CODES:
            if str(code) in err_msg:
                retryable = True
                break

        if not retryable or attempt >= MAX_RETRIES:
            return response, provider

        backoff = RETRY_BACKOFF[min(attempt, len(RETRY_BACKOFF) - 1)]
        log.info("Retrying API call (attempt %d/%d, backoff %ds): %s",
                 attempt + 1, MAX_RETRIES, backoff, err_msg[:80])
        time.sleep(backoff)

    return response, provider


def _call_claude_sync(messages, system, model, api_key, agent_config=None):
    """Blocking Claude API call."""
    all_tools = _get_all_tools(agent_config)
    body = json.dumps({
        "model": model,
        "max_tokens": MAX_TOKENS,
        "system": system,
        "tools": all_tools,
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


def _call_openai_sync(messages, system, model):
    """Call OpenAI-compatible API (no tool support, text only)."""
    api_key = os.environ.get("OPENAI_API_KEY", "")
    if not api_key:
        return {"error": {"message": "No OPENAI_API_KEY set"}}
    oai_msgs = [{"role": "system", "content": system}]
    for m in messages:
        if isinstance(m.get("content"), str):
            oai_msgs.append({"role": m["role"], "content": m["content"]})
        elif isinstance(m.get("content"), list):
            text = " ".join(
                b.get("text", "") for b in m["content"]
                if b.get("type") == "text"
            )
            if text:
                oai_msgs.append({"role": m["role"], "content": text})
    body = json.dumps({
        "model": model, "max_tokens": MAX_TOKENS, "messages": oai_msgs,
    }).encode()
    req = urllib.request.Request(
        OPENAI_API_URL, data=body,
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {api_key}",
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=API_TIMEOUT) as resp:
            data = json.loads(resp.read())
        choice = data.get("choices", [{}])[0]
        text = choice.get("message", {}).get("content", "")
        usage = data.get("usage", {})
        return {
            "content": [{"type": "text", "text": text}],
            "stop_reason": "end_turn",
            "usage": {
                "input_tokens": usage.get("prompt_tokens", 0),
                "output_tokens": usage.get("completion_tokens", 0),
            },
        }
    except Exception as e:
        return {"error": {"message": f"OpenAI: {e}"}}


def _call_ollama_sync(messages, system, model):
    """Call local Ollama API."""
    oai_msgs = [{"role": "system", "content": system}]
    for m in messages:
        if isinstance(m.get("content"), str):
            oai_msgs.append({"role": m["role"], "content": m["content"]})
    body = json.dumps({
        "model": model, "messages": oai_msgs, "stream": False,
    }).encode()
    url = f"{OLLAMA_BASE_URL}/api/chat"
    req = urllib.request.Request(
        url, data=body, headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=API_TIMEOUT) as resp:
            data = json.loads(resp.read())
        text = data.get("message", {}).get("content", "")
        return {
            "content": [{"type": "text", "text": text}],
            "stop_reason": "end_turn",
            "usage": {
                "input_tokens": data.get("prompt_eval_count", 0),
                "output_tokens": data.get("eval_count", 0),
            },
        }
    except Exception as e:
        return {"error": {"message": f"Ollama: {e}"}}


def _estimate_tokens(messages) -> int:
    """Rough token estimate: ~4 chars per token."""
    total = 0
    for m in messages:
        c = m.get("content", "")
        if isinstance(c, str):
            total += len(c) // 4
        elif isinstance(c, list):
            for b in c:
                total += len(str(b)) // 4
    return total


_SUMMARIZE_PROMPT = """\
Summarize the conversation so far into a concise paragraph.
Preserve: key decisions, facts learned, files edited, commands run, and current task state.
Be brief but complete enough that the conversation can continue from this summary."""


async def _summarize_messages(messages, api_key, model):
    """Compress old messages into a summary to stay within context limits."""
    import asyncio

    convo = "\n".join(
        f"{m['role']}: {m['content'] if isinstance(m['content'], str) else '[tool interaction]'}"
        for m in messages
        if isinstance(m, dict) and isinstance(m.get("content"), str)
    )
    summary_model = MODEL_SHORTCUTS.get("haiku", "claude-haiku-4-5")
    body = json.dumps({
        "model": summary_model, "max_tokens": 1024,
        "system": _SUMMARIZE_PROMPT,
        "messages": [{"role": "user", "content": convo[:30000]}],
    }).encode()
    req = urllib.request.Request(
        "https://api.anthropic.com/v1/messages", data=body,
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
        text = ""
        for block in response.get("content", []):
            if block.get("type") == "text":
                text += block["text"]
        return text.strip() if text.strip() else None
    except Exception:
        log.warning("Summarization failed", exc_info=True)
        return None


def _get_all_tools(agent_config: dict | None = None):
    """Combine built-in, extended, plugin, MCP tools and apply profile filter."""
    from . import plugins as plugins_mod
    all_tools = list(tools.TOOLS)
    all_tools.extend(tools_extended.EXTENDED_TOOLS)
    all_tools.append({
        "name": "delegate_agent",
        "description": (
            "Delegate a subtask to another named agent profile. "
            "The other agent will process the message independently and return its response."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "agent": {"type": "string", "description": "Name of the agent to delegate to"},
                "message": {"type": "string", "description": "Task description for the other agent"},
            },
            "required": ["agent", "message"],
        },
    })
    if _plugin_registry:
        all_tools.extend(plugins_mod.get_tool_schemas(_plugin_registry))
    if _mcp_manager:
        all_tools.extend(_mcp_manager.get_tool_schemas())

    if agent_config:
        all_tools = filter_tools(all_tools, agent_config)

    return all_tools


_EXTENDED_TOOL_NAMES = {t["name"] for t in tools_extended.EXTENDED_TOOLS}


async def _execute_tool(name: str, inp: dict, memory_db=None, agent_name="default"):
    """Execute any tool — built-in, extended, plugin, MCP, or delegation."""
    from . import plugins as plugins_mod

    if name == "delegate_agent":
        return await _delegate(inp, memory_db, agent_name)

    if _mcp_manager and _mcp_manager.has_tool(name):
        return await _mcp_manager.execute(name, inp)

    for plugin in _plugin_registry:
        if plugin.get("name") == name:
            return await plugins_mod.execute_plugin(plugin, inp)

    if name in _EXTENDED_TOOL_NAMES:
        api_key = get_api_key()
        return await tools_extended.execute(name, inp, api_key)

    return await tools.execute(name, inp)


async def _delegate(inp: dict, memory_db, caller_agent: str):
    """Delegate a subtask to another agent."""
    target = inp.get("agent", "")
    message = inp.get("message", "")
    if not target or not message:
        return "Need agent name and message", "missing params"
    if target == caller_agent:
        return "Cannot delegate to self", "self-delegation"

    if not memory_db:
        return "No memory DB for delegation", "no db"

    from .config import DEFAULT_MODEL, DEFAULT_SYSTEM_PROMPT
    agent_cfg = memory_db.get_agent(target)
    if not agent_cfg:
        return f"Agent '{target}' not found", f"agent '{target}' not found"

    messages = []
    output_parts = []
    async for event in process_message(message, agent_cfg, messages, memory_db, target):
        etype = event.get("type", "")
        if etype == "text":
            output_parts.append(event.get("content", ""))
        elif etype == "error":
            output_parts.append(f"ERROR: {event.get('message', '')}")

    result = "\n".join(output_parts) or "(no response)"
    preview = result[:500]
    return result, preview


async def process_message(message, agent_config, session_messages,
                          memory_db, agent_name="default"):
    """Run the agent loop for one user turn.  Yields streaming events."""
    import asyncio

    api_key = get_api_key()
    model = agent_config.get("model", "claude-sonnet-4-6")
    provider = _detect_provider(model)

    if provider == "anthropic" and not api_key:
        yield {
            "type": "error",
            "message": "No Anthropic API key. Run: kmac secrets set anthropic",
        }
        return

    memories = []
    try:
        memories = memory_db.search_memories(agent_name, message, limit=5)
    except Exception:
        pass

    system = build_system_prompt(agent_config, memories)

    # RAG: inject relevant project context for first message
    if len(session_messages) == 0:
        try:
            from .rag import build_rag_context
            rag_ctx = build_rag_context(message, max_chars=6000)
            if rag_ctx:
                system += rag_ctx
        except Exception:
            pass

    # Cost warning for expensive models
    est_input = _estimate_tokens(session_messages) + len(message) // 4
    est_cost = _estimate_cost(model, est_input)
    if est_cost and est_cost > COST_WARNING_THRESHOLD:
        yield {
            "type": "status",
            "text": f"Estimated cost: ${est_cost:.2f}",
            "model": model.split("/")[-1].split("-")[1] if "-" in model else model,
        }

    # Auto-summarize if conversation is getting long
    if (len(session_messages) > SUMMARIZE_AFTER_MESSAGES or
            _estimate_tokens(session_messages) > CONTEXT_TOKEN_LIMIT):
        log.info("Summarizing %d messages for context management", len(session_messages))
        summary = await _summarize_messages(session_messages, api_key, model)
        if summary:
            session_messages.clear()
            session_messages.append({
                "role": "user",
                "content": f"[Previous conversation summary: {summary}]",
            })
            session_messages.append({
                "role": "assistant",
                "content": "Understood, I have the context from our previous conversation. How can I help?",
            })

    session_messages.append({"role": "user", "content": message})
    loop = asyncio.get_event_loop()
    total_input = 0
    total_output = 0

    for round_num in range(MAX_TOOL_ROUNDS):
        model_short = model.split("/")[-1].split("-")[1] if "-" in model else model.split("/")[-1]
        yield {
            "type": "status",
            "text": "Thinking" if round_num == 0 else "Working",
            "model": model_short,
        }

        response, _ = await loop.run_in_executor(
            None,
            _call_api_sync,
            session_messages,
            system,
            model,
            api_key,
            agent_config,
        )

        # Track tokens
        usage = response.get("usage", {})
        total_input += usage.get("input_tokens", 0)
        total_output += usage.get("output_tokens", 0)

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
                result, preview = await _execute_tool(
                    block["name"], block["input"], memory_db, agent_name,
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

    # Log token usage
    if memory_db and (total_input or total_output):
        try:
            memory_db.log_tokens(agent_name, model, total_input, total_output)
        except Exception:
            pass

    yield {
        "type": "done",
        "input_tokens": total_input,
        "output_tokens": total_output,
    }

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
