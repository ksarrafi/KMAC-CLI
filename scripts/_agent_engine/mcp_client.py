"""MCP (Model Context Protocol) client — connect to external MCP servers.

Spawns MCP server processes, communicates via JSON-RPC over stdio,
and registers their tools for use in agent conversations.

Config file: ~/.cache/kmac/agent/mcp.json
Format:
{
  "servers": {
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/path"],
      "enabled": true
    }
  }
}
"""

import asyncio
import json
import logging
import os
from pathlib import Path

from .config import AGENT_HOME

log = logging.getLogger("kmac-agent")

MCP_CONFIG = AGENT_HOME / "mcp.json"

_JSONRPC_ID = 0


def _next_id() -> int:
    global _JSONRPC_ID
    _JSONRPC_ID += 1
    return _JSONRPC_ID


class MCPServer:
    """A single MCP server process connection."""

    def __init__(self, name: str, command: str, args: list[str]):
        self.name = name
        self.command = command
        self.args = args
        self.process: asyncio.subprocess.Process | None = None
        self.tools: list[dict] = []
        self._reader_task: asyncio.Task | None = None
        self._pending: dict[int, asyncio.Future] = {}
        self._buf = b""

    async def start(self) -> bool:
        try:
            self.process = await asyncio.create_subprocess_exec(
                self.command, *self.args,
                stdin=asyncio.subprocess.PIPE,
                stdout=asyncio.subprocess.PIPE,
                stderr=asyncio.subprocess.DEVNULL,
            )
            self._reader_task = asyncio.ensure_future(self._read_loop())

            init_result = await self._send_request("initialize", {
                "protocolVersion": "2024-11-05",
                "capabilities": {},
                "clientInfo": {"name": "kmac-agent", "version": "1.0"},
            })
            if not init_result:
                return False

            await self._send_notification("notifications/initialized", {})

            tools_result = await self._send_request("tools/list", {})
            if tools_result and "tools" in tools_result:
                self.tools = tools_result["tools"]
                for t in self.tools:
                    t["_mcp_server"] = self.name
                log.info("MCP %s: loaded %d tools", self.name, len(self.tools))
            return True
        except Exception:
            log.warning("MCP %s: failed to start", self.name, exc_info=True)
            return False

    async def _read_loop(self):
        """Read JSON-RPC responses from stdout."""
        try:
            while self.process and self.process.returncode is None:
                line = await self.process.stdout.readline()
                if not line:
                    break
                line = line.strip()
                if not line:
                    continue
                try:
                    msg = json.loads(line)
                except json.JSONDecodeError:
                    continue
                rid = msg.get("id")
                if rid is not None and rid in self._pending:
                    self._pending[rid].set_result(msg.get("result"))
        except asyncio.CancelledError:
            pass
        except Exception:
            log.debug("MCP %s: reader error", self.name, exc_info=True)

    async def _send_request(self, method: str, params: dict, timeout: float = 30) -> dict | None:
        if not self.process or not self.process.stdin:
            return None
        rid = _next_id()
        msg = json.dumps({"jsonrpc": "2.0", "id": rid, "method": method, "params": params})
        loop = asyncio.get_event_loop()
        fut = loop.create_future()
        self._pending[rid] = fut
        try:
            self.process.stdin.write(msg.encode() + b"\n")
            await self.process.stdin.drain()
            result = await asyncio.wait_for(fut, timeout=timeout)
            return result
        except asyncio.TimeoutError:
            log.warning("MCP %s: timeout on %s", self.name, method)
            return None
        except Exception:
            return None
        finally:
            self._pending.pop(rid, None)

    async def _send_notification(self, method: str, params: dict):
        if not self.process or not self.process.stdin:
            return
        msg = json.dumps({"jsonrpc": "2.0", "method": method, "params": params})
        try:
            self.process.stdin.write(msg.encode() + b"\n")
            await self.process.stdin.drain()
        except Exception:
            pass

    async def call_tool(self, tool_name: str, arguments: dict) -> str:
        result = await self._send_request("tools/call", {
            "name": tool_name,
            "arguments": arguments,
        })
        if result is None:
            return f"MCP tool {tool_name} failed (no response)"
        content = result.get("content", [])
        text_parts = []
        for item in content:
            if isinstance(item, dict) and item.get("type") == "text":
                text_parts.append(item["text"])
            elif isinstance(item, str):
                text_parts.append(item)
        return "\n".join(text_parts) if text_parts else json.dumps(result)

    async def stop(self):
        if self._reader_task:
            self._reader_task.cancel()
        if self.process:
            try:
                self.process.terminate()
                await asyncio.wait_for(self.process.wait(), timeout=5)
            except Exception:
                try:
                    self.process.kill()
                except Exception:
                    pass


class MCPManager:
    """Manages multiple MCP server connections."""

    def __init__(self):
        self.servers: dict[str, MCPServer] = {}
        self._tool_map: dict[str, MCPServer] = {}

    async def load_config(self):
        if not MCP_CONFIG.exists():
            return

        try:
            with open(MCP_CONFIG) as f:
                config = json.load(f)
        except Exception:
            log.warning("Failed to load MCP config", exc_info=True)
            return

        for name, cfg in config.get("servers", {}).items():
            if not cfg.get("enabled", True):
                continue
            command = cfg.get("command", "")
            args = cfg.get("args", [])
            env = cfg.get("env", {})
            if not command:
                continue

            if env:
                for k, v in env.items():
                    os.environ[k] = v

            server = MCPServer(name, command, args)
            if await server.start():
                self.servers[name] = server
                for tool in server.tools:
                    prefixed_name = f"mcp_{name}_{tool['name']}"
                    tool["name"] = prefixed_name
                    self._tool_map[prefixed_name] = server

    def get_tool_schemas(self) -> list[dict]:
        """Get all MCP tool schemas formatted for the Claude API."""
        schemas = []
        for server in self.servers.values():
            for tool in server.tools:
                schema = {
                    "name": tool["name"],
                    "description": f"[MCP:{server.name}] {tool.get('description', '')}",
                    "input_schema": tool.get("inputSchema", tool.get("input_schema", {
                        "type": "object", "properties": {},
                    })),
                }
                schemas.append(schema)
        return schemas

    async def execute(self, tool_name: str, arguments: dict) -> tuple[str, str]:
        server = self._tool_map.get(tool_name)
        if not server:
            return f"Unknown MCP tool: {tool_name}", "unknown tool"

        original_name = tool_name
        for t in server.tools:
            if t["name"] == tool_name:
                parts = tool_name.split("_", 2)
                if len(parts) >= 3:
                    original_name = parts[2]
                break

        result = await server.call_tool(original_name, arguments)
        preview = result[:500] if result else "(empty)"
        return result, preview

    def has_tool(self, name: str) -> bool:
        return name in self._tool_map

    async def stop_all(self):
        for server in self.servers.values():
            await server.stop()
        self.servers.clear()
        self._tool_map.clear()

    def stats(self) -> dict:
        return {
            "servers": len(self.servers),
            "tools": sum(len(s.tools) for s in self.servers.values()),
            "server_names": list(self.servers.keys()),
        }
