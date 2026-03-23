#!/usr/bin/env python3
"""KMac Docker Vault — encrypted key-value store for secrets.

Runs inside a Docker container. Values are encrypted at rest with Fernet
(AES-128-CBC + HMAC-SHA256) in a SQLite database stored on a Docker volume.
Listens only on 127.0.0.1 inside the container — expose to host via port
mapping on 127.0.0.1 if needed.

Auth: Bearer token read from /vault/token (mounted from host).
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

DB_PATH = "/vault/data/secrets.db"
TOKEN_PATH = "/vault/token"
PORT = 9999
MAX_BODY_BYTES = 64 * 1024
RATE_WINDOW_SEC = 60.0
RATE_MAX_PER_WINDOW = 100

_ip_request_times: dict[str, deque[float]] = {}


def _rate_limit_allow(client_ip: str) -> bool:
    now = time.monotonic()
    q = _ip_request_times.setdefault(client_ip, deque())
    while q and q[0] < now - RATE_WINDOW_SEC:
        q.popleft()
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
    if os.path.exists(TOKEN_PATH):
        with open(TOKEN_PATH) as f:
            _token_cache = f.read().strip()
    else:
        _token_cache = secrets.token_urlsafe(32)
        os.makedirs(os.path.dirname(TOKEN_PATH), exist_ok=True)
        with open(TOKEN_PATH, "w") as f:
            f.write(_token_cache)
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
        except Exception:
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
            self._json_response({"ok": True, "backend": "docker"})
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
    print(f"KMac Docker Vault")
    print(f"  Port:  {PORT}")
    print(f"  DB:    {DB_PATH}")
    print("  Token: loaded")
    print(f"  Crypto: Fernet (AES-128-CBC + HMAC-SHA256)")
    print()
    server = HTTPServer(("127.0.0.1", PORT), VaultHandler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
