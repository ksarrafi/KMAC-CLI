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
    SESSION_MAX_AGE_DAYS, SESSION_PRUNE_INTERVAL,
)
from .memory import MemoryDB
from . import runtime
from . import plugins as plugins_mod
from .mcp_client import MCPManager
from .watcher import FileWatcher
from .web import start_web_server
from . import workflows as workflows_mod
from .skills import list_skills_info
from .tool_profiles import get_profile_names, get_group_names, PROFILES

log = logging.getLogger("kmac-agent")

TASK_POLL_INTERVAL = 5
MAX_CONCURRENT_TASKS = 2


class AgentDaemon:
    """Single daemon that manages multiple named agent profiles."""

    def __init__(self):
        self.dbs: dict[str, MemoryDB] = {}
        self._server = None
        self._start_time = time.time()
        self._task_runner: asyncio.Task | None = None
        self._running_tasks: dict[str, asyncio.Task] = {}
        self._tasks_completed = 0
        self._last_prune = 0
        self._last_schedule_check = 0
        self._mcp = MCPManager()
        self._watcher: FileWatcher | None = None
        self._web_server = None
        self._plugins: list[dict] = []
        self._heartbeats: dict[str, float] = {}
        self._heartbeat_timeout = 120

    # ── database helpers ─────────────────────────────────────────────

    def _get_db(self, agent_name: str) -> MemoryDB:
        if agent_name not in self.dbs:
            db_path = DB_DIR / agent_name / "memory.db"
            self.dbs[agent_name] = MemoryDB(db_path)
            db = self.dbs[agent_name]
            db.migrate()
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
        except ConnectionResetError:
            pass
        except BrokenPipeError:
            pass
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
            "task-cancel":    lambda: self._oneshot(self._task_cancel(request)),
            "task-approve":   lambda: self._oneshot(self._task_approve(request)),
            "task-reject":    lambda: self._oneshot(self._task_reject(request)),
            "task-subtasks":  lambda: self._oneshot(self._task_subtasks(request)),
            "task-run":       lambda: self._oneshot(self._task_run(agent, request)),
            "task-result":    lambda: self._oneshot(self._task_result(agent, request)),
            "tasks-list":     lambda: self._oneshot(self._tasks_list(agent)),
            "agent-update":   lambda: self._oneshot(self._agent_update(agent, request)),
            "export":         lambda: self._oneshot(self._export(agent)),
            "import":         lambda: self._oneshot(self._import(agent, request)),
            "prune":          lambda: self._oneshot(self._prune(agent)),
            "token-usage":    lambda: self._oneshot(self._token_usage(agent)),
            "schedule-create": lambda: self._oneshot(self._schedule_create(agent, request)),
            "schedule-list":  lambda: self._oneshot(self._schedule_list(agent)),
            "schedule-delete": lambda: self._oneshot(self._schedule_delete(request)),
            "session-fork":   lambda: self._oneshot(self._session_fork(agent, request)),
            "plugins-list":   lambda: self._oneshot(self._plugins_list()),
            "mcp-status":     lambda: self._oneshot(self._mcp_status()),
            "watches-list":   lambda: self._oneshot(self._watches_list()),
            "workflows-list": lambda: self._oneshot(self._workflows_list()),
            "workflow-run":   lambda: self._workflow_run(agent, request),
            "skills-list":    lambda: self._oneshot(self._skills_list(agent)),
            "profiles-list":  lambda: self._oneshot(self._profiles_list()),
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

        self._heartbeats[agent_name] = time.time()
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
        active_tasks = 0
        total_in = 0
        total_out = 0
        for db in self.dbs.values():
            s = db.stats()
            for k in total:
                total[k] += s.get(k, 0)
            active_tasks += s.get("active_tasks", 0)
            total_in += s.get("total_input_tokens", 0)
            total_out += s.get("total_output_tokens", 0)
        if DB_DIR.exists():
            for d in DB_DIR.iterdir():
                if d.is_dir() and d.name not in self.dbs:
                    total["agents"] += 1
        mcp_stats = self._mcp.stats()
        web_port = None
        if self._web_server:
            try:
                web_port = self._web_server.server_address[1]
            except Exception:
                pass
        total_cost = sum(
            db.stats().get("total_task_cost_usd", 0) for db in self.dbs.values()
        )
        now = time.time()
        agent_health = {}
        for name, last_beat in self._heartbeats.items():
            elapsed = now - last_beat
            if elapsed < self._heartbeat_timeout:
                agent_health[name] = "healthy"
            else:
                agent_health[name] = "stale"
        return {
            "type": "result",
            "data": {
                "running": True,
                "pid": os.getpid(),
                "uptime": uptime,
                "uptime_human": f"{uptime // 3600}h {(uptime % 3600) // 60}m {uptime % 60}s",
                "socket": str(SOCKET_PATH),
                "running_tasks": len(self._running_tasks),
                "completed_tasks": self._tasks_completed,
                "total_tokens": total_in + total_out,
                "total_cost_usd": round(total_cost, 4),
                "plugins": len(self._plugins),
                "mcp_servers": mcp_stats.get("servers", 0),
                "mcp_tools": mcp_stats.get("tools", 0),
                "web_port": web_port,
                "agent_health": agent_health,
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
        task = self._get_db(agent_name).create_task(
            agent_name, desc,
            priority=req.get("priority", "normal"),
            tags=req.get("tags"),
            parent_task_id=req.get("parent_task_id"),
            approval_required=req.get("approval_required", False),
        )
        return {"type": "result", "data": {"task": task}}

    def _tasks_list(self, agent_name):
        db = self._get_db(agent_name)
        return {
            "type": "result",
            "data": {
                "tasks": db.list_tasks(agent_name),
                "stats": db.task_stats(agent_name),
            },
        }

    def _task_cancel(self, req):
        tid = req.get("task_id", "")
        agent = req.get("agent", "default")
        if not tid:
            return {"type": "error", "message": "No task ID"}
        if tid in self._running_tasks:
            self._running_tasks[tid].cancel()
        self._get_db(agent).update_task(tid, "cancelled")
        return {"type": "result", "data": {"cancelled": tid}}

    def _task_approve(self, req):
        tid = req.get("task_id", "")
        agent = req.get("agent", "default")
        if not tid:
            return {"type": "error", "message": "No task ID"}
        db = self._get_db(agent)
        task = db.get_task(tid)
        if not task:
            return {"type": "error", "message": f"Task {tid} not found"}
        if task["status"] != "review":
            return {"type": "error", "message": f"Task {tid} is not in review (status: {task['status']})"}
        db.approve_task(tid, approved_by=req.get("approved_by", "user"))
        return {"type": "result", "data": {"approved": tid}}

    def _task_reject(self, req):
        tid = req.get("task_id", "")
        agent = req.get("agent", "default")
        if not tid:
            return {"type": "error", "message": "No task ID"}
        db = self._get_db(agent)
        task = db.get_task(tid)
        if not task:
            return {"type": "error", "message": f"Task {tid} not found"}
        db.reject_task(tid)
        return {"type": "result", "data": {"rejected": tid}}

    def _task_subtasks(self, req):
        tid = req.get("task_id", "")
        agent = req.get("agent", "default")
        if not tid:
            return {"type": "error", "message": "No task ID"}
        subs = self._get_db(agent).get_subtasks(tid)
        return {"type": "result", "data": {"subtasks": subs}}

    def _task_run(self, agent_name, req):
        """Immediately trigger a pending task."""
        tid = req.get("task_id", "")
        if not tid:
            return {"type": "error", "message": "No task ID"}
        db = self._get_db(agent_name)
        task = db.get_task(tid)
        if not task:
            return {"type": "error", "message": f"Task {tid} not found"}
        if task["status"] not in ("pending", "approved"):
            return {"type": "error", "message": f"Task {tid} cannot run (status: {task['status']})"}
        asyncio.ensure_future(self._execute_task(agent_name, task))
        return {"type": "result", "data": {"started": tid}}

    # ── task runner background loop ──────────────────────────────────

    async def _task_loop(self):
        """Background loop: queued tasks, session pruning, scheduled tasks."""
        while True:
            try:
                await asyncio.sleep(TASK_POLL_INTERVAL)
                now = time.time()

                # Auto-prune old sessions periodically
                if now - self._last_prune > SESSION_PRUNE_INTERVAL:
                    self._last_prune = now
                    for db in self.dbs.values():
                        try:
                            n = db.prune_sessions(SESSION_MAX_AGE_DAYS)
                            if n:
                                log.info("Pruned %d stale sessions", n)
                        except Exception:
                            pass

                # Check scheduled tasks (every 60s)
                if now - self._last_schedule_check > 60:
                    self._last_schedule_check = now
                    self._check_schedules()

                # Pick up pending tasks (sorted by priority) and approved tasks awaiting run
                if len(self._running_tasks) >= MAX_CONCURRENT_TASKS:
                    continue
                for agent_dir in sorted(DB_DIR.iterdir()) if DB_DIR.exists() else []:
                    if not agent_dir.is_dir():
                        continue
                    db = self._get_db(agent_dir.name)
                    pending = db.list_tasks(agent_dir.name, status="pending")
                    approved = db.list_tasks(agent_dir.name, status="approved")
                    runnable = (
                        [t for t in pending if not t.get("approval_required")] + approved
                    )
                    for task in runnable:
                        if len(self._running_tasks) >= MAX_CONCURRENT_TASKS:
                            break
                        if task["id"] not in self._running_tasks:
                            coro = self._execute_task(agent_dir.name, task)
                            self._running_tasks[task["id"]] = (
                                asyncio.ensure_future(coro)
                            )
            except asyncio.CancelledError:
                break
            except Exception:
                log.exception("Task loop error")

    def _check_schedules(self):
        """Simple cron-like scheduler: checks if any schedule is due."""
        for db in self.dbs.values():
            try:
                for sched in db.list_schedules():
                    if not sched.get("enabled"):
                        continue
                    if self._schedule_is_due(sched):
                        agent = sched["agent"]
                        task = db.create_task(agent, sched["description"])
                        db.update_schedule(sched["id"], last_run=time.strftime("%Y-%m-%dT%H:%M:%S"))
                        log.info("Schedule %s triggered task %s", sched["id"], task["id"])
            except Exception:
                log.debug("Schedule check error", exc_info=True)

    @staticmethod
    def _schedule_is_due(sched) -> bool:
        """Check if a schedule is due based on its cron expression.
        Supports: @hourly, @daily, @weekly, or 'every Xm/Xh' shorthand."""
        cron = sched.get("cron", "").strip().lower()
        last = sched.get("last_run") or ""
        now = time.time()

        if last:
            try:
                last_ts = time.mktime(time.strptime(last, "%Y-%m-%dT%H:%M:%S"))
            except ValueError:
                last_ts = 0
        else:
            last_ts = 0

        elapsed = now - last_ts
        if cron == "@hourly":
            return elapsed >= 3600
        if cron == "@daily":
            return elapsed >= 86400
        if cron == "@weekly":
            return elapsed >= 604800
        if cron.startswith("every "):
            val = cron[6:].strip()
            if val.endswith("m"):
                return elapsed >= int(val[:-1]) * 60
            if val.endswith("h"):
                return elapsed >= int(val[:-1]) * 3600
        return False

    async def _execute_task(self, agent_name, task):
        """Run a single task through the agent conversation loop with cost tracking."""
        tid = task["id"]
        db = self._get_db(agent_name)
        log.info("Task %s starting: %s", tid, task["description"][:60])
        db.update_task(tid, "running")
        start_ms = int(time.time() * 1000)

        agent_cfg = db.get_agent(agent_name) or {
            "model": DEFAULT_MODEL,
            "system_prompt": DEFAULT_SYSTEM_PROMPT,
            "context": "",
        }
        messages = []
        full_output = []
        total_in = total_out = 0

        try:
            async for event in runtime.process_message(
                task["description"], agent_cfg, messages, db, agent_name
            ):
                etype = event.get("type", "")
                if etype == "text":
                    full_output.append(event.get("content", ""))
                elif etype == "error":
                    full_output.append(f"ERROR: {event.get('message', '')}")
                elif etype == "done":
                    total_in = event.get("input_tokens", 0)
                    total_out = event.get("output_tokens", 0)

            duration_ms = int(time.time() * 1000) - start_ms
            result_text = "\n".join(full_output) or "(no output)"
            model = agent_cfg.get("model", DEFAULT_MODEL)
            from .config import MODEL_COSTS
            costs = MODEL_COSTS.get(model, (0, 0))
            usd = (total_in * costs[0] + total_out * costs[1]) / 1_000_000

            final_status = "review" if task.get("approval_required") else "completed"
            db.update_task(
                tid, final_status,
                result=result_text[:50000],
                cost={
                    "tokens_in": total_in,
                    "tokens_out": total_out,
                    "usd": round(usd, 6),
                    "duration_ms": duration_ms,
                },
            )
            self._tasks_completed += 1
            log.info("Task %s %s (%.4f USD, %dms)",
                     tid, final_status, usd, duration_ms)
            self._notify("KmacAgent Task Done", f"Task {tid}: {task['description'][:60]}")
        except asyncio.CancelledError:
            db.update_task(tid, "cancelled", result="Cancelled by user")
            log.info("Task %s cancelled", tid)
        except Exception as exc:
            log.exception("Task %s failed", tid)
            db.update_task(tid, "failed", result=str(exc)[:5000])
        finally:
            self._running_tasks.pop(tid, None)

    def _task_result(self, agent_name, req):
        tid = req.get("task_id", "")
        if not tid:
            return {"type": "error", "message": "No task ID"}
        db = self._get_db(agent_name)
        task = db.get_task(tid)
        if not task:
            return {"type": "error", "message": f"Task {tid} not found"}
        subtasks = db.get_subtasks(tid)
        task["subtasks"] = subtasks
        return {"type": "result", "data": {"task": task}}

    # ── agent update ─────────────────────────────────────────────────

    def _agent_update(self, agent_name, req):
        db = self._get_db(agent_name)
        if not db.get_agent(agent_name):
            return {"type": "error", "message": f"Agent '{agent_name}' not found"}
        kwargs = {}
        if "model" in req:
            kwargs["model"] = MODEL_SHORTCUTS.get(req["model"], req["model"])
        if "system_prompt" in req:
            kwargs["system_prompt"] = req["system_prompt"]
        if "context" in req:
            kwargs["context"] = req["context"]
        if not kwargs:
            return {"type": "error", "message": "Nothing to update"}
        db.update_agent(agent_name, **kwargs)
        return {"type": "result", "data": {"agent": db.get_agent(agent_name)}}

    # ── export / import ──────────────────────────────────────────────

    def _export(self, agent_name):
        db = self._get_db(agent_name)
        data = db.export_data()
        export_path = AGENT_HOME / f"export-{agent_name}-{int(time.time())}.json"
        export_path.write_text(json.dumps(data, indent=2))
        return {"type": "result", "data": {
            "exported": str(export_path),
            "agents": len(data["agents"]),
            "memories": len(data["memories"]),
        }}

    def _import(self, agent_name, req):
        path = req.get("path", "")
        if not path:
            return {"type": "error", "message": "No import file path"}
        try:
            with open(path) as f:
                data = json.load(f)
        except Exception as e:
            return {"type": "error", "message": f"Cannot read file: {e}"}
        db = self._get_db(agent_name)
        result = db.import_data(data)
        return {"type": "result", "data": {"imported": result}}

    # ── session pruning ──────────────────────────────────────────────

    def _prune(self, agent_name):
        db = self._get_db(agent_name)
        count = db.prune_sessions(SESSION_MAX_AGE_DAYS)
        return {"type": "result", "data": {"pruned_sessions": count}}

    # ── token usage ──────────────────────────────────────────────────

    def _token_usage(self, agent_name):
        db = self._get_db(agent_name)
        usage = db.get_token_usage(agent_name)
        return {"type": "result", "data": {"usage": usage}}

    # ── schedules ────────────────────────────────────────────────────

    def _schedule_create(self, agent_name, req):
        desc = req.get("description", "")
        cron = req.get("cron", "")
        if not desc or not cron:
            return {"type": "error", "message": "Need description and cron expression"}
        sched = self._get_db(agent_name).create_schedule(agent_name, desc, cron)
        return {"type": "result", "data": {"schedule": sched}}

    def _schedule_list(self, agent_name):
        return {
            "type": "result",
            "data": {"schedules": self._get_db(agent_name).list_schedules(agent_name)},
        }

    def _schedule_delete(self, req):
        sid = req.get("schedule_id", "")
        agent = req.get("agent", "default")
        if not sid:
            return {"type": "error", "message": "No schedule ID"}
        self._get_db(agent).delete_schedule(sid)
        return {"type": "result", "data": {"deleted": sid}}

    # ── session forking ───────────────────────────────────────────────

    def _session_fork(self, agent_name, req):
        sid = req.get("session_id", "")
        if not sid:
            return {"type": "error", "message": "No session ID to fork"}
        db = self._get_db(agent_name)
        sess = db.get_session(sid)
        if not sess:
            return {"type": "error", "message": f"Session {sid} not found"}
        messages = json.loads(sess.get("messages", "[]"))
        new_sess = db.create_session(agent_name)
        db.update_session(new_sess["id"], messages)
        return {"type": "result", "data": {
            "forked": new_sess["id"],
            "from": sid,
            "messages": len(messages),
        }}

    # ── plugins / MCP / watches ──────────────────────────────────────

    def _plugins_list(self):
        plugins = [{"name": p["name"], "description": p.get("description", "")}
                    for p in self._plugins]
        mcp_tools = self._mcp.get_tool_schemas()
        return {"type": "result", "data": {
            "plugins": plugins,
            "mcp_tools": [{"name": t["name"], "description": t.get("description", "")}
                          for t in mcp_tools],
        }}

    def _mcp_status(self):
        return {"type": "result", "data": self._mcp.stats()}

    def _watches_list(self):
        watches = []
        if self._watcher:
            watches = self._watcher._watches
        return {"type": "result", "data": {"watches": watches}}

    # ── workflows ────────────────────────────────────────────────────

    def _workflows_list(self):
        wfs = workflows_mod.list_workflows()
        return {"type": "result", "data": {"workflows": wfs}}

    async def _workflow_run(self, agent_name, req):
        wf_id = req.get("workflow_id", "")
        if not wf_id:
            yield {"type": "error", "message": "No workflow ID"}
            return

        variables = req.get("variables", {})

        async def tool_runner(name, inp):
            from . import tools, tools_extended
            if name in {t["name"] for t in tools_extended.EXTENDED_TOOLS}:
                api_key = runtime.get_api_key()
                return await tools_extended.execute(name, inp, api_key)
            return await tools.execute(name, inp)

        db = self._get_db(agent_name)
        agent_cfg = db.get_agent(agent_name) or {
            "model": DEFAULT_MODEL,
            "system_prompt": DEFAULT_SYSTEM_PROMPT,
            "context": "",
        }

        async def agent_runner(prompt):
            messages = []
            output_parts = []
            async for event in runtime.process_message(
                prompt, agent_cfg, messages, db, agent_name
            ):
                etype = event.get("type", "")
                if etype == "text":
                    output_parts.append(event.get("content", ""))
                elif etype == "error":
                    output_parts.append(f"ERROR: {event.get('message', '')}")
            return "\n".join(output_parts) or "(no response)"

        yield {"type": "status", "text": f"Running workflow: {wf_id}"}

        result = await workflows_mod.execute_workflow(
            wf_id, variables=variables,
            tool_runner=tool_runner, agent_runner=agent_runner,
        )

        for log_entry in result.get("log", []):
            yield {"type": "status", "text": log_entry}

        for step_id, step_result in result.get("results", {}).items():
            if step_result and len(step_result) > 10:
                yield {"type": "text", "content": f"\n**[{step_id}]**\n{step_result[:5000]}"}

        yield {"type": "text", "content": f"\nWorkflow '{wf_id}' {result.get('status', 'done')}"}

    # ── skills ───────────────────────────────────────────────────────

    def _skills_list(self, agent_name):
        skills = list_skills_info(agent_name)
        return {"type": "result", "data": {"skills": skills}}

    # ── tool profiles ────────────────────────────────────────────────

    def _profiles_list(self):
        profiles = []
        for name in get_profile_names():
            p = PROFILES[name]
            if p is None:
                tools_list = ["(all)"]
            elif len(p) == 0:
                tools_list = ["(none)"]
            else:
                tools_list = sorted(p)
            profiles.append({
                "name": name,
                "tools": tools_list,
            })
        return {"type": "result", "data": {
            "profiles": profiles,
            "groups": get_group_names(),
        }}

    # ── notifications ────────────────────────────────────────────────

    def _notify(self, title: str, body: str):
        """Send a notification via macOS notification center and/or Telegram."""
        import subprocess as sp
        try:
            sp.run([
                "osascript", "-e",
                f'display notification "{body}" with title "{title}"'
            ], timeout=5, capture_output=True)
        except Exception:
            pass
        self._notify_telegram(f"*{title}*\n{body}")

    def _notify_telegram(self, text: str):
        """Send notification via Pilot's Telegram if configured."""
        try:
            config_path = Path.home() / ".config" / "kmac-pilot" / "config.json"
            if not config_path.exists():
                return
            with open(config_path) as f:
                cfg = json.load(f)
            token = cfg.get("telegram_token", "")
            chat_id = cfg.get("chat_id", "")
            if not token or not chat_id:
                return
            import urllib.request
            body = json.dumps({
                "chat_id": chat_id, "text": text, "parse_mode": "Markdown",
            }).encode()
            req = urllib.request.Request(
                f"https://api.telegram.org/bot{token}/sendMessage",
                data=body,
                headers={"Content-Type": "application/json"},
            )
            urllib.request.urlopen(req, timeout=10)
        except Exception:
            pass

    # ── lifecycle ────────────────────────────────────────────────────

    async def start(self):
        AGENT_HOME.mkdir(parents=True, exist_ok=True)
        os.chmod(str(AGENT_HOME), 0o700)

        if SOCKET_PATH.exists():
            SOCKET_PATH.unlink()

        # Load plugins
        self._plugins = plugins_mod.load_all()
        runtime.register_plugins(self._plugins)
        if self._plugins:
            log.info("Loaded %d plugins", len(self._plugins))

        # Initialize MCP servers
        try:
            await self._mcp.load_config()
            runtime.register_mcp(self._mcp)
            if self._mcp.servers:
                log.info("MCP: %d servers, %d tools",
                         len(self._mcp.servers),
                         sum(len(s.tools) for s in self._mcp.servers.values()))
        except Exception:
            log.warning("MCP init failed", exc_info=True)

        # Start file watcher
        def _watch_callback(agent, desc):
            db = self._get_db(agent)
            db.create_task(agent, desc)
        self._watcher = FileWatcher(_watch_callback)
        await self._watcher.start()

        # Start web dashboard
        self._web_server = start_web_server(self)

        self._server = await asyncio.start_unix_server(
            self.handle_connection, path=str(SOCKET_PATH),
        )
        os.chmod(str(SOCKET_PATH), 0o600)
        PID_FILE.write_text(str(os.getpid()))

        self._task_runner = asyncio.ensure_future(self._task_loop())
        log.info("KmacAgent daemon started (PID: %d, socket: %s, task runner: on)",
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
        if self._task_runner:
            self._task_runner.cancel()
            try:
                await self._task_runner
            except asyncio.CancelledError:
                pass
        for atask in list(self._running_tasks.values()):
            atask.cancel()
        if self._watcher:
            await self._watcher.stop()
        await self._mcp.stop_all()
        if self._web_server:
            self._web_server.shutdown()
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
        handlers=[logging.FileHandler(str(LOG_FILE))],
    )
    daemon = AgentDaemon()
    asyncio.run(daemon.start())
