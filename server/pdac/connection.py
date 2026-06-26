"""PDAC database connection management with vault integration."""

import os
import requests
from typing import Optional, Generator
from contextlib import contextmanager

try:
    import pyodbc
except ImportError:
    pyodbc = None

from .errors import ConnectionError


class PDACConnection:
    """Manages PDAC database connections via vault credentials."""

    def __init__(self, vault_url: str, vault_token: str):
        self.vault_url = vault_url
        self.vault_token = vault_token
        self._connection_string: Optional[str] = None

    def _get_vault_secret(self, key: str) -> Optional[str]:
        """Retrieve secret from vault."""
        try:
            response = requests.get(
                f"{self.vault_url}/get/{key}",
                headers={"Authorization": f"Bearer {self.vault_token}"},
                timeout=5,
            )
            if response.status_code == 200:
                return response.json().get("value")
        except Exception:
            pass
        return None

    def _load_connection_string(self) -> str:
        """Load connection string from vault."""
        if self._connection_string:
            return self._connection_string

        # Try full connection string first
        conn_str = self._get_vault_secret("pdac_reporting:connectionstring")
        if conn_str:
            self._connection_string = conn_str
            return conn_str

        # Fall back to building from components
        server = self._get_vault_secret("pdac_reporting:server")
        user = self._get_vault_secret("pdac_reporting:user")
        password = self._get_vault_secret("pdac_reporting:password")

        if not all([server, user, password]):
            raise ConnectionError(
                "PDAC credentials not found in vault. "
                "Ensure pdac_reporting:* secrets are populated."
            )

        # Build connection string
        # Handle URL that may already have protocol
        if server.startswith("http://"):
            server = server.replace("http://", "")
        if server.startswith("https://"):
            server = server.replace("https://", "")

        self._connection_string = (
            f"Server=tcp:{server},1433;"
            f"User ID={user};"
            f"Password={password};"
            f"Encrypt=True;"
            f"Connection Timeout=30;"
        )
        return self._connection_string

    @contextmanager
    def get_connection(self):
        """Context manager for database connection."""
        if not pyodbc:
            raise ConnectionError(
                "pyodbc not installed. "
                "Install with: pip install pyodbc"
            )

        conn_str = self._load_connection_string()
        try:
            conn = pyodbc.connect(conn_str)
            conn.setdecoding(pyodbc.SQL_CHAR, encoding="utf-8")
            conn.setdecoding(pyodbc.SQL_WCHAR, encoding="utf-8")
            conn.setencoding(encoding="utf-8")
            yield conn
        except pyodbc.Error as e:
            raise ConnectionError(f"Database connection failed: {e}")
        finally:
            try:
                conn.close()
            except:
                pass


_global_connection: Optional[PDACConnection] = None


def get_pdac_connection() -> PDACConnection:
    """Get or create global PDAC connection instance."""
    global _global_connection
    if _global_connection is None:
        vault_url = os.getenv("KMAC_VAULT_URL", "http://localhost:9999")
        vault_token_path = os.path.expanduser(
            "~/.config/kmac/docker-vault-token"
        )
        if not os.path.exists(vault_token_path):
            raise ConnectionError(
                f"Vault token not found at {vault_token_path}"
            )
        with open(vault_token_path) as f:
            vault_token = f.read().strip()

        _global_connection = PDACConnection(vault_url, vault_token)
    return _global_connection
