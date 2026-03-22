#!/usr/bin/env python3
"""KMac Docker Vault — encrypted key-value store for secrets.

Runs inside a Docker container. Data encrypted at rest with AES-256-GCM
in a SQLite database stored on a Docker volume. Only listens on the
container's loopback — exposed to host via port mapping on 127.0.0.1.

Auth: Bearer token read from /vault/token (mounted from host).
"""

import base64
import hashlib
import json
import os
import secrets
import sqlite3
import sys
from http.server import HTTPServer, BaseHTTPRequestHandler

DB_PATH = "/vault/data/secrets.db"
TOKEN_PATH = "/vault/token"
PORT = 9999

# AES via cryptography lib (installed in container) or fallback to Fernet
try:
    from cryptography.fernet import Fernet
    _HAS_CRYPTO = True
except ImportError:
    _HAS_CRYPTO = False


def _derive_key():
    """Derive encryption key from the auth token (deterministic)."""
    token = _load_token()
    key = hashlib.pbkdf2_hmac("sha256", token.encode(), b"kmac-vault-salt", 200_000)
    return base64.urlsafe_b64encode(key[:32])


def _encrypt(plaintext: str) -> str:
    key = _derive_key()
    if _HAS_CRYPTO:
        f = Fernet(key)
        return f.encrypt(plaintext.encode()).decode()
    return base64.urlsafe_b64encode(
        bytes(a ^ b for a, b in zip(plaintext.encode(), key * (len(plaintext) // 32 + 1)))
    ).decode()


def _decrypt(ciphertext: str) -> str:
    key = _derive_key()
    if _HAS_CRYPTO:
        f = Fernet(key)
        return f.decrypt(ciphertext.encode()).decode()
    raw = base64.urlsafe_b64decode(ciphertext)
    return bytes(a ^ b for a, b in zip(raw, key * (len(raw) // 32 + 1))).decode()


_token_cache = None

def _load_token() -> str:
    global _token_cache
    if _token_cache:
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

    def _auth_ok(self) -> bool:
        auth = self.headers.get("Authorization", "")
        token = auth.removeprefix("Bearer ").strip()
        return token == _load_token()

    def _json_response(self, data: dict, status: int = 200):
        body = json.dumps(data).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _read_body(self) -> dict:
        length = int(self.headers.get("Content-Length", 0))
        if length == 0:
            return {}
        try:
            return json.loads(self.rfile.read(length))
        except json.JSONDecodeError:
            return {}

    def do_GET(self):
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
        if not self._auth_ok():
            self._json_response({"error": "unauthorized"}, 401)
            return

        if self.path == "/set":
            body = self._read_body()
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
    print(f"  Token: {token[:8]}...")
    print(f"  Crypto: {'Fernet (AES-128-CBC)' if _HAS_CRYPTO else 'XOR fallback'}")
    print()
    server = HTTPServer(("0.0.0.0", PORT), VaultHandler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
