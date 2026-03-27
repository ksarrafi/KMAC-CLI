"""KmacAgent daemon — unix-socket server managing multiple agent profiles."""

import asyncio
import json
import logging
import os
import shutil
import signal
import time
from pathlib import Path

from .config import (
    AGENT_HOME, SOCKET_PATH, PID_FILE, LOG_FILE, DB_DIR,
    DEFAULT_MODEL, DEFAULT_SYSTEM_PROMPT, MODEL_SHORTCUTS,
)
from .memory import MemoryDB
from . import runtime

log = logging.getLogger("kmac-agent")


class AgentDaemon:
    """Single daemon that manages multiple named agent profiles."""

    def __init__(self):
        self.dbs: dict[str, MemoryDB] = {}
        self._server = None
        self._start_time = time.time()

    # ── database helpers ─────────────────────────────────────────────

    def _get_db(self, agent_name: str) -> MemoryDB:
        if agent_name not in self.dbs:
            db_path = DB_DIR / agent_name / "memory.db"
            self.dbs[agent_name] = MemoryDB(db_path)
            db = self.dbs[agent_name]
            if not db.get_agent(agent_name):
                db.create_agent(
                    agent_name, model=DEFAULT_MODEL,
                    system_prompt=DEFAULT_SYSTEM_PROMPT,
                )
        return self.dbs[agent_name]

    # ── socket server ────────────────────────────────────────────────

    async def handle_connection(self, reader: asyncio.StreamReader,
                                writer: asyncio.StreamWriter):
        try:
            data = await asyncio.wait_for(reader.readline(), timeout=10)
            if not data:
                return
            request = json.loads(data.decode())
            action = request.get("action", "")

            async for event in self._dispatch(action, request):
                writer.write(json.dumps(event).encode() + b"\n")
                await writer.drain()
        except asyncio.TimeoutError:
            self._write_err(writer, "Request timeout")
        except json.JSONDecodeError:
            self._write_err(writer, "Invalid JSON")
        except Exception as exc:
            log.exception("Connection error")
            self._write_err(writer, str(exc))
        finally:
            try:
                writer.close()
                await writer.wait_closed()
            except Exception:
                pass

    @staticmethod
    def _write_err(writer, msg):
        try:
            writer.write(json.dumps({"type": "error", "message": msg}).encode() + b"\n")
        except Exception:
            pass

    # ── request dispatch ─────────────────────────────────────────────

    async def _dispatch(self, action, request):
        agent = request.get("agent", "default")

        handlers = {
            "ask":            lambda: self._ask(agent, request),
            "status":         lambda: self._oneshot(self._status()),
            "ping":           lambda: self._oneshot({"type": "result", "data": {"ok": True}}),
            "agents-list":    lambda: self._oneshot(self._agents_list()),
            "agent-create":   lambda: self._oneshot(self._agent_create(request)),
            "agent-delete":   lambda: self._oneshot(self._agent_delete(request)),
            "agent-info":     lambda: self._oneshot(self._agent_info(agent)),
            "sessions-list":  lambda: self._oneshot(self._sessions_list(agent)),
            "session-delete": lambda: self._oneshot(self._session_delete(request)),
            "memory-search":  lambda: self._oneshot(self._memory_search(agent, request)),
            "memory-add":     lambda: self._oneshot(self._memory_add(agent, request)),
            "memory-list":    lambda: self._oneshot(self._memory_list(agent)),
            "memory-delete":  lambda: self._oneshot(self._memory_delete(request)),
            "task-create":    lambda: self._oneshot(self._task_create(agent, request)),
            "tasks-list":     lambda: self._oneshot(self._tasks_list(agent)),
        }

        handler = handlers.get(action)
        if handler:
            async for evt in handler():
                yield evt
        else:
            yield {"type": "error", "message": f"Unknown action: {action}"}

        yield {"type": "done"}

    async def _oneshot(self, result):
        yield result

    # ── ask (conversation) ───────────────────────────────────────────

    async def _ask(self, agent_name, request):
        message = request.get("message", "")
        session_id = request.get("session", "")
        if not message:
            yield {"type": "error", "message": "No message provided"}
            return

        db = self._get_db(agent_name)
        agent_cfg = db.get_agent(agent_name) or {
            "model": DEFAULT_MODEL,
            "system_prompt": DEFAULT_SYSTEM_PROMPT,
            "context": "",
        }

        # Apply per-request model override
        req_model = request.get("model")
        if req_model:
            agent_cfg = dict(agent_cfg)
            agent_cfg["model"] = MODEL_SHORTCUTS.get(req_model, req_model)

        if session_id:
            sess = db.get_session(session_id)
            if sess:
                messages = json.loads(sess["messages"])
            else:
                sess = db.create_session(agent_name, session_id)
                messages = []
        else:
            sess = db.create_session(agent_name)
            session_id = sess["id"]
            messages = []

        yield {"type": "session", "id": session_id}

        async for event in runtime.process_message(
            message, agent_cfg, messages, db, agent_name
        ):
            yield event

        db.update_session(session_id, messages)

    # ── status ───────────────────────────────────────────────────────

    def _status(self):
        uptime = int(time.time() - self._start_time)
        total = {"agents": 0, "sessions": 0, "memories": 0}
        for db in self.dbs.values():
            s = db.stats()
            for k in total:
                total[k] += s.get(k, 0)
        # Count agent dirs that haven't been loaded yet
        if DB_DIR.exists():
            for d in DB_DIR.iterdir():
                if d.is_dir() and d.name not in self.dbs:
                    total["agents"] += 1
        return {
            "type": "result",
            "data": {
                "running": True,
                "pid": os.getpid(),
                "uptime": uptime,
                "uptime_human": f"{uptime // 3600}h {(uptime % 3600) // 60}m {uptime % 60}s",
                "socket": str(SOCKET_PATH),
                **total,
            },
        }

    # ── agents ───────────────────────────────────────────────────────

    def _agents_list(self):
        agents = []
        seen = set()
        if DB_DIR.exists():
            for d in sorted(DB_DIR.iterdir()):
                if d.is_dir() and (d / "memory.db").exists():
                    db = self._get_db(d.name)
                    a = db.get_agent(d.name)
                    if a:
                        st = db.stats()
                        a["sessions"] = st["sessions"]
                        a["memories"] = st["memories"]
                        agents.append(a)
                        seen.add(d.name)
        if "default" not in seen:
            db = self._get_db("default")
            a = db.get_agent("default")
            if a:
                st = db.stats()
                a["sessions"] = st["sessions"]
                a["memories"] = st["memories"]
                agents.append(a)
        return {"type": "result", "data": {"agents": agents}}

    def _agent_create(self, req):
        name = req.get("name", "")
        if not name or not name.replace("-", "").replace("_", "").isalnum():
            return {"type": "error", "message": "Invalid agent name (alphanumeric, -, _)"}
        model = MODEL_SHORTCUTS.get(req.get("model", ""), req.get("model", DEFAULT_MODEL))
        prompt = req.get("system_prompt", DEFAULT_SYSTEM_PROMPT)
        context = req.get("context", "")
        db = self._get_db(name)
        agent = db.create_agent(name, model, prompt, context)
        return {"type": "result", "data": {"agent": agent}}

    def _agent_delete(self, req):
        name = req.get("name", "")
        if name == "default":
            return {"type": "error", "message": "Cannot delete default agent"}
        if name in self.dbs:
            self.dbs[name].close()
            del self.dbs[name]
        d = DB_DIR / name
        if d.exists():
            shutil.rmtree(d)
        return {"type": "result", "data": {"deleted": name}}

    def _agent_info(self, agent_name):
        db = self._get_db(agent_name)
        a = db.get_agent(agent_name)
        if not a:
            return {"type": "error", "message": f"Agent '{agent_name}' not found"}
        a.update(db.stats())
        return {"type": "result", "data": {"agent": a}}

    # ── sessions ─────────────────────────────────────────────────────

    def _sessions_list(self, agent_name):
        db = self._get_db(agent_name)
        sessions = db.list_sessions(agent_name)
        for s in sessions:
            msgs = json.loads(s.get("messages", "[]"))
            s["message_count"] = len(
                [m for m in msgs if m.get("role") == "user"]
            )
            s.pop("messages", None)
        return {"type": "result", "data": {"sessions": sessions}}

    def _session_delete(self, req):
        sid = req.get("session_id", "")
        agent = req.get("agent", "default")
        self._get_db(agent).delete_session(sid)
        return {"type": "result", "data": {"deleted": sid}}

    # ── memory ───────────────────────────────────────────────────────

    def _memory_search(self, agent_name, req):
        q = req.get("query", "")
        if not q:
            return {"type": "error", "message": "No query"}
        results = self._get_db(agent_name).search_memories(agent_name, q)
        return {"type": "result", "data": {"memories": results}}

    def _memory_add(self, agent_name, req):
        content = req.get("content", "")
        if not content:
            return {"type": "error", "message": "No content"}
        mid = self._get_db(agent_name).add_memory(
            agent_name, content,
            req.get("category", "fact"),
            req.get("source", "manual"),
        )
        return {"type": "result", "data": {"id": mid}}

    def _memory_list(self, agent_name):
        return {
            "type": "result",
            "data": {"memories": self._get_db(agent_name).list_memories(agent_name)},
        }

    def _memory_delete(self, req):
        mid = req.get("id")
        if not mid:
            return {"type": "error", "message": "No memory ID"}
        agent = req.get("agent", "default")
        self._get_db(agent).delete_memory(int(mid))
        return {"type": "result", "data": {"deleted": mid}}

    # ── tasks ────────────────────────────────────────────────────────

    def _task_create(self, agent_name, req):
        desc = req.get("description", "")
        if not desc:
            return {"type": "error", "message": "No description"}
        task = self._get_db(agent_name).create_task(agent_name, desc)
        return {"type": "result", "data": {"task": task}}

    def _tasks_list(self, agent_name):
        return {
            "type": "result",
            "data": {"tasks": self._get_db(agent_name).list_tasks(agent_name)},
        }

    # ── lifecycle ────────────────────────────────────────────────────

    async def start(self):
        AGENT_HOME.mkdir(parents=True, exist_ok=True)
        os.chmod(str(AGENT_HOME), 0o700)

        if SOCKET_PATH.exists():
            SOCKET_PATH.unlink()

        self._server = await asyncio.start_unix_server(
            self.handle_connection, path=str(SOCKET_PATH),
        )
        os.chmod(str(SOCKET_PATH), 0o600)
        PID_FILE.write_text(str(os.getpid()))

        log.info("KmacAgent daemon started (PID: %d, socket: %s)",
                 os.getpid(), SOCKET_PATH)

        loop = asyncio.get_event_loop()
        for sig in (signal.SIGTERM, signal.SIGINT):
            loop.add_signal_handler(sig, lambda: asyncio.ensure_future(self.stop()))

        try:
            await self._server.serve_forever()
        except asyncio.CancelledError:
            pass

    async def stop(self):
        log.info("Shutting down...")
        if self._server:
            self._server.close()
            await self._server.wait_closed()
        for db in self.dbs.values():
            db.close()
        for path in (SOCKET_PATH, PID_FILE):
            if path.exists():
                path.unlink()
        log.info("Daemon stopped.")
        asyncio.get_event_loop().stop()


def run_daemon():
    """Entry point called by __main__.py or the bash CLI."""
    AGENT_HOME.mkdir(parents=True, exist_ok=True)
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(message)s",
        handlers=[
            logging.FileHandler(str(LOG_FILE)),
            logging.StreamHandler(),
        ],
    )
    daemon = AgentDaemon()
    asyncio.run(daemon.start())
