"""Client — connects to the daemon socket, sends requests, displays output."""

import json
import os
import socket
import sys
import threading

from .config import SOCKET_PATH

# ── Colors ───────────────────────────────────────────────────────────
G = "\033[0;32m"; Y = "\033[0;33m"; C = "\033[0;36m"
R = "\033[0;31m"; B = "\033[1m"; D = "\033[2m"; N = "\033[0m"


class Spinner:
    """Braille spinner matching KMAC style."""
    def __init__(self, label="Thinking", model=""):
        self.label = label
        self.model = model
        self._stop = threading.Event()
        self._thread = None

    def start(self):
        self._stop.clear()
        self._thread = threading.Thread(target=self._run, daemon=True)
        self._thread.start()

    def _run(self):
        frames = list("\u28cb\u2819\u2839\u2838\u283c\u2834\u2826\u2827\u2847\u280f")
        colors = [C, "\033[0;35m", "\033[0;34m", C]
        i = cc = 0
        tag = f" {D}({self.model}){N}" if self.model else ""
        while not self._stop.is_set():
            f = frames[i % len(frames)]
            clr = colors[cc % len(colors)]
            d = i % 12
            dots = "   " if d < 3 else ".  " if d < 6 else ".. " if d < 9 else "..."
            sys.stderr.write(f"\r  {clr}{f}{N} {B}\U0001f916 {self.label}{dots}{N}{tag}  ")
            sys.stderr.flush()
            i += 1
            if i % 4 == 0:
                cc += 1
            self._stop.wait(0.12)

    def stop(self):
        self._stop.set()
        if self._thread:
            self._thread.join(timeout=1)
        sys.stderr.write("\r\033[K")
        sys.stderr.flush()


# ── Socket helpers ───────────────────────────────────────────────────

def _connect():
    sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    sock.connect(str(SOCKET_PATH))
    return sock


def _stream(sock):
    """Yield parsed JSON events from a socket."""
    buf = b""
    while True:
        chunk = sock.recv(8192)
        if not chunk:
            break
        buf += chunk
        while b"\n" in buf:
            line, buf = buf.split(b"\n", 1)
            if line:
                yield json.loads(line)


# ── Display helpers ──────────────────────────────────────────────────

def _display_tool_call(event):
    tool = event.get("tool", "")
    inp = event.get("input", {})
    labels = {
        "bash": f"{D}${N} {C}{inp.get('command', '')}{N}",
        "read_file": f"{D}\U0001f4c4 {inp.get('path', '')}{N}",
        "write_file": f"{D}\u270f\ufe0f  {inp.get('path', '')}{N}",
        "edit_file": f"{D}\u270f\ufe0f  {inp.get('path', '')}{N}",
        "list_dir": f"{D}\U0001f4c2 {inp.get('path', '.')}/{N}",
        "grep_search": f"{D}\U0001f50d grep '{inp.get('pattern', '')}'{N}",
        "delegate_agent": f"{D}\U0001f4e4 delegate -> {inp.get('agent', '?')}{N}",
        "web_search": f"{D}\U0001f310 search: {inp.get('query', '')}{N}",
        "web_fetch": f"{D}\U0001f310 fetch: {inp.get('url', '')[:60]}{N}",
        "browser": f"{D}\U0001f5a5  browser {inp.get('action', '')} {inp.get('url', '')[:40]}{N}",
        "image": f"{D}\U0001f5bc  analyze: {inp.get('path', '')}{N}",
        "image_generate": f"{D}\U0001f3a8 generate: {inp.get('prompt', '')[:50]}{N}",
        "apply_patch": f"{D}\U0001f4cb patch ({len(inp.get('patch', '').split(chr(10)))} lines){N}",
    }
    print(f"\n  {labels.get(tool, f'{D}{tool}{N}')}")


