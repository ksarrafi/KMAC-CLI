"""Integration tests — start the daemon and exercise the socket protocol."""

import asyncio
import json
import os
import socket
import sys
import tempfile
import time
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent.parent))

from _agent_engine.config import AGENT_HOME, SOCKET_PATH


def _daemon_running() -> bool:
    if not SOCKET_PATH.exists():
        return False
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.connect(str(SOCKET_PATH))
        s.sendall(json.dumps({"action": "ping"}).encode() + b"\n")
        data = s.recv(4096)
        s.close()
        return b"ok" in data
    except Exception:
        return False


def _send(action: str, **kwargs) -> dict:
    """Send a request to the daemon and return the result data."""
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.connect(str(SOCKET_PATH))
    req = {"action": action, **kwargs}
    s.sendall(json.dumps(req).encode() + b"\n")

    buf = b""
    events = []
    while True:
        chunk = s.recv(8192)
        if not chunk:
            break
        buf += chunk
        while b"\n" in buf:
            line, buf = buf.split(b"\n", 1)
            if line:
                events.append(json.loads(line))

    s.close()

    for e in events:
        if e.get("type") == "result":
            return e.get("data", {})
        if e.get("type") == "error":
            return {"_error": e.get("message", "")}
    return {"_events": events}


@unittest.skipUnless(_daemon_running(), "Agent daemon not running — start with: kmac agent start")
class TestDaemonProtocol(unittest.TestCase):
    """These tests require a running daemon. Start it first."""

    def test_ping(self):
        data = _send("ping")
        self.assertTrue(data.get("ok"))

    def test_status(self):
        data = _send("status")
        self.assertTrue(data.get("running"))
        self.assertIn("pid", data)
        self.assertIn("uptime_human", data)

    def test_agents_list(self):
        data = _send("agents-list")
        self.assertIn("agents", data)
        self.assertIsInstance(data["agents"], list)

    def test_sessions_list(self):
        data = _send("sessions-list", agent="default")
        self.assertIn("sessions", data)

    def test_memory_lifecycle(self):
        add_data = _send("memory-add", agent="default", content="integration-test-fact-xyz")
        self.assertIn("id", add_data)
        mid = add_data["id"]

        search_data = _send("memory-search", agent="default", query="integration-test-fact-xyz")
        self.assertIn("memories", search_data)
        found = any("integration-test-fact-xyz" in m.get("content", "")
                     for m in search_data["memories"])
        self.assertTrue(found)

        _send("memory-delete", agent="default", id=str(mid))
        search_after = _send("memory-search", agent="default", query="integration-test-fact-xyz")
        not_found = not any("integration-test-fact-xyz" in m.get("content", "")
                            for m in search_after.get("memories", []))
        self.assertTrue(not_found)

    def test_task_lifecycle(self):
        create_data = _send("task-create", agent="default",
                            description="integration-test-task-noop")
        self.assertIn("task", create_data)
        tid = create_data["task"]["id"]

        cancel_data = _send("task-cancel", agent="default", task_id=tid)
        self.assertIn("cancelled", cancel_data)

    def test_token_usage(self):
        data = _send("token-usage", agent="default")
        self.assertIn("usage", data)

    def test_schedule_lifecycle(self):
        create_data = _send("schedule-create", agent="default",
                            description="test-schedule-noop", cron="@daily")
        self.assertIn("schedule", create_data)
        sid = create_data["schedule"]["id"]

        list_data = _send("schedule-list", agent="default")
        self.assertIn("schedules", list_data)
        found = any(s["id"] == sid for s in list_data["schedules"])
        self.assertTrue(found)

        _send("schedule-delete", agent="default", schedule_id=sid)
        list_after = _send("schedule-list", agent="default")
        not_found = not any(s["id"] == sid for s in list_after.get("schedules", []))
        self.assertTrue(not_found)

    def test_session_fork(self):
        sessions = _send("sessions-list", agent="default")
        if sessions.get("sessions"):
            sid = sessions["sessions"][0]["id"]
            fork_data = _send("session-fork", agent="default", session_id=sid)
            self.assertIn("forked", fork_data)

    def test_export(self):
        data = _send("export", agent="default")
        self.assertIn("exported", data)
        export_path = data["exported"]
        self.assertTrue(os.path.exists(export_path))
        os.unlink(export_path)

    def test_plugins_list(self):
        data = _send("plugins-list")
        self.assertIn("plugins", data)
        self.assertIn("mcp_tools", data)

    def test_prune(self):
        data = _send("prune", agent="default")
        self.assertIn("pruned_sessions", data)

    def test_workflows_list(self):
        data = _send("workflows-list")
        self.assertIn("workflows", data)
        self.assertIsInstance(data["workflows"], list)
        self.assertGreater(len(data["workflows"]), 0)
        names = {w["id"] for w in data["workflows"]}
        self.assertIn("lint-fix", names)
        self.assertIn("security-scan", names)

    def test_skills_list(self):
        data = _send("skills-list", agent="default")
        self.assertIn("skills", data)
        self.assertIsInstance(data["skills"], list)

    def test_profiles_list(self):
        data = _send("profiles-list")
        self.assertIn("profiles", data)
        self.assertIsInstance(data["profiles"], list)
        names = {p["name"] for p in data["profiles"]}
        self.assertIn("full", names)
        self.assertIn("safe", names)
        self.assertIn("coding", names)
        self.assertIn("groups", data)

    def test_watches_list(self):
        data = _send("watches-list")
        self.assertIn("watches", data)

    def test_mcp_status(self):
        data = _send("mcp-status")
        self.assertIsInstance(data, dict)

    def test_unknown_action(self):
        data = _send("nonexistent-action-xyz")
        self.assertIn("_error", data)


if __name__ == "__main__":
    unittest.main()
