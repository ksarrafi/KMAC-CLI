#!/usr/bin/env python3
"""KMac Vault Server — encrypted key-value store for secrets.

Deployment modes:
  1. Docker:  runs in a container with volume mount and token file
  2. Railway: reads config from env vars, binds to 0.0.0.0:$PORT
  3. Local:   runs standalone for development

Values are encrypted at rest with Fernet (AES-128-CBC + HMAC-SHA256)
in a SQLite database. Auth via Bearer token.

Env vars (all optional, with sensible defaults):
  VAULT_DB_PATH     — SQLite path        (default: /vault/data/secrets.db)
  VAULT_TOKEN       — Bearer auth token  (default: read from /vault/token or auto-generated)
  VAULT_PORT        — Listen port        (default: 9999, Railway sets PORT)
  VAULT_BIND        — Bind address       (default: 127.0.0.1, 0.0.0.0 on Railway)
  RAILWAY_ENVIRONMENT — set by Railway automatically
"""

import base64
import hashlib
import hmac
import json
import os
import secrets
import sqlite3
import sys
import time
from collections import deque
from http.server import HTTPServer, BaseHTTPRequestHandler
from typing import Optional

try:
    from cryptography.fernet import Fernet
except ImportError as exc:
    print(
        "cryptography (Fernet) is required; install with: pip install cryptography",
        file=sys.stderr,
    )
    raise SystemExit(1) from exc

IS_RAILWAY = bool(os.environ.get("RAILWAY_ENVIRONMENT"))

DB_PATH = os.environ.get("VAULT_DB_PATH", "/vault/data/secrets.db")
TOKEN_PATH = "/vault/token"
PORT = int(os.environ.get("VAULT_PORT", os.environ.get("PORT", "9999")))
BIND = os.environ.get("VAULT_BIND", "0.0.0.0" if IS_RAILWAY else "127.0.0.1")
MAX_BODY_BYTES = 64 * 1024
RATE_WINDOW_SEC = 60.0
RATE_MAX_PER_WINDOW = 100

_ip_request_times: dict[str, deque[float]] = {}


def _rate_limit_allow(client_ip: str) -> bool:
    now = time.monotonic()
    q = _ip_request_times.setdefault(client_ip, deque())
    while q and q[0] < now - RATE_WINDOW_SEC:
        q.popleft()
    if len(_ip_request_times) > 10_000:
        oldest = sorted(
            _ip_request_times.keys(),
            key=lambda k: _ip_request_times[k][-1] if _ip_request_times[k] else 0,
        )
        for k in oldest[: len(_ip_request_times) - 5000]:
            del _ip_request_times[k]
    if len(q) >= RATE_MAX_PER_WINDOW:
        return False
    q.append(now)
    return True


def _derive_key():
    """Derive encryption key from the auth token using a per-deployment salt."""
    salt_path = DB_PATH + ".salt"
    if os.path.exists(salt_path):
        with open(salt_path, "rb") as f:
            salt = f.read()
    else:
        salt = os.urandom(32)
        with open(salt_path, "wb") as f:
            f.write(salt)
        os.chmod(salt_path, 0o600)
    token = _load_token()
    key = hashlib.pbkdf2_hmac("sha256", token.encode(), salt, 200_000)
    return base64.urlsafe_b64encode(key[:32])


def _encrypt(plaintext: str) -> str:
    key = _derive_key()
    f = Fernet(key)
    return f.encrypt(plaintext.encode()).decode()


def _decrypt(ciphertext: str) -> str:
    key = _derive_key()
    f = Fernet(key)
    return f.decrypt(ciphertext.encode()).decode()


_token_cache: Optional[str] = None


def _load_token() -> str:
    global _token_cache
    if _token_cache is not None:
        return _token_cache
    env_token = os.environ.get("VAULT_TOKEN", "").strip()
    if env_token:
        _token_cache = env_token
    elif os.path.exists(TOKEN_PATH):
        with open(TOKEN_PATH) as f:
            _token_cache = f.read().strip()
    else:
        _token_cache = secrets.token_urlsafe(32)
        try:
            os.makedirs(os.path.dirname(TOKEN_PATH), exist_ok=True)
            with open(TOKEN_PATH, "w") as f:
                f.write(_token_cache)
            os.chmod(TOKEN_PATH, 0o600)
        except OSError:
            pass
    return _token_cache


