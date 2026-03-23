"""Session manager — multiple concurrent AI agent sessions."""

import asyncio
import json
import logging
import os
import pty
import re
import signal
import time
import uuid
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

from config import PILOT_DIR, active_agent

log = logging.getLogger(__name__)

_MAX_OUTPUT_LINES = 10_000

SESSIONS_DIR = PILOT_DIR / "sessions"
SESSIONS_DIR.mkdir(parents=True, exist_ok=True)


def _clean_env() -> dict:
    env = dict(os.environ)
    for key in ("ANTHROPIC_API_KEY", "OPENAI_API_KEY"):
        val = env.get(key, "")
        if not val or "your-" in val or "placeholder" in val.lower():
            env.pop(key, None)
    return env


_ANSI_RE = re.compile(
    r"\x1b\[[\d;]*[A-Za-z]"   # CSI sequences
    r"|\x1b\][^\x07]*\x07"    # OSC sequences
    r"|\x1b[()][AB012]"       # charset selection
    r"|\x1b\[\?[\d;]*[hl]"   # private mode set/reset
    r"|\r"                     # carriage return
)


def _strip_ansi(text: str) -> str:
    return _ANSI_RE.sub("", text)


def _agent_cmd(agent: str, prompt: str) -> tuple[list[str], bool]:
    """Returns (command, is_stream_json)."""
    if agent == "cursor":
        return ["cursor", "agent", "--trust", prompt], False
    return ["claude", "-p", "--output-format", "stream-json", "--verbose", prompt], True


def _parse_stream_event(raw: str) -> Optional[list[str] | str]:
    """Parse a stream-json line from Claude CLI into readable text.

    Returns None if the event should be silently skipped, a string for
    a single line, or a list of strings for multi-line output.
    """
    if not raw.strip():
        return None
    try:
        evt = json.loads(raw)
    except json.JSONDecodeError:
        return raw

    etype = evt.get("type", "")

    if etype == "system" and evt.get("subtype") == "init":
        model = _strip_ansi(evt.get("model", "unknown"))
        return f"⚙ Agent initialized (model: {model})"

    if etype == "assistant":
        msg = evt.get("message", {})
        content_blocks = msg.get("content", [])
        lines: list[str] = []
        for block in content_blocks:
            btype = block.get("type", "")
            if btype == "text":
                text = _strip_ansi(block.get("text", ""))
                if text.strip():
                    lines.extend(text.splitlines())
            elif btype == "tool_use":
                name = block.get("name", "unknown")
                inp = block.get("input", {})
                summary = _tool_summary(name, inp)
                lines.append(f"🔧 {name}: {summary}")
        if msg.get("stop_reason") == "tool_use" and not lines:
            return None
        return lines if lines else None

    if etype == "tool":
        content_blocks = evt.get("content", [])
        for block in content_blocks:
            if block.get("type") == "tool_result":
                text = block.get("content", "")
                if isinstance(text, str) and text.strip():
                    preview = text.strip().splitlines()
                    if len(preview) > 3:
                        return [f"  {l}" for l in preview[:3]] + [f"  … ({len(preview)} lines)"]
                    return [f"  {l}" for l in preview]
        return None

    if etype == "result":
        result_text = evt.get("result", "")
        cost = evt.get("total_cost_usd", 0)
        duration = evt.get("duration_ms", 0)
        parts = []
        if result_text:
            parts.extend(result_text.splitlines())
        parts.append(f"✓ Done ({duration/1000:.1f}s, ${cost:.4f})")
        return parts

    return None


def _tool_summary(name: str, inp: dict) -> str:
    """Create a short human-readable summary for a tool invocation."""
    if name in ("Read", "read"):
        return inp.get("file_path", inp.get("path", "file"))
    if name in ("Edit", "edit", "Write", "write"):
        return inp.get("file_path", inp.get("path", "file"))
    if name in ("Bash", "bash"):
        cmd = inp.get("command", "")
        return cmd[:80] + ("…" if len(cmd) > 80 else "")
    if name in ("Glob", "glob"):
        return inp.get("pattern", inp.get("glob_pattern", ""))
    if name in ("Grep", "grep"):
        return f'/{inp.get("pattern", "")}/'
    if name in ("WebSearch",):
        return inp.get("query", inp.get("search_term", ""))
    if name in ("WebFetch",):
        return inp.get("url", "")
    if name in ("TodoWrite",):
        return "updating tasks"
    return str(inp)[:60]