def _display_result(data):
    """Pretty-print a structured result dict."""
    if "running" in data:
        print(f"\n  {B}KmacAgent{N}")
        print(f"  Status:   {G}\u25cf Running{N}")
        print(f"  PID:      {data.get('pid', '?')}")
        print(f"  Uptime:   {data.get('uptime_human', '?')}")
        print(f"  Agents:   {data.get('agents', 0)}")
        print(f"  Sessions: {data.get('sessions', 0)}")
        print(f"  Memories: {data.get('memories', 0)}")
        rt = data.get('running_tasks', 0)
        ct = data.get('completed_tasks', 0)
        task_str = f"{rt} running" if rt else "idle"
        if ct:
            task_str += f", {ct} completed"
        print(f"  Tasks:    {task_str}")
        tt = data.get("total_tokens", 0)
        if tt:
            if tt > 1_000_000:
                print(f"  Tokens:   {tt / 1_000_000:.1f}M total")
            elif tt > 1000:
                print(f"  Tokens:   {tt / 1000:.1f}K total")
            else:
                print(f"  Tokens:   {tt}")
        np = data.get("plugins", 0)
        ms = data.get("mcp_servers", 0)
        mt = data.get("mcp_tools", 0)
        if np or ms:
            ext_parts = []
            if np:
                ext_parts.append(f"{np} plugins")
            if ms:
                ext_parts.append(f"{ms} MCP servers ({mt} tools)")
            print(f"  Ext:      {', '.join(ext_parts)}")
        wp = data.get("web_port")
        if wp:
            print(f"  Web UI:   {C}http://127.0.0.1:{wp}{N}")
        print(f"  Socket:   {D}{data.get('socket', '?')}{N}")
        return

    if "agents" in data and isinstance(data["agents"], list):
        agents = data["agents"]
        if not agents:
            print(f"  {D}No agents configured{N}"); return
        print(f"\n  {B}{'NAME':<16} {'MODEL':<12} {'SESSIONS':<10} {'MEMORIES':<10}{N}")
        print(f"  {D}{'─' * 52}{N}")
        for a in agents:
            short = a.get("model", "?").split("-")[1] if "-" in a.get("model", "") else a.get("model", "?")
            print(f"  {a['name']:<16} {short:<12} {a.get('sessions', 0):<10} {a.get('memories', 0):<10}")

    elif "sessions" in data:
        ss = data["sessions"]
        if not ss:
            print(f"  {D}No sessions{N}"); return
        print(f"\n  {B}{'SESSION':<14} {'AGENT':<12} {'UPDATED':<18} {'MSGS'}{N}")
        print(f"  {D}{'─' * 52}{N}")
        for s in ss:
            print(f"  {s['id']:<14} {s.get('agent', '?'):<12} "
                  f"{s.get('updated', '?')[:16]:<18} {s.get('message_count', 0)}")

    elif "memories" in data and isinstance(data["memories"], list):
        mm = data["memories"]
        if not mm:
            print(f"  {D}No memories{N}"); return
        for m in mm:
            print(f"  {D}[{m['id']}]{N} {m['content'][:80]}")

    elif "tasks" in data:
        tt = data["tasks"]
        if not tt:
            print(f"  {D}No tasks{N}"); return
        icons = {"queued": "\u25cb", "running": "\u25cf", "completed": "\u2713",
                 "failed": "\u2717", "cancelled": "\u2013"}
        colors = {"queued": D, "running": C, "completed": G, "failed": R, "cancelled": D}
        for t in tt:
            clr = colors.get(t["status"], "")
            icon = icons.get(t["status"], "?")
            print(f"  {clr}{icon}{N} {t['description'][:55]} "
                  f"{D}[{t['id']}] {t['status']}{N}")

    elif "task" in data and "result" in data.get("task", {}):
        t = data["task"]
        icon = icons_map.get(t.get("status", ""), "?") if False else ""
        print(f"\n  {B}Task {t.get('id', '?')}{N}  ({t.get('status', '?')})")
        print(f"  {D}{t.get('description', '')}{N}")
        result = t.get("result") or ""
        if result:
            print(f"\n{result[:2000]}")
            if len(result) > 2000:
                print(f"\n  {D}... ({len(result) - 2000} more chars){N}")

    elif "agent" in data:
        a = data["agent"]
        short = a.get("model", "?").split("-")[1] if "-" in a.get("model", "") else a.get("model", "?")
        print(f"\n  {B}{a['name']}{N}")
        print(f"  Model:    {short}")
        if a.get("system_prompt"):
            print(f"  Prompt:   {a['system_prompt'][:60]}...")
        if a.get("context"):
            print(f"  Context:  {a['context'][:60]}...")

    elif "usage" in data:
        uu = data["usage"]
        if not uu:
            print(f"  {D}No token usage recorded{N}"); return
        print(f"\n  {B}{'MODEL':<28} {'INPUT':<12} {'OUTPUT':<12} {'CALLS'}{N}")
        print(f"  {D}{'─' * 60}{N}")
        total_in = total_out = total_calls = 0
        for u in uu:
            inp = u.get("inp", 0)
            out = u.get("out", 0)
            calls = u.get("calls", 0)
            total_in += inp; total_out += out; total_calls += calls
            model = u.get("model", "?")
            print(f"  {model:<28} {inp:>10,}  {out:>10,}  {calls:>5}")
        print(f"  {D}{'─' * 60}{N}")
        print(f"  {'TOTAL':<28} {total_in:>10,}  {total_out:>10,}  {total_calls:>5}")

    elif "schedules" in data:
        ss = data["schedules"]
        if not ss:
            print(f"  {D}No schedules{N}"); return
        for s in ss:
            enabled = f"{G}on{N}" if s.get("enabled") else f"{R}off{N}"
            print(f"  [{enabled}] {s['description'][:50]} "
                  f"{D}({s['cron']}) [{s['id']}]{N}")

    elif "schedule" in data:
        s = data["schedule"]
        print(f"  {G}\u2713{N} Schedule created: {s['description']} ({s['cron']}) [ID: {s['id']}]")

    elif "exported" in data:
        print(f"  {G}\u2713{N} Exported to: {data['exported']}")
        print(f"  {D}Agents: {data.get('agents', 0)}, "
              f"Memories: {data.get('memories', 0)}{N}")

    elif "imported" in data:
        imp = data["imported"]
        print(f"  {G}\u2713{N} Imported: {imp.get('agents', 0)} agents, "
              f"{imp.get('memories', 0)} memories, "
              f"{imp.get('schedules', 0)} schedules")

    elif "pruned_sessions" in data:
        n = data["pruned_sessions"]
        print(f"  {G}\u2713{N} Pruned {n} stale session{'s' if n != 1 else ''}")

    elif "forked" in data:
        print(f"  {G}\u2713{N} Forked session {data['from']} -> {data['forked']} "
              f"({data.get('messages', 0)} messages)")

    elif "plugins" in data or "mcp_tools" in data:
        ps = data.get("plugins", [])
        mt = data.get("mcp_tools", [])
        if ps:
            print(f"\n  {B}Plugins:{N}")
            for p in ps:
                print(f"  {G}\u25b8{N} {p['name']}: {D}{p.get('description', '')[:60]}{N}")
        else:
            print(f"  {D}No plugins (add to ~/.cache/kmac/agent/plugins/){N}")
        if mt:
            print(f"\n  {B}MCP Tools:{N}")
            for t in mt:
                print(f"  {C}\u25b8{N} {t['name']}: {D}{t.get('description', '')[:60]}{N}")

    elif "workflows" in data:
        wfs = data["workflows"]
        if not wfs:
            print(f"  {D}No workflows available{N}"); return
        print(f"\n  {B}{'ID':<20} {'NAME':<25} {'STEPS':<8} {'SOURCE'}{N}")
        print(f"  {D}{'─' * 65}{N}")
        for w in wfs:
            print(f"  {w['id']:<20} {w['name']:<25} {w.get('steps', 0):<8} {D}{w.get('source', '')}{N}")

    elif "skills" in data:
        ss = data["skills"]
        if not ss:
            print(f"  {D}No skills loaded{N}"); return
        print(f"\n  {B}Skills:{N}")
        for s in ss:
            print(f"  {G}\u25b8{N} {s['name']} {D}({s.get('lines', 0)} lines) — {s.get('description', '')[:60]}{N}")
            print(f"    {D}{s.get('path', '')}{N}")

    elif "profiles" in data:
        ps = data["profiles"]
        print(f"\n  {B}Tool Profiles:{N}")
        for p in ps:
            tool_list = ", ".join(p["tools"][:8])
            if len(p["tools"]) > 8:
                tool_list += f" ... (+{len(p['tools']) - 8})"
            print(f"  {G}\u25b8{N} {p['name']}: {D}{tool_list}{N}")
        gs = data.get("groups", [])
        if gs:
            print(f"\n  {B}Tool Groups:{N} {D}{', '.join(gs)}{N}")

    elif "watches" in data:
        ww = data.get("watches", [])
        if not ww:
            print(f"  {D}No file watches configured{N}"); return
        for w in ww:
            status = f"{G}on{N}" if w.get("enabled", True) else f"{R}off{N}"
            paths = ", ".join(w.get("paths", []))
            print(f"  [{status}] {w.get('task', '')[:45]} {D}({paths}){N}")

    elif "deleted" in data:
        print(f"  {G}\u2713{N} Deleted: {data['deleted']}")
    elif "id" in data:
        print(f"  {G}\u2713{N} Created (ID: {data['id']})")
    elif "task" in data:
        t = data["task"]
        print(f"  {G}\u2713{N} Task queued: {t['description']} (ID: {t['id']})")
    else:
        print(json.dumps(data, indent=2))


