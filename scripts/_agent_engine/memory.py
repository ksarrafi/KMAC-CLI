"""SQLite memory layer — agents, sessions, persistent knowledge, tasks."""

import json
import sqlite3
import threading
import time
import uuid
from pathlib import Path

_SCHEMA = """\
CREATE TABLE IF NOT EXISTS agents (
    name        TEXT PRIMARY KEY,
    model       TEXT NOT NULL DEFAULT 'claude-sonnet-4-6',
    system_prompt TEXT NOT NULL DEFAULT '',
    context     TEXT NOT NULL DEFAULT '',
    config      TEXT NOT NULL DEFAULT '{}',
    created     TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS sessions (
    id          TEXT PRIMARY KEY,
    agent       TEXT NOT NULL DEFAULT 'default',
    messages    TEXT NOT NULL DEFAULT '[]',
    summary     TEXT NOT NULL DEFAULT '',
    created     TEXT NOT NULL,
    updated     TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS memories (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    agent       TEXT NOT NULL DEFAULT 'default',
    content     TEXT NOT NULL,
    category    TEXT NOT NULL DEFAULT 'fact',
    source      TEXT NOT NULL DEFAULT 'manual',
    created     TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS tasks (
    id              TEXT PRIMARY KEY,
    agent           TEXT NOT NULL DEFAULT 'default',
    description     TEXT NOT NULL,
    status          TEXT NOT NULL DEFAULT 'pending',
    priority        TEXT NOT NULL DEFAULT 'normal',
    result          TEXT,
    cost_tokens_in  INTEGER NOT NULL DEFAULT 0,
    cost_tokens_out INTEGER NOT NULL DEFAULT 0,
    cost_usd        REAL NOT NULL DEFAULT 0.0,
    cost_duration_ms INTEGER NOT NULL DEFAULT 0,
    approval_required INTEGER NOT NULL DEFAULT 0,
    approved_by     TEXT,
    tags            TEXT NOT NULL DEFAULT '[]',
    parent_task_id  TEXT,
    created         TEXT NOT NULL,
    started         TEXT,
    completed       TEXT
);

CREATE TABLE IF NOT EXISTS token_usage (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    agent       TEXT NOT NULL DEFAULT 'default',
    model       TEXT NOT NULL,
    input_tokens  INTEGER NOT NULL DEFAULT 0,
    output_tokens INTEGER NOT NULL DEFAULT 0,
    created     TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS schedules (
    id          TEXT PRIMARY KEY,
    agent       TEXT NOT NULL DEFAULT 'default',
    description TEXT NOT NULL,
    cron        TEXT NOT NULL,
    enabled     INTEGER NOT NULL DEFAULT 1,
    last_run    TEXT,
    created     TEXT NOT NULL
);
"""


def _now():
    return time.strftime("%Y-%m-%dT%H:%M:%S")


