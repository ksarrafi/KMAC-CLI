#!/usr/bin/env python3
"""Minimal async smoke tests for the Pilot aiohttp app.

Run from repo root (after deps):

  cd server && python3 -m venv .venv && .venv/bin/pip install -r requirements.txt
  .venv/bin/python test_smoke.py

CI runs this via `.github/workflows/ci.yml`.
"""

from __future__ import annotations

import asyncio
import sys
from pathlib import Path

# Import app package when run as script
sys.path.insert(0, str(Path(__file__).resolve().parent))

from aiohttp.test_utils import TestClient, TestServer  # noqa: E402

from app import create_app  # noqa: E402


async def _run() -> None:
    app = create_app()
    async with TestClient(TestServer(app)) as client:
        ping = await client.get("/api/ping")
        assert ping.status == 200, f"ping status {ping.status}"
        body = await ping.json()
        assert body.get("ok") is True, body

        # Auth required for API (middleware)
        unauth = await client.get("/api/system")
        assert unauth.status == 401, f"expected 401 without token, got {unauth.status}"


def main() -> None:
    asyncio.run(_run())
    print("Pilot server smoke: ok (/api/ping + /api/system unauthorized)")


if __name__ == "__main__":
    main()
