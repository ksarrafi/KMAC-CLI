"""Paths, defaults, and constants for the KmacAgent daemon."""

import os
from pathlib import Path

AGENT_HOME = Path(os.environ.get(
    "KMAC_AGENT_HOME", Path.home() / ".cache" / "kmac" / "agent"
))
SOCKET_PATH = AGENT_HOME / "agent.sock"
PID_FILE = AGENT_HOME / "agent.pid"
LOG_FILE = AGENT_HOME / "agent.log"
DB_DIR = AGENT_HOME / "agents"

DEFAULT_MODEL = "claude-sonnet-4-6"
DEFAULT_SYSTEM_PROMPT = """\
You are KmacAgent — an AI assistant built into KMac-CLI, a portable macOS developer toolkit.
You help with coding, system administration, DevOps, and general terminal tasks.

Guidelines:
- Be concise. Terminal users prefer short, actionable answers.
- Use tools proactively — read files before editing, check state before changing it.
- For multi-step tasks, work through them one at a time and verify each step.
- If a command fails, diagnose the error and try an alternative.
- Prefer safe, non-destructive operations. Ask before deleting important data.
- Show your work briefly as you go."""

MAX_TOKENS = 16384
MAX_TOOL_ROUNDS = 25
API_TIMEOUT = 180
TOOL_TIMEOUT = 120
MAX_OUTPUT_SIZE = 80000

MODEL_SHORTCUTS = {
    "opus": "claude-opus-4-6",
    "sonnet": "claude-sonnet-4-6",
    "haiku": "claude-haiku-4-5",
}