class MemoryDB:
    """Per-agent SQLite database for sessions, memories, and tasks."""

    def __init__(self, db_path: Path):
        db_path.parent.mkdir(parents=True, exist_ok=True)
        self._lock = threading.RLock()
        with self._lock:
            self.conn = sqlite3.connect(str(db_path), check_same_thread=False)
            self.conn.row_factory = sqlite3.Row
            self.conn.executescript(_SCHEMA)
            self._ensure_fts()
            self.conn.commit()

    def _ensure_fts(self):
        try:
            self.conn.execute(
                "CREATE VIRTUAL TABLE IF NOT EXISTS memories_fts "
                "USING fts5(content, category, source, "
                "content=memories, content_rowid=id)"
            )
            self.conn.commit()
        except sqlite3.OperationalError:
            pass  # FTS5 unavailable

    def close(self):
        with self._lock:
            self.conn.close()

    # ── Agents ───────────────────────────────────────────────────────

    def get_agent(self, name: str):
        with self._lock:
            row = self.conn.execute(
                "SELECT * FROM agents WHERE name = ?", (name,)
            ).fetchone()
            return dict(row) if row else None

    def create_agent(self, name, model="claude-sonnet-4-6",
                     system_prompt="", context="", config=None):
        with self._lock:
            self.conn.execute(
                "INSERT OR REPLACE INTO agents "
                "(name, model, system_prompt, context, config, created) "
                "VALUES (?, ?, ?, ?, ?, ?)",
                (name, model, system_prompt, context,
                 json.dumps(config or {}), _now()),
            )
            self.conn.commit()
            row = self.conn.execute(
                "SELECT * FROM agents WHERE name = ?", (name,)
            ).fetchone()
            return dict(row) if row else None

    def update_agent(self, name, **kwargs):
        with self._lock:
            allowed = {"model", "system_prompt", "context", "config"}
            parts, vals = [], []
            for k, v in kwargs.items():
                if k in allowed:
                    parts.append(f"{k} = ?")
                    vals.append(json.dumps(v) if k == "config" else v)
            if parts:
                vals.append(name)
                self.conn.execute(
                    f"UPDATE agents SET {', '.join(parts)} WHERE name = ?", vals
                )
                self.conn.commit()

    def list_agents(self):
        with self._lock:
            rows = self.conn.execute(
                "SELECT * FROM agents ORDER BY created"
            ).fetchall()
            return [dict(r) for r in rows]

    def delete_agent(self, name):
        with self._lock:
            for table in ("agents", "sessions", "memories", "tasks"):
                col = "name" if table == "agents" else "agent"
                self.conn.execute(f"DELETE FROM {table} WHERE {col} = ?", (name,))
            self.conn.commit()

    # ── Sessions ─────────────────────────────────────────────────────

    def get_session(self, session_id):
        with self._lock:
            row = self.conn.execute(
                "SELECT * FROM sessions WHERE id = ?", (session_id,)
            ).fetchone()
            return dict(row) if row else None

    def create_session(self, agent="default", session_id=None):
        with self._lock:
            sid = session_id or uuid.uuid4().hex[:12]
            now = _now()
            self.conn.execute(
                "INSERT INTO sessions (id, agent, messages, created, updated) "
                "VALUES (?, ?, '[]', ?, ?)",
                (sid, agent, now, now),
            )
            self.conn.commit()
            row = self.conn.execute(
                "SELECT * FROM sessions WHERE id = ?", (sid,)
            ).fetchone()
            return dict(row) if row else None

    def update_session(self, session_id, messages):
        with self._lock:
            self.conn.execute(
                "UPDATE sessions SET messages = ?, updated = ? WHERE id = ?",
                (json.dumps(messages), _now(), session_id),
            )
            self.conn.commit()

    def list_sessions(self, agent=None, limit=50):
        with self._lock:
            if agent:
                rows = self.conn.execute(
                    "SELECT * FROM sessions WHERE agent = ? "
                    "ORDER BY updated DESC LIMIT ?", (agent, limit),
                ).fetchall()
            else:
                rows = self.conn.execute(
                    "SELECT * FROM sessions ORDER BY updated DESC LIMIT ?",
                    (limit,),
                ).fetchall()
            return [dict(r) for r in rows]

    def delete_session(self, session_id):
        with self._lock:
            self.conn.execute("DELETE FROM sessions WHERE id = ?", (session_id,))
            self.conn.commit()

    # ── Memories ─────────────────────────────────────────────────────

    def add_memory(self, agent, content, category="fact", source="manual"):
        with self._lock:
            cur = self.conn.execute(
                "INSERT INTO memories (agent, content, category, source, created) "
                "VALUES (?, ?, ?, ?, ?)",
                (agent, content, category, source, _now()),
            )
            try:
                self.conn.execute(
                    "INSERT INTO memories_fts (rowid, content, category, source) "
                    "VALUES (?, ?, ?, ?)",
                    (cur.lastrowid, content, category, source),
                )
            except sqlite3.OperationalError:
                pass
            self.conn.commit()
            return cur.lastrowid

    def search_memories(self, agent, query, limit=10):
        with self._lock:
            try:
                rows = self.conn.execute(
                    "SELECT m.* FROM memories m "
                    "JOIN memories_fts f ON m.id = f.rowid "
                    "WHERE m.agent = ? AND memories_fts MATCH ? "
                    "ORDER BY rank LIMIT ?",
                    (agent, query, limit),
                ).fetchall()
                if rows:
                    return [dict(r) for r in rows]
            except sqlite3.OperationalError:
                pass
            rows = self.conn.execute(
                "SELECT * FROM memories WHERE agent = ? AND content LIKE ? "
                "ORDER BY created DESC LIMIT ?",
                (agent, f"%{query}%", limit),
            ).fetchall()
            return [dict(r) for r in rows]

    def list_memories(self, agent, limit=50):
        with self._lock:
            rows = self.conn.execute(
                "SELECT * FROM memories WHERE agent = ? "
                "ORDER BY created DESC LIMIT ?", (agent, limit),
            ).fetchall()
            return [dict(r) for r in rows]

    def delete_memory(self, memory_id):
        with self._lock:
            self.conn.execute("DELETE FROM memories WHERE id = ?", (memory_id,))
            try:
                self.conn.execute(
                    "DELETE FROM memories_fts WHERE rowid = ?", (memory_id,)
                )
            except sqlite3.OperationalError:
                pass
            self.conn.commit()

    # ── Tasks ────────────────────────────────────────────────────────

    VALID_PRIORITIES = ("low", "normal", "high", "urgent")
    VALID_STATUSES = (
        "pending", "assigned", "queued", "running",
        "review", "approved", "rejected",
        "completed", "done", "failed", "cancelled",
    )
    _PRIORITY_RANK = {"urgent": 0, "high": 1, "normal": 2, "low": 3}

    def create_task(self, agent, description, priority="normal",
                    tags=None, parent_task_id=None, approval_required=False):
        with self._lock:
            tid = uuid.uuid4().hex[:8]
            if priority not in self.VALID_PRIORITIES:
                priority = "normal"
            self.conn.execute(
                "INSERT INTO tasks (id, agent, description, status, priority, "
                "tags, parent_task_id, approval_required, created) "
                "VALUES (?, ?, ?, 'pending', ?, ?, ?, ?, ?)",
                (tid, agent, description, priority,
                 json.dumps(tags or []), parent_task_id,
                 1 if approval_required else 0, _now()),
            )
            self.conn.commit()
            return {"id": tid, "agent": agent, "description": description,
                    "status": "pending", "priority": priority}

    def update_task(self, task_id, status, result=None, cost=None):
        with self._lock:
            now = _now()
            if status not in self.VALID_STATUSES:
                return
            parts = ["status = ?"]
            vals = [status]
            if status == "running":
                parts.append("started = ?")
                vals.append(now)
            elif status in ("completed", "done", "failed", "cancelled", "rejected"):
                parts.append("completed = ?")
                vals.append(now)
                if result is not None:
                    parts.append("result = ?")
                    vals.append(result)
            elif result is not None:
                parts.append("result = ?")
                vals.append(result)
            if cost:
                for col, key in [("cost_tokens_in", "tokens_in"),
                                  ("cost_tokens_out", "tokens_out"),
                                  ("cost_usd", "usd"),
                                  ("cost_duration_ms", "duration_ms")]:
                    if key in cost:
                        parts.append(f"{col} = ?")
                        vals.append(cost[key])
            vals.append(task_id)
            self.conn.execute(
                f"UPDATE tasks SET {', '.join(parts)} WHERE id = ?", vals
            )
            self.conn.commit()

    def approve_task(self, task_id, approved_by="user"):
        with self._lock:
            self.conn.execute(
                "UPDATE tasks SET status='approved', approved_by=? WHERE id=?",
                (approved_by, task_id),
            )
            self.conn.commit()

    def reject_task(self, task_id):
        with self._lock:
            self.conn.execute(
                "UPDATE tasks SET status='rejected', completed=? WHERE id=?",
                (_now(), task_id),
            )
            self.conn.commit()

    def get_task(self, task_id):
        with self._lock:
            row = self.conn.execute(
                "SELECT * FROM tasks WHERE id = ?", (task_id,)
            ).fetchone()
            if not row:
                return None
            t = dict(row)
            try:
                t["tags"] = json.loads(t.get("tags", "[]"))
            except (json.JSONDecodeError, TypeError):
                t["tags"] = []
            return t

    def get_subtasks(self, parent_id):
        with self._lock:
            rows = self.conn.execute(
                "SELECT * FROM tasks WHERE parent_task_id = ? ORDER BY created",
                (parent_id,),
            ).fetchall()
            return [dict(r) for r in rows]

    def list_tasks(self, agent=None, status=None, tag=None):
        with self._lock:
            q, p = "SELECT * FROM tasks WHERE 1=1", []
            if agent:
                q += " AND agent = ?"; p.append(agent)
            if status:
                q += " AND status = ?"; p.append(status)
            q += " ORDER BY created DESC LIMIT 50"
            rows = self.conn.execute(q, p).fetchall()
            tasks = []
            for r in rows:
                t = dict(r)
                try:
                    t["tags"] = json.loads(t.get("tags", "[]"))
                except (json.JSONDecodeError, TypeError):
                    t["tags"] = []
                if tag and tag not in t["tags"]:
                    continue
                tasks.append(t)
            tasks.sort(
                key=lambda t: self._PRIORITY_RANK.get(t.get("priority", "normal"), 2)
            )
            return tasks

    def task_stats(self, agent=None):
        with self._lock:
            where = "WHERE agent = ?" if agent else ""
            params = (agent,) if agent else ()

            def _cnt(status):
                r = self.conn.execute(
                    f"SELECT COUNT(*) FROM tasks {where}"
                    f"{' AND' if where else ' WHERE'} status = ?",
                    (*params, status),
                ).fetchone()
                return r[0]

            total_cost = self.conn.execute(
                f"SELECT COALESCE(SUM(cost_usd), 0) FROM tasks {where}", params
            ).fetchone()[0]
            return {
                "total": self.conn.execute(
                    f"SELECT COUNT(*) FROM tasks {where}", params
                ).fetchone()[0],
                "pending": _cnt("pending"),
                "running": _cnt("running"),
                "done": _cnt("completed") + _cnt("done"),
                "failed": _cnt("failed"),
                "review": _cnt("review"),
                "total_cost_usd": round(total_cost, 4),
            }

    # ── Token Usage ──────────────────────────────────────────────────

    def log_tokens(self, agent, model, input_tokens, output_tokens):
        with self._lock:
            self.conn.execute(
                "INSERT INTO token_usage (agent, model, input_tokens, output_tokens, created) "
                "VALUES (?, ?, ?, ?, ?)",
                (agent, model, input_tokens, output_tokens, _now()),
            )
            self.conn.commit()

    def get_token_usage(self, agent=None, days=30):
        with self._lock:
            cutoff = time.strftime(
                "%Y-%m-%dT%H:%M:%S",
                time.localtime(time.time() - days * 86400),
            )
            if agent:
                rows = self.conn.execute(
                    "SELECT model, SUM(input_tokens) as inp, SUM(output_tokens) as out, "
                    "COUNT(*) as calls FROM token_usage "
                    "WHERE agent = ? AND created > ? GROUP BY model",
                    (agent, cutoff),
                ).fetchall()
            else:
                rows = self.conn.execute(
                    "SELECT model, SUM(input_tokens) as inp, SUM(output_tokens) as out, "
                    "COUNT(*) as calls FROM token_usage "
                    "WHERE created > ? GROUP BY model",
                    (cutoff,),
                ).fetchall()
            return [dict(r) for r in rows]

    # ── Schedules ───────────────────────────────────────────────────

    def create_schedule(self, agent, description, cron):
        with self._lock:
            sid = uuid.uuid4().hex[:8]
            self.conn.execute(
                "INSERT INTO schedules (id, agent, description, cron, created) "
                "VALUES (?, ?, ?, ?, ?)",
                (sid, agent, description, cron, _now()),
            )
            self.conn.commit()
            return {"id": sid, "agent": agent, "description": description,
                    "cron": cron, "enabled": 1}

    def list_schedules(self, agent=None):
        with self._lock:
            if agent:
                rows = self.conn.execute(
                    "SELECT * FROM schedules WHERE agent = ? ORDER BY created",
                    (agent,),
                ).fetchall()
            else:
                rows = self.conn.execute(
                    "SELECT * FROM schedules ORDER BY created"
                ).fetchall()
            return [dict(r) for r in rows]

    def update_schedule(self, schedule_id, **kwargs):
        with self._lock:
            allowed = {"enabled", "last_run", "cron", "description"}
            parts, vals = [], []
            for k, v in kwargs.items():
                if k in allowed:
                    parts.append(f"{k} = ?")
                    vals.append(v)
            if parts:
                vals.append(schedule_id)
                self.conn.execute(
                    f"UPDATE schedules SET {', '.join(parts)} WHERE id = ?", vals
                )
                self.conn.commit()

    def delete_schedule(self, schedule_id):
        with self._lock:
            self.conn.execute("DELETE FROM schedules WHERE id = ?", (schedule_id,))
            self.conn.commit()

    # ── Session Pruning ─────────────────────────────────────────────

    def prune_sessions(self, max_age_days=14):
        with self._lock:
            cutoff = time.strftime(
                "%Y-%m-%dT%H:%M:%S",
                time.localtime(time.time() - max_age_days * 86400),
            )
            cur = self.conn.execute(
                "DELETE FROM sessions WHERE updated < ?", (cutoff,)
            )
            self.conn.commit()
            return cur.rowcount

    # ── Export / Import ─────────────────────────────────────────────

    def export_data(self):
        with self._lock:
            data = {
                "agents": [dict(r) for r in self.conn.execute(
                    "SELECT * FROM agents").fetchall()],
                "memories": [dict(r) for r in self.conn.execute(
                    "SELECT * FROM memories").fetchall()],
                "sessions": [],
                "schedules": [dict(r) for r in self.conn.execute(
                    "SELECT * FROM schedules").fetchall()],
            }
            for s in self.conn.execute("SELECT * FROM sessions").fetchall():
                sd = dict(s)
                sd.pop("messages", None)
                data["sessions"].append(sd)
            return data

    def import_data(self, data):
        with self._lock:
            imported = {"agents": 0, "memories": 0, "schedules": 0}
            for a in data.get("agents", []):
                try:
                    self.create_agent(
                        a["name"], a.get("model", "claude-sonnet-4-6"),
                        a.get("system_prompt", ""), a.get("context", ""),
                    )
                    imported["agents"] += 1
                except Exception:
                    pass
            for m in data.get("memories", []):
                try:
                    self.add_memory(
                        m.get("agent", "default"), m["content"],
                        m.get("category", "fact"), m.get("source", "import"),
                    )
                    imported["memories"] += 1
                except Exception:
                    pass
            for s in data.get("schedules", []):
                try:
                    self.create_schedule(
                        s.get("agent", "default"),
                        s["description"], s["cron"],
                    )
                    imported["schedules"] += 1
                except Exception:
                    pass
            return imported

    # ── Stats ────────────────────────────────────────────────────────

    # ── Schema migration ────────────────────────────────────────────

    def migrate(self):
        """Add columns from newer schema versions if missing."""
        with self._lock:
            existing = {
                row[1] for row in
                self.conn.execute("PRAGMA table_info(tasks)").fetchall()
            }
            migrations = [
                ("priority", "TEXT NOT NULL DEFAULT 'normal'"),
                ("cost_tokens_in", "INTEGER NOT NULL DEFAULT 0"),
                ("cost_tokens_out", "INTEGER NOT NULL DEFAULT 0"),
                ("cost_usd", "REAL NOT NULL DEFAULT 0.0"),
                ("cost_duration_ms", "INTEGER NOT NULL DEFAULT 0"),
                ("approval_required", "INTEGER NOT NULL DEFAULT 0"),
                ("approved_by", "TEXT"),
                ("tags", "TEXT NOT NULL DEFAULT '[]'"),
                ("parent_task_id", "TEXT"),
            ]
            for col, typedef in migrations:
                if col not in existing:
                    try:
                        self.conn.execute(
                            f"ALTER TABLE tasks ADD COLUMN {col} {typedef}"
                        )
                    except sqlite3.OperationalError:
                        pass
            # Rename old 'queued' status to 'pending' for consistency
            self.conn.execute(
                "UPDATE tasks SET status='pending' WHERE status='queued'"
            )
            self.conn.commit()

    # ── Stats ────────────────────────────────────────────────────────

    def stats(self):
        with self._lock:
            def _count(sql):
                return self.conn.execute(sql).fetchone()[0]
            total_input = 0
            total_output = 0
            try:
                row = self.conn.execute(
                    "SELECT COALESCE(SUM(input_tokens),0), "
                    "COALESCE(SUM(output_tokens),0) FROM token_usage"
                ).fetchone()
                total_input, total_output = row[0], row[1]
            except Exception:
                pass
            task_cost = 0.0
            try:
                task_cost = self.conn.execute(
                    "SELECT COALESCE(SUM(cost_usd),0) FROM tasks"
                ).fetchone()[0]
            except Exception:
                pass
            return {
                "agents": _count("SELECT COUNT(*) FROM agents"),
                "sessions": _count("SELECT COUNT(*) FROM sessions"),
                "memories": _count("SELECT COUNT(*) FROM memories"),
                "active_tasks": _count(
                    "SELECT COUNT(*) FROM tasks "
                    "WHERE status IN ('pending','assigned','running')"
                ),
                "total_input_tokens": total_input,
                "total_output_tokens": total_output,
                "total_task_cost_usd": round(task_cost, 4),
            }