def _init_db():
    os.makedirs(os.path.dirname(DB_PATH), exist_ok=True)
    conn = sqlite3.connect(DB_PATH)
    conn.execute("""
        CREATE TABLE IF NOT EXISTS secrets (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL,
            updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)
    conn.commit()
    return conn


_db = _init_db()


class VaultHandler(BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        pass  # silent

    def _client_ip(self) -> str:
        return self.client_address[0] if self.client_address else "unknown"

    def _auth_ok(self) -> bool:
        auth = self.headers.get("Authorization", "")
        token = auth.removeprefix("Bearer ").strip()
        if not token:
            return False
        try:
            return hmac.compare_digest(
                token.encode("utf-8"), _load_token().encode("utf-8")
            )
        except (UnicodeEncodeError, TypeError):
            return False

    def _json_response(self, data: dict, status: int = 200):
        body = json.dumps(data).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _read_body(self) -> Optional[dict]:
        try:
            length = int(self.headers.get("Content-Length", 0))
        except ValueError:
            return None
        if length > MAX_BODY_BYTES:
            return None
        if length == 0:
            return {}
        raw = self.rfile.read(length)
        if len(raw) != length:
            return {}
        try:
            return json.loads(raw.decode())
        except json.JSONDecodeError:
            return {}

    def _content_length_allowed(self) -> bool:
        cl = self.headers.get("Content-Length")
        if cl is None or cl == "":
            return True
        try:
            if int(cl) > MAX_BODY_BYTES:
                self._json_response({"error": "payload too large"}, 413)
                return False
        except ValueError:
            self._json_response({"error": "invalid Content-Length"}, 400)
            return False
        return True

    def _preflight(self) -> bool:
        if not self._content_length_allowed():
            return False
        if not _rate_limit_allow(self._client_ip()):
            self._json_response({"error": "rate limited"}, 429)
            return False
        return True

    def do_GET(self):
        if not self._preflight():
            return

        if self.path == "/health":
            mode = "railway" if IS_RAILWAY else "docker"
            self._json_response({"ok": True, "backend": mode})
            return

        if not self._auth_ok():
            self._json_response({"error": "unauthorized"}, 401)
            return

        if self.path.startswith("/get/"):
            key = self.path[5:]
            row = _db.execute("SELECT value FROM secrets WHERE key = ?", (key,)).fetchone()
            if row:
                try:
                    val = _decrypt(row[0])
                    self._json_response({"key": key, "value": val})
                except Exception:
                    self._json_response({"error": "decryption failed"}, 500)
            else:
                self._json_response({"error": "not found"}, 404)

        elif self.path == "/list":
            rows = _db.execute("SELECT key FROM secrets ORDER BY key").fetchall()
            self._json_response({"keys": [r[0] for r in rows]})

        elif self.path.startswith("/has/"):
            key = self.path[5:]
            row = _db.execute("SELECT 1 FROM secrets WHERE key = ?", (key,)).fetchone()
            self._json_response({"exists": row is not None})

        else:
            self._json_response({"error": "not found"}, 404)

    def do_POST(self):
        if not self._preflight():
            return

        if not self._auth_ok():
            self._json_response({"error": "unauthorized"}, 401)
            return

        if self.path == "/set":
            body = self._read_body()
            if body is None:
                self._json_response({"error": "body too large or invalid"}, 413)
                return
            key = body.get("key", "")
            value = body.get("value", "")
            if not key or not value:
                self._json_response({"error": "key and value required"}, 400)
                return
            encrypted = _encrypt(value)
            _db.execute(
                "INSERT OR REPLACE INTO secrets (key, value, updated_at) VALUES (?, ?, CURRENT_TIMESTAMP)",
                (key, encrypted),
            )
            _db.commit()
            self._json_response({"ok": True, "key": key})

        elif self.path.startswith("/delete/"):
            key = self.path[8:]
            _db.execute("DELETE FROM secrets WHERE key = ?", (key,))
            _db.commit()
            self._json_response({"ok": True, "key": key})

        else:
            self._json_response({"error": "not found"}, 404)

    def do_DELETE(self):
        self.do_POST()


if __name__ == "__main__":
    token = _load_token()
    mode = "Railway" if IS_RAILWAY else "Docker/Local"
    print(f"KMac Vault Server ({mode})")
    print(f"  Bind:  {BIND}:{PORT}")
    print(f"  DB:    {DB_PATH}")
    print(f"  Token: {'env' if os.environ.get('VAULT_TOKEN') else 'file'}")
    print(f"  Crypto: Fernet (AES-128-CBC + HMAC-SHA256)")
    print()
    server = HTTPServer((BIND, PORT), VaultHandler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
