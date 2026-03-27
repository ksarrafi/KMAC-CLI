"""SQLite memory layer — agents, sessions, persistent knowledge, tasks."""

import json
import sqlite3
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
    id          TEXT PRIMARY KEY,
    agent       TEXT NOT NULL DEFAULT 'default',
    description TEXT NOT NULL,
    status      TEXT NOT NULL DEFAULT 'queued',
    result      TEXT,
    created     TEXT NOT NULL,
    started     TEXT,
    completed   TEXT
);
"""


def _now():
    return time.strftime("%Y-%m-%dT%H:%M:%S")


class MemoryDB:
    """Per-agent SQLite database for sessions, memories, and tasks."""

    def __init__(self, db_path: Path):
        db_path.parent.mkdir(parents=True, exist_ok=True)
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
        self.conn.close()

    # ── Agents ───────────────────────────────────────────────────────

    def get_agent(self, name: str):
        row = self.conn.execute(
            "SELECT * FROM agents WHERE name = ?", (name,)
        ).fetchone()
        return dict(row) if row else None

    def create_agent(self, name, model="claude-sonnet-4-6",
                     system_prompt="", context="", config=None):
        self.conn.execute(
            "INSERT OR REPLACE INTO agents "
            "(name, model, system_prompt, context, config, created) "
            "VALUES (?, ?, ?, ?, ?, ?)",
            (name, model, system_prompt, context,
             json.dumps(config or {}), _now()),
        )
        self.conn.commit()
        return self.get_agent(name)

    def update_agent(self, name, **kwargs):
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
        rows = self.conn.execute(
            "SELECT * FROM agents ORDER BY created"
        ).fetchall()
        return [dict(r) for r in rows]

    def delete_agent(self, name):
        for table in ("agents", "sessions", "memories", "tasks"):
            col = "name" if table == "agents" else "agent"
            self.conn.execute(f"DELETE FROM {table} WHERE {col} = ?", (name,))
        self.conn.commit()

    # ── Sessions ─────────────────────────────────────────────────────

    def get_session(self, session_id):
        row = self.conn.execute(
            "SELECT * FROM sessions WHERE id = ?", (session_id,)
        ).fetchone()
        return dict(row) if row else None

    def create_session(self, agent="default", session_id=None):
        sid = session_id or uuid.uuid4().hex[:12]
        now = _now()
        self.conn.execute(
            "INSERT INTO sessions (id, agent, messages, created, updated) "
            "VALUES (?, ?, '[]', ?, ?)",
            (sid, agent, now, now),
        )
        self.conn.commit()
        return self.get_session(sid)

    def update_session(self, session_id, messages):
        self.conn.execute(
            "UPDATE sessions SET messages = ?, updated = ? WHERE id = ?",
            (json.dumps(messages), _now(), session_id),
        )
        self.conn.commit()

    def list_sessions(self, agent=None, limit=50):
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
        self.conn.execute("DELETE FROM sessions WHERE id = ?", (session_id,))
        self.conn.commit()

    # ── Memories ─────────────────────────────────────────────────────

    def add_memory(self, agent, content, category="fact", source="manual"):
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
        rows = self.conn.execute(
            "SELECT * FROM memories WHERE agent = ? "
            "ORDER BY created DESC LIMIT ?", (agent, limit),
        ).fetchall()
        return [dict(r) for r in rows]

    def delete_memory(self, memory_id):
        self.conn.execute("DELETE FROM memories WHERE id = ?", (memory_id,))
        try:
            self.conn.execute(
                "DELETE FROM memories_fts WHERE rowid = ?", (memory_id,)
            )
        except sqlite3.OperationalError:
            pass
        self.conn.commit()

    # ── Tasks ────────────────────────────────────────────────────────

    def create_task(self, agent, description):
        tid = uuid.uuid4().hex[:8]
        self.conn.execute(
            "INSERT INTO tasks (id, agent, description, status, created) "
            "VALUES (?, ?, ?, 'queued', ?)",
            (tid, agent, description, _now()),
        )
        self.conn.commit()
        return {"id": tid, "agent": agent,
                "description": description, "status": "queued"}

    def update_task(self, task_id, status, result=None):
        now = _now()
        if status == "running":
            self.conn.execute(
                "UPDATE tasks SET status=?, started=? WHERE id=?",
                (status, now, task_id),
            )
        elif status in ("completed", "failed", "cancelled"):
            self.conn.execute(
                "UPDATE tasks SET status=?, completed=?, result=? WHERE id=?",
                (status, now, result, task_id),
            )
        else:
            self.conn.execute(
                "UPDATE tasks SET status=? WHERE id=?", (status, task_id)
            )
        self.conn.commit()

    def list_tasks(self, agent=None, status=None):
        q, p = "SELECT * FROM tasks WHERE 1=1", []
        if agent:
            q += " AND agent = ?"; p.append(agent)
        if status:
            q += " AND status = ?"; p.append(status)
        q += " ORDER BY created DESC LIMIT 50"
        return [dict(r) for r in self.conn.execute(q, p).fetchall()]

    # ── Stats ────────────────────────────────────────────────────────

    def stats(self):
        def _count(sql):
            return self.conn.execute(sql).fetchone()[0]
        return {
            "agents": _count("SELECT COUNT(*) FROM agents"),
            "sessions": _count("SELECT COUNT(*) FROM sessions"),
            "memories": _count("SELECT COUNT(*) FROM memories"),
            "active_tasks": _count(
                "SELECT COUNT(*) FROM tasks "
                "WHERE status IN ('queued','running')"
            ),
        }
