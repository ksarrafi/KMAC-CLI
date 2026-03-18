"""Agent manager — launches Claude Code / Cursor as a subprocess, captures output."""

import asyncio
import json
import os
import signal
import time
from pathlib import Path
from typing import Optional

from config import PILOT_DIR, active_agent, load_config


TASK_FILE = PILOT_DIR / "task.json"
AGENT_LOG = PILOT_DIR / "agent.log"
AGENT_PID = PILOT_DIR / "agent.pid"


class AgentManager:
    """Manages AI agent subprocess lifecycle and output capture."""

    def __init__(self):
        self._proc: Optional[asyncio.subprocess.Process] = None
        self._subscribers: list[asyncio.Queue] = []
        self._task_meta: dict = {}
        self._output_lines: list[str] = []

    # ── state ────────────────────────────────────────────────────────

    @property
    def running(self) -> bool:
        return self._proc is not None and self._proc.returncode is None

    @property
    def task(self) -> dict:
        if self._task_meta:
            return self._task_meta
        if TASK_FILE.exists():
            try:
                return json.loads(TASK_FILE.read_text())
            except Exception:
                return {}
        return {}

    @property
    def output(self) -> list[str]:
        return self._output_lines

    # ── WebSocket pub/sub ────────────────────────────────────────────

    def subscribe(self) -> asyncio.Queue:
        q: asyncio.Queue = asyncio.Queue()
        self._subscribers.append(q)
        return q

    def unsubscribe(self, q: asyncio.Queue):
        if q in self._subscribers:
            self._subscribers.remove(q)

    async def _broadcast(self, event: dict):
        for q in self._subscribers:
            try:
                q.put_nowait(event)
            except asyncio.QueueFull:
                pass

    # ── task lifecycle ───────────────────────────────────────────────

    async def start_task(self, project_name: str, project_dir: str,
                         prompt: str, agent: str = "") -> dict:
        if self.running:
            return {"error": "Agent is already running", "project": self._task_meta.get("project")}

        if not os.path.isdir(project_dir):
            return {"error": f"Directory not found: {project_dir}"}

        agent = agent or active_agent()
        agent_label = "Cursor Agent" if agent == "cursor" else "Claude Code"

        self._task_meta = {
            "project": project_name,
            "dir": project_dir,
            "task": prompt,
            "agent": agent,
            "agent_label": agent_label,
            "started": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "status": "running",
        }
        TASK_FILE.write_text(json.dumps(self._task_meta, indent=2))

        self._output_lines = []
        AGENT_LOG.write_text("")

        await self._broadcast({
            "type": "task_started",
            "project": project_name,
            "agent": agent_label,
            "prompt": prompt,
        })

        if agent == "cursor":
            cmd = ["cursor", "agent", prompt]
        else:
            cmd = ["claude", "--print", prompt]

        self._proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.STDOUT,
            cwd=project_dir,
        )
        AGENT_PID.write_text(str(self._proc.pid))

        asyncio.create_task(self._read_output())
        return {"ok": True, "project": project_name, "agent": agent_label, "pid": self._proc.pid}

    async def _read_output(self):
        """Read agent stdout line-by-line, broadcast each line."""
        try:
            assert self._proc and self._proc.stdout
            async for raw_line in self._proc.stdout:
                line = raw_line.decode("utf-8", errors="replace").rstrip("\n")
                self._output_lines.append(line)

                with open(AGENT_LOG, "a") as f:
                    f.write(line + "\n")

                await self._broadcast({"type": "output", "line": line})
        except Exception:
            pass

        rc = await self._proc.wait() if self._proc else -1
        status = "completed" if rc == 0 else "failed"
        self._task_meta["status"] = status
        TASK_FILE.write_text(json.dumps(self._task_meta, indent=2))

        await self._broadcast({
            "type": "task_finished",
            "status": status,
            "exit_code": rc,
            "project": self._task_meta.get("project"),
            "lines": len(self._output_lines),
        })

        try:
            AGENT_PID.unlink()
        except FileNotFoundError:
            pass

    async def stop(self) -> dict:
        if not self.running:
            return {"error": "No agent running"}

        assert self._proc
        try:
            os.killpg(os.getpgid(self._proc.pid), signal.SIGTERM)
        except (ProcessLookupError, PermissionError):
            self._proc.terminate()

        self._task_meta["status"] = "stopped"
        TASK_FILE.write_text(json.dumps(self._task_meta, indent=2))
        await self._broadcast({"type": "task_stopped", "project": self._task_meta.get("project")})
        return {"ok": True}

    # ── ask (follow-up) ──────────────────────────────────────────────

    async def ask(self, question: str) -> dict:
        if self.running:
            return {"error": "Agent is busy"}

        project_dir = self._task_meta.get("dir", "")
        if not project_dir or not os.path.isdir(project_dir):
            return {"error": "No active project"}

        agent = self._task_meta.get("agent", active_agent())

        context = ""
        if self._output_lines:
            tail = self._output_lines[-50:]
            context = "Previous context:\n" + "\n".join(tail) + "\n\nFollow-up: "

        prompt = context + question

        if agent == "cursor":
            cmd = ["cursor", "agent", prompt]
        else:
            cmd = ["claude", "--print", prompt]

        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.STDOUT,
            cwd=project_dir,
        )

        stdout, _ = await proc.communicate()
        output = stdout.decode("utf-8", errors="replace") if stdout else ""

        self._output_lines = output.splitlines()
        AGENT_LOG.write_text(output)

        return {"ok": True, "output": output, "exit_code": proc.returncode}