# ── Streaming event renderer ────────────────────────────────────────

def _render_events(sock):
    """Read streamed events from socket and display them.  Returns session id."""
    spinner = None
    session_id = ""
    try:
        for event in _stream(sock):
            etype = event.get("type", "")
            if etype == "status":
                if spinner:
                    spinner.stop()
                spinner = Spinner(event.get("text", "Thinking"), event.get("model", ""))
                spinner.start()
            elif etype == "text":
                if spinner:
                    spinner.stop(); spinner = None
                print(f"\n{event['content']}")
            elif etype == "tool_call":
                if spinner:
                    spinner.stop(); spinner = None
                _display_tool_call(event)
            elif etype == "tool_output":
                for ln in event.get("preview", "").split("\n")[:20]:
                    print(f"  {D}  {ln}{N}")
            elif etype == "session":
                session_id = event.get("id", "")
            elif etype == "error":
                if spinner:
                    spinner.stop(); spinner = None
                print(f"\n  {R}Error: {event['message']}{N}")
            elif etype == "result":
                if spinner:
                    spinner.stop(); spinner = None
                _display_result(event.get("data", {}))
            elif etype == "done":
                break
    finally:
        if spinner:
            spinner.stop()
    return session_id


# ── Public API ───────────────────────────────────────────────────────

