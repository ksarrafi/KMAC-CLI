"""File watcher — event-driven task triggers on file changes.

Uses fswatch (macOS) or inotifywait (Linux) to monitor paths.
When a watched file changes, queues a task for the agent.

Config stored in DB schedules table with cron='@watch' and
description containing the path pattern and task template.

Watch config in: ~/.cache/kmac/agent/watches.json
Format:
{
  "watches": [
    {
      "id": "w1",
      "agent": "default",
      "paths": ["src/"],
      "pattern": "*.py",
      "task": "lint and type-check the changed Python files",
      "debounce": 5,
      "enabled": true
    }
  ]
}
"""

import asyncio
import json
import logging
import os
import time
from pathlib import Path

from .config import AGENT_HOME

log = logging.getLogger("kmac-agent")

WATCH_CONFIG = AGENT_HOME / "watches.json"


class FileWatcher:
    """Watches file paths and queues agent tasks on changes."""

    def __init__(self, task_callback):
        """task_callback(agent, description) -> creates a task."""
        self._callback = task_callback
        self._watches: list[dict] = []
        self._processes: list[asyncio.subprocess.Process] = []
        self._tasks: list[asyncio.Task] = []
        self._last_trigger: dict[str, float] = {}

    def load_config(self):
        if not WATCH_CONFIG.exists():
            return
        try:
            with open(WATCH_CONFIG) as f:
                data = json.load(f)
            self._watches = [w for w in data.get("watches", []) if w.get("enabled", True)]
            log.info("Loaded %d file watches", len(self._watches))
        except Exception:
            log.warning("Failed to load watch config", exc_info=True)

    async def start(self):
        """Start watchers for all configured paths."""
        self.load_config()
        for watch in self._watches:
            task = asyncio.ensure_future(self._run_watch(watch))
            self._tasks.append(task)

    async def _run_watch(self, watch: dict):
        """Run a single file watcher using fswatch or inotifywait."""
        paths = watch.get("paths", [])
        if not paths:
            return

        wid = watch.get("id", "unknown")
        debounce = watch.get("debounce", 5)
        agent = watch.get("agent", "default")
        task_desc = watch.get("task", "process changed files")
        pattern = watch.get("pattern", "")

        abs_paths = [os.path.abspath(p) for p in paths if os.path.exists(p)]
        if not abs_paths:
            log.warning("Watch %s: no valid paths", wid)
            return

        tool = await self._detect_tool()
        if not tool:
            log.warning("Watch %s: no fswatch or inotifywait available", wid)
            return

        try:
            if tool == "fswatch":
                cmd = ["fswatch", "-r", "--event", "Updated", "--event", "Created"]
                if pattern:
                    cmd.extend(["--include", pattern, "--exclude", ".*"])
                cmd.extend(abs_paths)
            else:
                cmd = ["inotifywait", "-m", "-r", "-e", "modify,create"]
                if pattern:
                    cmd.extend(["--include", pattern])
                cmd.extend(abs_paths)

            proc = await asyncio.create_subprocess_exec(
                *cmd,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.DEVNULL,
            )
            self._processes.append(proc)
            log.info("Watch %s started: %s", wid, " ".join(abs_paths))

            while True:
                line = await proc.stdout.readline()
                if not line:
                    break
                changed = line.decode().strip()
                if not changed:
                    continue

                now = time.time()
                if now - self._last_trigger.get(wid, 0) < debounce:
                    continue
                self._last_trigger[wid] = now

                desc = f"{task_desc} (triggered by: {os.path.basename(changed)})"
                log.info("Watch %s triggered: %s", wid, changed)
                try:
                    self._callback(agent, desc)
                except Exception:
                    log.warning("Watch %s: callback failed", wid, exc_info=True)

        except asyncio.CancelledError:
            pass
        except Exception:
            log.warning("Watch %s error", wid, exc_info=True)

    @staticmethod
    async def _detect_tool() -> str | None:
        for tool in ("fswatch", "inotifywait"):
            proc = await asyncio.create_subprocess_shell(
                f"command -v {tool}",
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.PIPE,
            )
            await proc.communicate()
            if proc.returncode == 0:
                return tool
        return None

    async def stop(self):
        for task in self._tasks:
            task.cancel()
        for proc in self._processes:
            try:
                proc.terminate()
            except Exception:
                pass
        self._tasks.clear()
        self._processes.clear()

    @staticmethod
    def create_config_template():
        """Create an example watches.json if none exists."""
        if WATCH_CONFIG.exists():
            return
        WATCH_CONFIG.parent.mkdir(parents=True, exist_ok=True)
        example = {
            "watches": [
                {
                    "id": "example",
                    "agent": "default",
                    "paths": ["src/"],
                    "pattern": "*.py",
                    "task": "lint the changed files",
                    "debounce": 10,
                    "enabled": False,
                }
            ]
        }
        WATCH_CONFIG.write_text(json.dumps(example, indent=2))
