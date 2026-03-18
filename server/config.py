"""KMac Pilot Server — configuration."""

import json
import os
import secrets
from pathlib import Path

PILOT_DIR = Path("/tmp/kmac-pilot")
CONFIG_DIR = Path.home() / ".config" / "kmac-pilot"
CONFIG_FILE = CONFIG_DIR / "config.json"
SERVER_TOKEN_FILE = CONFIG_DIR / "server_token"

PILOT_DIR.mkdir(parents=True, exist_ok=True)
CONFIG_DIR.mkdir(parents=True, exist_ok=True)

HOST = os.getenv("KMAC_HOST", "0.0.0.0")
PORT = int(os.getenv("KMAC_PORT", "7890"))


def load_config() -> dict:
    if CONFIG_FILE.exists():
        try:
            return json.loads(CONFIG_FILE.read_text())
        except (json.JSONDecodeError, OSError):
            return {}
    return {}


def save_config(cfg: dict):
    CONFIG_FILE.write_text(json.dumps(cfg, indent=2))


def get_or_create_token() -> str:
    """Return the server auth token, generating one on first run."""
    if SERVER_TOKEN_FILE.exists():
        return SERVER_TOKEN_FILE.read_text().strip()
    token = secrets.token_urlsafe(32)
    SERVER_TOKEN_FILE.write_text(token)
    SERVER_TOKEN_FILE.chmod(0o600)
    return token


def project_scan_dirs() -> list[str]:
    cfg = load_config()
    raw = cfg.get("project_dirs", str(Path.home() / "Projects"))
    return [
        os.path.expanduser(d.strip())
        for d in raw.split(",")
        if os.path.isdir(os.path.expanduser(d.strip()))
    ]


def active_agent() -> str:
    return load_config().get("agent", "claude")
