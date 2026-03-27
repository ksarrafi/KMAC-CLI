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

    elif "memories" in data:
        mm = data["memories"]
        if not mm:
            print(f"  {D}No memories{N}"); return
        for m in mm:
            print(f"  {D}[{m['id']}]{N} {m['content'][:80]}")

    elif "tasks" in data:
        tt = data["tasks"]
        if not tt:
            print(f"  {D}No tasks{N}"); return
        icons = {"queued": "\u25cb", "running": "\u25cf", "completed": "\u2713", "failed": "\u2717"}
        for t in tt:
            print(f"  {icons.get(t['status'], '?')} {t['description'][:60]} {D}({t['status']}){N}")

    elif "agent" in data:
        a = data["agent"]
        short = a.get("model", "?").split("-")[1] if "-" in a.get("model", "") else a.get("model", "?")
        print(f"\n  {B}{a['name']}{N}")
        print(f"  Model:    {short}")
        if a.get("system_prompt"):
            print(f"  Prompt:   {a['system_prompt'][:60]}...")
        if a.get("context"):
            print(f"  Context:  {a['context'][:60]}...")

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
    i = 0
    while i < len(args):
        a = args[i]
        if a in ("-a", "--agent") and i + 1 < len(args):
            req["agent"] = args[i + 1]; i += 2
        elif a in ("-m", "--model") and i + 1 < len(args):
            req["model"] = args[i + 1]; i += 2
        elif a in ("-s", "--session") and i + 1 < len(args):
            req["session"] = args[i + 1]; i += 2
        elif a in ("-n", "--name") and i + 1 < len(args):
            req["name"] = args[i + 1]; i += 2
        elif a in ("--system-prompt",) and i + 1 < len(args):
            req["system_prompt"] = args[i + 1]; i += 2
        elif a in ("--context",) and i + 1 < len(args):
            req["context"] = args[i + 1]; i += 2
        elif a in ("-q", "--query") and i + 1 < len(args):
            req["query"] = args[i + 1]; i += 2
        elif a in ("--id",) and i + 1 < len(args):
            req["id"] = args[i + 1]; i += 2
        else:
            single_arg_actions = {
                "agent-create": "name", "agent-delete": "name",
                "memory-delete": "id", "session-delete": "session_id",
            }
            multi_arg_actions = {
                "ask": "message", "memory-add": "content",
                "memory-search": "query", "task-create": "description",
            }
            if action in single_arg_actions:
                req[single_arg_actions[action]] = args[i]
                i += 1
                continue
            field = multi_arg_actions.get(action, "message")
            req[field] = " ".join(args[i:])
            break
        continue
    return req