def send_request(action, args):
    """Build request from CLI args, send to daemon, display response."""
    req = _build_request(action, args)
    try:
        sock = _connect()
    except (FileNotFoundError, ConnectionRefusedError):
        print(f"  {R}Agent not running.{N}  Start with: {G}kmac agent start{N}",
              file=sys.stderr)
        sys.exit(1)
    sock.sendall(json.dumps(req).encode() + b"\n")
    _render_events(sock)
    sock.close()


def chat_interactive(agent="default", session="", model=""):
    """Interactive chat loop connected to the daemon."""
    print(f"\n  {B}KmacAgent{N} \u2014 Interactive")
    print(f"  {D}Agent: {agent} | Type 'exit' to quit, 'help' for commands{N}\n")

    current_session = session

    while True:
        try:
            user_input = input(f"  {B}you>{N} ")
        except (EOFError, KeyboardInterrupt):
            print()
            break

        stripped = user_input.strip()
        if not stripped:
            continue
        low = stripped.lower()

        if low in ("exit", "quit"):
            break
        if low == "help":
            print(f"\n  {B}Commands:{N}")
            print(f"  {G}exit{N}           Quit")
            print(f"  {G}model <name>{N}   Switch model (opus, sonnet, haiku)")
            print(f"  {G}agent <name>{N}   Switch agent")
            print(f"  {G}new{N}            New session")
            print(f"  {G}sessions{N}       List sessions")
            print(f"  {G}memory{N}         Show memories")
            print(f"  {G}remember X{N}     Save a memory")
            print(f"  {G}fork{N}           Fork current session")
            print(f"  {G}plugins{N}        List plugins + MCP tools")
            print(f"  {G}workflows{N}      List available workflows")
            print(f"  {G}run <id>{N}       Run a workflow")
            print(f"  {G}skills{N}         List loaded skills")
            print(f"  {G}profiles{N}       List tool profiles")
            print()
            continue
        if low.startswith("model "):
            model = low.split(None, 1)[1]
            print(f"  {C}\u25b8{N} Switched to {model}")
            continue
        if low.startswith("agent "):
            agent = low.split(None, 1)[1]
            current_session = ""
            print(f"  {C}\u25b8{N} Switched to agent: {agent}")
            continue
        if low == "new":
            current_session = ""
            print(f"  {C}\u25b8{N} New session")
            continue
        if low == "sessions":
            send_request("sessions-list", ["-a", agent])
            continue
        if low == "memory":
            send_request("memory-list", ["-a", agent])
            continue
        if low.startswith("remember "):
            fact = stripped.split(None, 1)[1]
            send_request("memory-add", ["-a", agent, fact])
            continue
        if low == "fork":
            if current_session:
                send_request("session-fork", ["-a", agent, current_session])
            else:
                print(f"  {D}No active session to fork{N}")
            continue
        if low == "plugins":
            send_request("plugins-list", [])
            continue
        if low == "workflows":
            send_request("workflows-list", [])
            continue
        if low.startswith("run "):
            wf_id = stripped.split(None, 1)[1]
            send_request("workflow-run", ["-a", agent, wf_id])
            continue
        if low == "skills":
            send_request("skills-list", ["-a", agent])
            continue
        if low == "profiles":
            send_request("profiles-list", [])
            continue

        req = {"action": "ask", "agent": agent, "message": stripped}
        if current_session:
            req["session"] = current_session
        if model:
            req["model"] = model

        try:
            sock = _connect()
        except (FileNotFoundError, ConnectionRefusedError):
            print(f"\n  {R}Agent not running.{N}  Start with: {G}kmac agent start{N}")
            continue

        sock.sendall(json.dumps(req).encode() + b"\n")
        sid = _render_events(sock)
        sock.close()
        if sid:
            current_session = sid
        print()

    if current_session:
        print(f"\n  {D}Session: {current_session}{N}")
        print(f"  {D}Resume:  kmac agent chat -s {current_session}{N}")
    print()