@dataclass
class Session:
    id: str
    project: str
    project_dir: str
    task: str
    agent: str
    agent_label: str
    status: str = "idle"
    started: str = ""
    output_lines: list[str] = field(default_factory=list)
    pid: Optional[int] = None
    stream_json: bool = False
    master_fd: Optional[int] = None
    _proc: Optional[asyncio.subprocess.Process] = field(default=None, repr=False)

    @property
    def running(self) -> bool:
        return self._proc is not None and self._proc.returncode is None

    @property
    def log_path(self) -> Path:
        return SESSIONS_DIR / f"{self.id}.log"

    def to_dict(self, include_output: bool = False) -> dict:
        d = {
            "id": self.id,
            "project": self.project,
            "dir": self.project_dir,
            "task": self.task,
            "agent": self.agent,
            "agent_label": self.agent_label,
            "status": self.status,
            "started": self.started,
            "running": self.running,
            "output_lines": len(self.output_lines),
            "pid": self.pid,
        }
        if include_output:
            d["output"] = self.output_lines
        return d


def _trim_output_lines(session: Session) -> None:
    while len(session.output_lines) > _MAX_OUTPUT_LINES:
        session.output_lines.pop(0)


class SessionManager:
    """Manages multiple concurrent AI agent sessions."""

    def __init__(self):
        self._sessions: dict[str, Session] = {}
        self._subscribers: list[asyncio.Queue] = []
        self._state_lock = asyncio.Lock()

    # ── queries ──────────────────────────────────────────────────────

    @property
    def sessions(self) -> list[Session]:
        return list(self._sessions.values())

    def get(self, session_id: str) -> Optional[Session]:
        return self._sessions.get(session_id)

    @property
    def running_count(self) -> int:
        return sum(1 for s in self._sessions.values() if s.running)

    @property
    def active_sessions(self) -> list[Session]:
        return [s for s in self._sessions.values() if s.running]

    # ── pub/sub ──────────────────────────────────────────────────────

    async def subscribe(self) -> asyncio.Queue:
        q: asyncio.Queue = asyncio.Queue(maxsize=1000)
        async with self._state_lock:
            self._subscribers.append(q)
        return q

    async def unsubscribe(self, q: asyncio.Queue):
        async with self._state_lock:
            if q in self._subscribers:
                self._subscribers.remove(q)

    async def _broadcast(self, event: dict):
        async with self._state_lock:
            subs = list(self._subscribers)
        for q in subs:
            try:
                q.put_nowait(event)
            except asyncio.QueueFull:
                pass

    # ── session lifecycle ────────────────────────────────────────────

    async def create_session(self, project: str, project_dir: str,
                              prompt: str = "", agent_choice: str = "") -> dict:
        if not os.path.isdir(project_dir):
            return {"error": f"Directory not found: {project_dir}"}

        agent = agent_choice or active_agent()
        agent_label = "Cursor Agent" if agent == "cursor" else "Claude Code"

        sid = uuid.uuid4().hex[:8]
        session = Session(
            id=sid,
            project=project,
            project_dir=project_dir,
            task=prompt,
            agent=agent,
            agent_label=agent_label,
            status="idle" if not prompt else "running",
            started=time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        )
        async with self._state_lock:
            self._sessions[sid] = session
            session.log_path.write_text("")

        await self._broadcast({
            "type": "session_created",
            "session_id": sid,
            "project": project,
            "agent": agent_label,
            "prompt": prompt,
        })

        # If a prompt was provided, start the agent immediately
        if prompt:
            await self._run_agent(session, prompt)

        return {"ok": True, "session": session.to_dict()}

    async def write_stdin(self, session_id: str, text: str) -> dict:
        """Write raw input to a running session's PTY (master side)."""
        session = self._sessions.get(session_id)
        if not session:
            return {"error": "Session not found"}
        if not session.running:
            return {"error": "Session not running"}
        fd = session.master_fd
        if fd is None:
            return {"error": "No PTY available"}
        data = text.encode("utf-8", errors="replace")
        loop = asyncio.get_running_loop()

        def _write():
            os.write(fd, data)

        try:
            await loop.run_in_executor(None, _write)
        except OSError as e:
            return {"error": str(e)}
        return {"ok": True}

    async def send_message(self, session_id: str, message: str) -> dict:
        """Send a message to a session — starts the agent with this prompt."""
        session = self._sessions.get(session_id)
        if not session:
            return {"error": "Session not found"}
        if session.running:
            return {"error": "Agent is still running. Wait for it to finish."}

        # Append the user message to output as a visual separator
        user_line = f"▶ {message}"
        session.output_lines.append("")
        session.output_lines.append(user_line)
        session.output_lines.append("")
        _trim_output_lines(session)

        await self._broadcast({"type": "output", "session_id": session.id, "line": ""})
        await self._broadcast({"type": "output", "session_id": session.id, "line": user_line})
        await self._broadcast({"type": "output", "session_id": session.id, "line": ""})

        # Update the task description to the latest message
        session.task = message
        session.status = "running"

        await self._run_agent(session, message)

        return {"ok": True, "status": "running"}

    async def _run_agent(self, session: Session, prompt: str):
        """Launch the agent subprocess inside a PTY for real-time output."""
        cmd, is_stream = _agent_cmd(session.agent, prompt)
        session.stream_json = is_stream
        env = _clean_env()

        master_fd, slave_fd = pty.openpty()
        session._proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdin=slave_fd,
            stdout=slave_fd,
            stderr=slave_fd,
            cwd=session.project_dir,
            env=env,
            start_new_session=True,
        )
        os.close(slave_fd)
        session.master_fd = master_fd
        session.pid = session._proc.pid
        asyncio.create_task(self._read_pty_output(session, master_fd))

    async def _emit(self, session: Session, line: str):
        """Append a line to session output and broadcast it."""
        session.output_lines.append(line)
        _trim_output_lines(session)
        with open(session.log_path, "a") as f:
            f.write(line + "\n")
        await self._broadcast({
            "type": "output",
            "session_id": session.id,
            "line": line,
        })

    async def _finish_session(self, session: Session):
        """Wait for process exit and broadcast the finished event."""
        rc = await session._proc.wait() if session._proc else -1
        session.status = "completed" if rc == 0 else "failed"
        await self._broadcast({
            "type": "session_finished",
            "session_id": session.id,
            "status": session.status,
            "exit_code": rc,
            "project": session.project,
            "lines": len(session.output_lines),
        })

    async def _process_line(self, session: Session, raw_line: str):
        """Process a single line — handles both stream-json and plain text."""
        if session.stream_json:
            clean = _strip_ansi(raw_line).strip()
            if not clean:
                return
            readable = _parse_stream_event(clean)
            if readable is not None:
                for rl in readable if isinstance(readable, list) else [readable]:
                    await self._emit(session, rl)
        else:
            clean = _strip_ansi(raw_line).rstrip()
            if clean:
                await self._emit(session, clean)

    async def _read_pty_output(self, session: Session, master_fd: int):
        """Read from a PTY, process each line, broadcast to subscribers."""
        loop = asyncio.get_running_loop()
        buf = ""
        try:
            while True:
                try:
                    data = await loop.run_in_executor(
                        None, os.read, master_fd, 4096
                    )
                except OSError:
                    break
                if not data:
                    break
                buf += data.decode("utf-8", errors="replace")
                while "\n" in buf:
                    line, buf = buf.split("\n", 1)
                    await self._process_line(session, line)
        except Exception as exc:
            log.exception("Error reading PTY output for session %s: %s", session.id, exc)
        finally:
            session.master_fd = None
            try:
                os.close(master_fd)
            except OSError:
                pass

        if buf.strip():
            await self._process_line(session, buf)

        await self._finish_session(session)

    async def stop_session(self, session_id: str) -> dict:
        session = self._sessions.get(session_id)
        if not session:
            return {"error": "Session not found"}
        if not session.running:
            return {"error": "Session not running"}

        if not session._proc or session._proc.pid is None:
            return {"error": "No process to stop"}
        try:
            os.killpg(os.getpgid(session._proc.pid), signal.SIGTERM)
        except (ProcessLookupError, PermissionError, OSError):
            try:
                session._proc.terminate()
            except ProcessLookupError:
                pass

        session.status = "stopped"
        await self._broadcast({
            "type": "session_stopped",
            "session_id": session.id,
            "project": session.project,
        })
        return {"ok": True}

    async def remove_session(self, session_id: str) -> dict:
        async with self._state_lock:
            session = self._sessions.get(session_id)
            if not session:
                return {"error": "Session not found"}
            if session.running:
                return {"error": "Stop session first"}

            try:
                session.log_path.unlink(missing_ok=True)
            except Exception:
                pass

            del self._sessions[session_id]
        return {"ok": True}

    # ── ask (legacy — kept for backward compat) ──────────────────────

    async def ask(self, session_id: str, question: str) -> dict:
        return await self.send_message(session_id, question)
