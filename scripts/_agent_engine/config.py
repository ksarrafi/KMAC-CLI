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

# ── Model routing ────────────────────────────────────────────────
MODEL_SHORTCUTS = {
    "opus": "claude-opus-4-6",
    "sonnet": "claude-sonnet-4-6",
    "haiku": "claude-haiku-4-5",
    "gpt4": "gpt-4o",
    "gpt4o": "gpt-4o",
    "gpt4-mini": "gpt-4o-mini",
    "ollama": "ollama/llama3.2",
}

PROVIDER_PREFIXES = {
    "claude-": "anthropic",
    "gpt-": "openai",
    "o1": "openai",
    "ollama/": "ollama",
}

OLLAMA_BASE_URL = os.environ.get("OLLAMA_BASE_URL", "http://localhost:11434")
OPENAI_API_URL = "https://api.openai.com/v1/chat/completions"

# ── Safety ───────────────────────────────────────────────────────
DANGEROUS_PATTERNS = [
    "rm -rf /", "rm -rf /*", "rm -rf ~",
    "mkfs.", "dd if=", ":(){:|:&};:",
    "> /dev/sda", "chmod -R 777 /",
    "mv /* ", "mv / ", "wget|sh", "curl|sh",
    "shutdown", "reboot", "halt",
    "kill -9 1", "kill -9 -1",
    "DROP DATABASE", "DROP TABLE",
    "truncate", "FORMAT",
]

DANGEROUS_PREFIXES = [
    "rm -rf /", "rm -rf /*", "rm -rf ~",
    "mkfs", ":(){", "dd if=/dev/",
    "chmod -R 777 /", "shutdown", "reboot", "halt",
]

# ── Retry ────────────────────────────────────────────────────────
MAX_RETRIES = 3
RETRY_BACKOFF = [1, 3, 10]
RETRYABLE_HTTP_CODES = {429, 500, 502, 503, 529}

# ── Rate limiting ────────────────────────────────────────────────
RATE_LIMIT_RPM = int(os.environ.get("KMAC_RATE_LIMIT_RPM", "50"))
RATE_LIMIT_TPM = int(os.environ.get("KMAC_RATE_LIMIT_TPM", "100000"))

# ── Cost per million tokens (input, output) ──────────────────────
MODEL_COSTS = {
    "claude-opus-4-6":   (15.0, 75.0),
    "claude-sonnet-4-6": (3.0, 15.0),
    "claude-haiku-4-5":  (0.25, 1.25),
    "gpt-4o":            (2.5, 10.0),
    "gpt-4o-mini":       (0.15, 0.6),
}
COST_WARNING_THRESHOLD = 0.10  # warn if single call may exceed $0.10

# ── Conversation management ──────────────────────────────────────
CONTEXT_TOKEN_LIMIT = 80000
SUMMARIZE_AFTER_MESSAGES = 30
SESSION_MAX_AGE_DAYS = 14
SESSION_PRUNE_INTERVAL = 3600

# ── Plugin / MCP ─────────────────────────────────────────────────
PLUGIN_DIR = AGENT_HOME / "plugins"
MCP_CONFIG = AGENT_HOME / "mcp.json"