# ── Request builder ──────────────────────────────────────────────────

def _build_request(action, args):
    req = {"action": action}

    _FLAGS = {
        "-a": "agent", "--agent": "agent",
        "-m": "model", "--model": "model",
        "-s": "session", "--session": "session",
        "-n": "name", "--name": "name",
        "--system-prompt": "system_prompt",
        "--context": "context",
        "--cron": "cron",
        "-q": "query", "--query": "query",
        "--id": "id",
        "-p": "priority", "--priority": "priority",
        "--parent": "parent_task_id",
        "--tag": "tag",
    }
    _BOOL_FLAGS = {"--approve": "approval_required"}

    # First pass: extract all flags
    positional = []
    i = 0
    while i < len(args):
        a = args[i]
        if a in _FLAGS and i + 1 < len(args):
            req[_FLAGS[a]] = args[i + 1]
            i += 2
        elif a in _BOOL_FLAGS:
            req[_BOOL_FLAGS[a]] = True
            i += 1
        else:
            positional.append(args[i])
            i += 1

    # Second pass: assign positional args
    single_arg_actions = {
        "agent-create": "name", "agent-delete": "name",
        "memory-delete": "id", "session-delete": "session_id",
        "task-cancel": "task_id", "task-run": "task_id",
        "task-result": "task_id", "task-approve": "task_id",
        "task-reject": "task_id", "task-subtasks": "task_id",
        "schedule-delete": "schedule_id",
        "import": "path",
        "session-fork": "session_id",
        "workflow-run": "workflow_id",
    }
    multi_arg_actions = {
        "ask": "message", "memory-add": "content",
        "memory-search": "query", "task-create": "description",
        "schedule-create": "description",
    }

    if positional:
        if action in single_arg_actions:
            req[single_arg_actions[action]] = positional[0]
        else:
            field = multi_arg_actions.get(action, "message")
            req[field] = " ".join(positional)

    return req
