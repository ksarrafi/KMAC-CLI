#!/usr/bin/env python3
"""KMac Pilot Server — REST API + WebSocket for remote AI agent control."""

import asyncio
import hmac
import json
import logging
import os
import platform
import re
import shlex
import time
from pathlib import Path
from typing import Optional

import aiohttp
from aiohttp import web

from config import HOST, PORT, get_or_create_token, load_config, active_agent
from session_manager import SessionManager
from projects import list_projects, resolve_project, file_tree, read_file, browse_directory, get_browse_roots
from git_ops import diff_stat, approve, reject, log_oneline
from docker_ops import (
    _SAFE_ID,
    docker_available,
    containers,
    images,
    container_action,
    container_logs,
    system_df,
)
from docker_dashboard import register_routes as register_docker_health_routes
from system_ops import disk_usage, memory_info, top_processes, network_info, services_status, homebrew_services

log = logging.getLogger(__name__)

session_mgr = SessionManager()
AUTH_TOKEN = get_or_create_token()

_WS_MAX_CLIENTS = 100
_WS_MAX_SESSION_SUBS = 50


class WSClientState:
    """Per-WebSocket subscription state (system metrics + session streams)."""

    __slots__ = ("ws", "system", "sessions")

    def __init__(self, ws: web.WebSocketResponse):
        self.ws = ws
        self.system = False
        self.sessions: set[str] = set()

# ── Auth middleware ───────────────────────────────────────────────────────

@web.middleware
async def auth_middleware(request: web.Request, handler):
    if request.path in ("/api/ping", "/ws") or request.path.startswith("/static/"):
        return await handler(request)

    token = request.headers.get("Authorization", "").removeprefix("Bearer ").strip()
    if (
        not token
        or len(token) != len(AUTH_TOKEN)
        or not hmac.compare_digest(token, AUTH_TOKEN)
    ):
        return web.json_response({"error": "Unauthorized"}, status=401)
    return await handler(request)


def json_ok(data: dict, status: int = 200) -> web.Response:
    return web.json_response(data, status=status)


# ── System ───────────────────────────────────────────────────────────────

async def handle_ping(_request):
    return json_ok({"ok": True, "ts": int(time.time())})


async def handle_system(_request):
    proc_up = await asyncio.create_subprocess_exec(
        "uptime",
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.DEVNULL,
    )
    stdout_up, _ = await proc_up.communicate()
    raw_up = stdout_up.decode(errors="replace").strip() if stdout_up else ""
    idx = raw_up.find(" up ")
    if idx >= 0:
        rest = raw_up[idx + 1 :].strip()
        c = rest.find(",")
        uptime = rest[:c] if c >= 0 else rest
    else:
        uptime = raw_up or "?"

    proc_ld = await asyncio.create_subprocess_exec(
        "sysctl", "-n", "vm.loadavg",
        stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL,
    )
    stdout_ld, _ = await proc_ld.communicate()
    load = stdout_ld.decode(errors="replace").split() if stdout_ld else []
    cfg = load_config()
    return json_ok({
        "hostname": platform.node(),
        "uptime": uptime,
        "load": load[1] if len(load) > 1 else "?",
        "agent": active_agent(),
        "agent_label": "Cursor Agent" if active_agent() == "cursor" else "Claude Code",
        "project_dirs": cfg.get("project_dirs", "~/Projects"),
        "bot_username": cfg.get("bot_username", ""),
    })


# ── Projects ─────────────────────────────────────────────────────────────

async def handle_projects(request):
    q = request.query.get("filter", "")
    return json_ok({"projects": list_projects(q)})


# ── Files ────────────────────────────────────────────────────────────────

async def handle_file_tree(request):
    project = request.query.get("project", "")
    sub = request.query.get("path", "")
    project_dir = resolve_project(project) if project else _active_dir()

    if not project_dir:
        return json_ok({"error": "No project specified"}, 400)

    return json_ok({"tree": file_tree(project_dir, sub), "project": project})


async def handle_file_read(request):
    project = request.query.get("project", "")
    path = request.query.get("path", "")
    project_dir = resolve_project(project) if project else _active_dir()

    if not project_dir or not path:
        return json_ok({"error": "project and path required"}, 400)

    return json_ok(read_file(project_dir, path))


async def handle_browse_roots(_request):
    return json_ok({"roots": get_browse_roots()})


async def handle_browse(request):
    dir_path = request.query.get("path", "")
    if not dir_path:
        return json_ok({"error": "path required"}, 400)
    return json_ok(browse_directory(dir_path))


async def handle_file_read_abs(request):
    """Read a file by absolute path (must be under home dir)."""
    file_path = request.query.get("path", "")
    if not file_path:
        return json_ok({"error": "path required"}, 400)

    from pathlib import Path as P
    fp = P(file_path).resolve()
    try:
        fp.relative_to(P.home().resolve())
    except ValueError:
        return json_ok({"error": "Access denied"}, 403)

    if not fp.is_file():
        return json_ok({"error": "File not found"}, 404)

    size = fp.stat().st_size
    if size > 500_000:
        return json_ok({"error": f"File too large ({size} bytes)"}, 413)

    try:
        content = fp.read_text(errors="replace")
    except Exception:
        return json_ok({"error": "Internal server error"}, 500)

    return json_ok({
        "path": str(fp),
        "name": fp.name,
        "content": content,
        "size": size,
        "extension": fp.suffix.lstrip("."),
    })


# ── Git ──────────────────────────────────────────────────────────────────

async def handle_diff(request):
    project_dir = _active_dir()
    if not project_dir:
        return json_ok({"error": "No active project"}, 400)
    return json_ok(diff_stat(project_dir))


async def handle_approve(request):
    try:
        body = await request.json()
    except Exception:
        body = {}
    project_dir = _active_dir()
    if not project_dir:
        return json_ok({"error": "No active project"}, 400)
    return json_ok(approve(project_dir, body.get("message", "")))


async def handle_reject(_request):
    project_dir = _active_dir()
    if not project_dir:
        return json_ok({"error": "No active project"}, 400)
    return json_ok(reject(project_dir))


async def handle_git_log(request):
    project = request.query.get("project", "")
    project_dir = resolve_project(project) if project else _active_dir()
    if not project_dir:
        return json_ok({"error": "No project"}, 400)
    try:
        count = int(request.query.get("count", "20"))
    except ValueError:
        count = 20
    count = max(1, min(count, 200))
    return json_ok({"commits": log_oneline(project_dir, count)})


# ── Sessions (multi-agent) ───────────────────────────────────────────────

async def handle_sessions_list(_request):
    sessions = [s.to_dict() for s in session_mgr.sessions]
    return json_ok({
        "sessions": sessions,
        "running": session_mgr.running_count,
        "total": len(sessions),
    })


async def handle_session_create(request):
    try:
        body = await request.json()
    except Exception:
        return json_ok({"error": "Invalid JSON body"}, 400)
    project_name = body.get("project", "")
    prompt = body.get("prompt", "")
    agent = body.get("agent", "")

    if not project_name:
        return json_ok({"error": "project required"}, 400)

    project_dir = resolve_project(project_name)
    if not project_dir:
        return json_ok({"error": f"Project '{project_name}' not found"}, 404)

    result = await session_mgr.create_session(project_name, project_dir, prompt, agent)
    return json_ok(result, 200 if result.get("ok") else 409)


async def handle_session_detail(request):
    sid = request.match_info["id"]
    session = session_mgr.get(sid)
    if not session:
        return json_ok({"error": "Session not found"}, 404)
    return json_ok(session.to_dict())


async def handle_session_output(request):
    sid = request.match_info["id"]
    session = session_mgr.get(sid)
    if not session:
        return json_ok({"error": "Session not found"}, 404)
    try:
        tail = int(request.query.get("tail", "100"))
    except ValueError:
        tail = 100
    tail = max(1, min(tail, 10000))
    lines = session.output_lines[-tail:]
    return json_ok({"lines": lines, "total": len(session.output_lines), "session_id": sid})


async def handle_session_stop(request):
    sid = request.match_info["id"]
    result = await session_mgr.stop_session(sid)
    return json_ok(result, 200 if result.get("ok") else 400)


async def handle_session_delete(request):
    sid = request.match_info["id"]
    result = await session_mgr.remove_session(sid)
    return json_ok(result, 200 if result.get("ok") else 400)


async def handle_session_ask(request):
    sid = request.match_info["id"]
    try:
        body = await request.json()
    except Exception:
        return json_ok({"error": "Invalid JSON body"}, 400)
    question = body.get("question", "")
    if not question:
        return json_ok({"error": "question required"}, 400)
    result = await session_mgr.ask(sid, question)
    return json_ok(result, 200 if result.get("ok") else 400)


async def handle_session_send(request):
    sid = request.match_info["id"]
    try:
        body = await request.json()
    except Exception:
        return json_ok({"error": "Invalid JSON body"}, 400)
    message = body.get("message", "")
    if not message:
        return json_ok({"error": "message required"}, 400)
    result = await session_mgr.send_message(sid, message)
    return json_ok(result, 200 if result.get("ok") else 400)


# Legacy single-task endpoints — map to sessions for backward compatibility

async def handle_task_start(request):
    return await handle_session_create(request)


async def handle_task_status(_request):
    active = session_mgr.active_sessions
    if active:
        s = active[-1]
        return json_ok({
            "running": True,
            "task": {"project": s.project, "dir": s.project_dir, "task": s.task,
                     "agent": s.agent, "agent_label": s.agent_label,
                     "started": s.started, "status": s.status},
            "output_lines": len(s.output_lines),
        })
    # Return most recent session
    all_sessions = session_mgr.sessions
    if all_sessions:
        s = all_sessions[-1]
        return json_ok({
            "running": False,
            "task": {"project": s.project, "dir": s.project_dir, "task": s.task,
                     "agent": s.agent, "agent_label": s.agent_label,
                     "started": s.started, "status": s.status},
            "output_lines": len(s.output_lines),
        })
    return json_ok({"running": False, "task": {}, "output_lines": 0})


async def handle_task_stop(_request):
    active = session_mgr.active_sessions
    if not active:
        return json_ok({"error": "No active sessions"}, 400)
    result = await session_mgr.stop_session(active[-1].id)
    return json_ok(result)


async def handle_task_output(request):
    all_sessions = session_mgr.sessions
    if not all_sessions:
        return json_ok({"lines": [], "total": 0})
    s = all_sessions[-1]
    try:
        tail = int(request.query.get("tail", "50"))
    except ValueError:
        tail = 50
    tail = max(1, min(tail, 10000))
    return json_ok({"lines": s.output_lines[-tail:], "total": len(s.output_lines)})


async def handle_ask(request):
    try:
        body = await request.json()
    except Exception:
        return json_ok({"error": "Invalid JSON body"}, 400)
    question = body.get("question", "")
    if not question:
        return json_ok({"error": "question required"}, 400)
    all_sessions = session_mgr.sessions
    if not all_sessions:
        return json_ok({"error": "No sessions"}, 400)
    result = await session_mgr.ask(all_sessions[-1].id, question)
    return json_ok(result, 200 if result.get("ok") else 400)


# ── Docker ────────────────────────────────────────────────────────────────

async def handle_docker_status(_request):
    return json_ok({"available": docker_available()})


async def handle_docker_containers(request):
    show_all = request.query.get("all", "true").lower() == "true"
    return json_ok({"containers": await containers(show_all)})


async def handle_docker_images(_request):
    return json_ok({"images": await images()})


async def handle_docker_action(request):
    try:
        body = await request.json()
    except Exception:
        return json_ok({"error": "Invalid JSON body"}, 400)
    cid = body.get("container", "")
    action = body.get("action", "")
    if not cid or not action:
        return json_ok({"error": "container and action required"}, 400)
    result = await container_action(cid, action)
    return json_ok(result, 200 if result.get("ok") else 400)


async def handle_docker_logs(request):
    cid = request.query.get("container", "")
    try:
        tail = int(request.query.get("tail", "100"))
    except ValueError:
        tail = 100
    if not cid:
        return json_ok({"error": "container required"}, 400)
    return json_ok(await container_logs(cid, tail))


async def handle_docker_df(_request):
    return json_ok(await system_df())


# ── System / Toolkit ─────────────────────────────────────────────────────

async def handle_disk(_request):
    return json_ok({"disks": await disk_usage()})


async def handle_memory(_request):
    return json_ok(await memory_info())


async def handle_processes(_request):
    return json_ok({"processes": await top_processes()})


async def handle_network(_request):
    return json_ok(await network_info())


async def handle_services(_request):
    return json_ok({"services": await services_status()})


async def handle_brew_services(_request):
    return json_ok({"services": await homebrew_services()})


# ── Run shell command ────────────────────────────────────────────────────

_BLOCKED_PATTERNS = [
    re.compile(r"\brm\s+-[^\s]*r[^\s]*f\s+/\s*$"),  # rm -rf /
    re.compile(r"\bmkfs\b"),
    re.compile(r"\bdd\s+if="),
    re.compile(r":\(\)\s*\{"),                         # fork bomb
    re.compile(r"\bsudo\b"),
    re.compile(r">\s*/dev/sd"),
    re.compile(r"\bcurl\b.*\|\s*(ba)?sh"),             # pipe to shell
]

# None => read-only command, allow any argv after program name.
# List => argv[1] must be one of these subcommands (see git/brew for extras).
_ALLOWED_COMMANDS: dict[str, Optional[list[str]]] = {
    "ls": None,
    "cat": None,
    "head": None,
    "tail": None,
    "wc": None,
    "du": None,
    "df": None,
    "uname": None,
    "whoami": None,
    "date": None,
    "uptime": None,
    "which": None,
    "echo": None,
    "pwd": None,
    "git": ["status", "log", "diff", "branch", "remote", "show"],
    "docker": ["ps", "images", "logs", "inspect", "stats"],
    "brew": ["list", "info", "outdated"],
    "npm": ["list", "ls", "outdated"],
    "pip3": ["list", "show"],
}

_MAX_RUN_OUTPUT_BYTES = 1_048_576


def _validate_run_argv(argv: list[str]) -> Optional[str]:
    """Return error message or None if argv is allowed."""
    if not argv:
        return "command required"
    prog = os.path.basename(argv[0])
    if prog not in _ALLOWED_COMMANDS:
        return f"Command not allowed: {prog}"
    allowed = _ALLOWED_COMMANDS[prog]
    if allowed is None:
        return None

    if prog == "git":
        if len(argv) < 2:
            return "git: subcommand required"
        sub = argv[1]
        if sub == "stash":
            if len(argv) < 3 or argv[2] != "list":
                return "git: only 'stash list' allowed for stash"
            for arg in argv[2:]:
                if arg.startswith('-') and arg in ('--exec', '--upload-pack', '-c', '--config'):
                    return f"git: flag not allowed: {arg}"
            return None
        if sub in allowed:
            for arg in argv[2:]:
                if arg.startswith('-') and arg in ('--exec', '--upload-pack', '-c', '--config'):
                    return f"git: flag not allowed: {arg}"
            return None
        return f"git: subcommand not allowed: {sub}"

    if prog == "brew":
        if len(argv) < 2:
            return "brew: subcommand required"
        if argv[1] in allowed:
            return None
        if argv[1] == "services" and len(argv) >= 3 and argv[2] == "list":
            return None
        return "brew: only list, info, outdated, or services list"

    if prog == "docker":
        if len(argv) < 2:
            return "docker: subcommand required"
        if argv[1] not in allowed:
            return f"docker: subcommand not allowed: {argv[1]}"
        for arg in argv[2:]:
            if arg.startswith('-') and arg in ('--privileged', '--pid', '--network'):
                return f"docker: flag not allowed: {arg}"
        sub_d = argv[1]
        if sub_d in ("logs", "inspect", "stats"):
            non_flags = [a for a in argv[2:] if not a.startswith('-')]
            if non_flags and not _SAFE_ID.match(non_flags[-1]):
                return "docker: invalid container ID"
        return None

    if len(argv) < 2:
        return f"{prog}: subcommand required"
    if argv[1] not in allowed:
        return f"{prog}: subcommand not allowed: {argv[1]}"
    return None


def _validate_run_command(cmd: str) -> tuple[Optional[str], Optional[list[str]]]:
    """Return (error_message, argv). error_message is None if OK."""
    if not cmd:
        return "command required", None
    for pat in _BLOCKED_PATTERNS:
        if pat.search(cmd):
            return "Blocked: potentially destructive command", None
    try:
        argv = shlex.split(cmd)
    except ValueError:
        return "Malformed command", None
    err = _validate_run_argv(argv)
    if err:
        return err, argv
    return None, argv


async def _read_process_output_limited(
    proc: asyncio.subprocess.Process, limit: int, timeout: float
) -> tuple[bytes, Optional[str]]:
    """Read merged stdout/stderr up to `limit` bytes. Returns (data, error_tag)."""
    assert proc.stdout is not None
    chunks: list[bytes] = []
    total = 0
    timed_out = False

    async def _drain():
        nonlocal total
        while True:
            chunk = await proc.stdout.read(65536)
            if not chunk:
                break
            if total + len(chunk) > limit:
                chunks.append(chunk[: limit - total])
                total = limit
                try:
                    proc.kill()
                except ProcessLookupError:
                    pass
                break
            chunks.append(chunk)
            total += len(chunk)

    try:
        await asyncio.wait_for(_drain(), timeout=timeout)
    except asyncio.TimeoutError:
        timed_out = True
        try:
            proc.kill()
        except ProcessLookupError:
            pass
    await proc.wait()
    data = b"".join(chunks)
    if timed_out:
        return data, "timeout"
    if total >= limit:
        return data, "truncated"
    return data, None


async def _execute_run_command(cmd: str, cwd: str) -> dict:
    """Run shell command with the same rules as /api/run. cwd must be a directory."""
    err, argv = _validate_run_command(cmd)
    if err or not argv:
        return {"error": err or "command required", "argv": argv}
    prog = os.path.basename(argv[0])
    proc = None
    try:
        proc = await asyncio.create_subprocess_exec(
            *argv,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.STDOUT,
            cwd=cwd,
        )
        stdout, out_err = await _read_process_output_limited(
            proc, _MAX_RUN_OUTPUT_BYTES, 30.0
        )
        output = stdout.decode("utf-8", errors="replace") if stdout else ""
        if out_err == "timeout":
            return {"error": "Command timed out (30s)", "exit_code": -1}
        if out_err == "truncated":
            output += "\n[output truncated at 1MB limit]"
        return {"stdout": output, "exit_code": proc.returncode if proc.returncode is not None else -1}
    except FileNotFoundError:
        return {"error": f"Command not found: {prog}", "exit_code": -1}


def _resolve_exec_cwd(cwd_raw: str) -> tuple[Optional[str], Optional[str]]:
    """Resolve WebSocket exec cwd: must be under home. Returns (path, error_message)."""
    if not (cwd_raw or "").strip():
        d = _active_dir()
        if not d:
            return None, "No project context"
        return d, None
    p = Path(cwd_raw).expanduser().resolve()
    try:
        p.relative_to(Path.home().resolve())
    except ValueError:
        return None, "cwd must be under your home directory"
    if not p.is_dir():
        return None, "cwd is not a directory"
    return str(p), None


async def handle_run(request):
    try:
        body = await request.json()
    except Exception:
        return json_ok({"error": "Invalid JSON body"}, 400)
    cmd = body.get("command", "")
    project = body.get("project", "")

    err, _argv = _validate_run_command(cmd)
    if err:
        code = 403 if ("Blocked" in err or "not allowed" in err) else 400
        return json_ok({"error": err}, code)

    project_dir = resolve_project(project) if project else _active_dir()
    if not project_dir:
        return json_ok({"error": "No project context"}, 400)

    result = await _execute_run_command(cmd, project_dir)
    if "error" in result:
        status = 408 if "timed out" in result.get("error", "") else 400
        return json_ok(result, status)
    return json_ok({"output": result["stdout"], "exit_code": result["exit_code"]})


# ── WebSocket ────────────────────────────────────────────────────────────

async def _ws_safe_send(ws: web.WebSocketResponse, payload: dict) -> None:
    try:
        await ws.send_json(payload)
    except (ConnectionResetError, RuntimeError):
        pass


def _ws_should_deliver(state: WSClientState, event: dict) -> bool:
    et = event.get("type")
    sid = event.get("session_id")
    if et in ("output", "session_finished", "session_stopped"):
        return bool(sid and sid in state.sessions)
    if et == "session_created":
        return state.system
    return False


async def _ws_build_system_status_dict() -> dict:
    mem = await memory_info()
    disks = await disk_usage()
    proc_ld = await asyncio.create_subprocess_exec(
        "sysctl", "-n", "vm.loadavg",
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.DEVNULL,
    )
    stdout_ld, _ = await proc_ld.communicate()
    load = stdout_ld.decode(errors="replace").strip() if stdout_ld else ""
    docker_block: dict = {"available": docker_available()}
    if docker_block["available"]:
        try:
            docker_block["containers"] = await containers(False)
        except Exception:
            docker_block["containers"] = []
    return {
        "cpu": {"loadavg": load},
        "memory": mem,
        "disk": disks,
        "docker": docker_block,
    }


async def _ws_system_broadcast_loop(app: web.Application) -> None:
    try:
        while True:
            await asyncio.sleep(30)
            lock = app.get("ws_lock")
            if lock:
                async with lock:
                    clients = list(app.get("ws_clients", []))
            else:
                clients = list(app.get("ws_clients", []))
            if not any(c.system for c in clients):
                continue
            try:
                body = await _ws_build_system_status_dict()
            except Exception:
                log.exception("system metrics collection failed")
                continue
            msg = {"type": "system.metrics", "ts": int(time.time()), **body}
            for c in clients:
                if not c.system:
                    continue
                await _ws_safe_send(c.ws, msg)
    except asyncio.CancelledError:
        raise


async def _ws_startup(app: web.Application) -> None:
    app["ws_broadcast_task"] = asyncio.create_task(_ws_system_broadcast_loop(app))


async def _ws_cleanup(app: web.Application) -> None:
    t = app.pop("ws_broadcast_task", None)
    if t:
        t.cancel()
        try:
            await t
        except asyncio.CancelledError:
            pass


async def _ws_dispatch(ws: web.WebSocketResponse, state: WSClientState, data: dict) -> None:
    cmd = data.get("type")
    if not cmd:
        await _ws_safe_send(ws, {"type": "error", "message": "Missing type"})
        return

    if cmd == "ping":
        await _ws_safe_send(ws, {"type": "pong", "ts": int(time.time())})
        return

    if cmd == "subscribe":
        channel = data.get("channel", "")
        if channel == "system":
            state.system = True
            return
        if channel == "session":
            sid = data.get("session_id", "")
            if not sid:
                await _ws_safe_send(ws, {"type": "error", "message": "session_id required for session channel"})
                return
            if not session_mgr.get(sid):
                await _ws_safe_send(ws, {"type": "error", "message": "Session not found"})
                return
            if len(state.sessions) >= _WS_MAX_SESSION_SUBS:
                await _ws_safe_send(ws, {"type": "error", "message": "Too many subscriptions"})
                return
            state.sessions.add(sid)
            return
        await _ws_safe_send(ws, {"type": "error", "message": "Unknown channel"})
        return

    if cmd == "unsubscribe":
        channel = data.get("channel", "")
        if channel == "system":
            state.system = False
            return
        if channel == "session":
            sid = data.get("session_id", "")
            if not sid:
                await _ws_safe_send(ws, {"type": "error", "message": "session_id required for session channel"})
                return
            state.sessions.discard(sid)
            return
        await _ws_safe_send(ws, {"type": "error", "message": "Unknown channel"})
        return

    if cmd == "session.input":
        sid = data.get("session_id", "")
        text = data.get("text", "")
        if not sid:
            await _ws_safe_send(ws, {"type": "error", "message": "session_id required"})
            return
        if not isinstance(text, str):
            await _ws_safe_send(ws, {"type": "error", "message": "text must be a string"})
            return
        result = await session_mgr.write_stdin(sid, text)
        if result.get("error"):
            await _ws_safe_send(ws, {"type": "error", "message": result["error"]})
        return

    if cmd == "session.start":
        project_name = data.get("project", "")
        task = data.get("task", "")
        agent = data.get("agent", "claude")
        if not project_name:
            await _ws_safe_send(ws, {"type": "error", "message": "project required"})
            return
        project_dir = resolve_project(project_name)
        if not project_dir:
            await _ws_safe_send(ws, {"type": "error", "message": f"Project '{project_name}' not found"})
            return
        if len(state.sessions) >= _WS_MAX_SESSION_SUBS:
            await _ws_safe_send(ws, {"type": "error", "message": "Too many subscriptions"})
            return
        result = await session_mgr.create_session(project_name, project_dir, task, agent)
        if not result.get("ok"):
            await _ws_safe_send(ws, {"type": "error", "message": result.get("error", "Failed to start session")})
            return
        sid = result["session"]["id"]
        state.sessions.add(sid)
        await _ws_safe_send(ws, {"type": "session.started", "session_id": sid})
        return

    if cmd == "session.stop":
        sid = data.get("session_id", "")
        if not sid:
            await _ws_safe_send(ws, {"type": "error", "message": "session_id required"})
            return
        result = await session_mgr.stop_session(sid)
        if not result.get("ok"):
            await _ws_safe_send(ws, {"type": "error", "message": result.get("error", "Failed to stop session")})
        return

    if cmd == "session.list":
        sessions = [s.to_dict() for s in session_mgr.sessions]
        await _ws_safe_send(ws, {"type": "session.list", "sessions": sessions})
        return

    if cmd == "system.status":
        try:
            body = await _ws_build_system_status_dict()
        except Exception:
            log.exception("WebSocket system.status failed")
            await _ws_safe_send(ws, {"type": "error", "message": "Internal server error"})
            return
        await _ws_safe_send(ws, {"type": "system.status", **body})
        return

    if cmd == "exec":
        command = data.get("command", "")
        if not isinstance(command, str):
            await _ws_safe_send(ws, {"type": "error", "message": "Invalid command type"})
            return
        cwd_raw = data.get("cwd", "")
        if not command:
            await _ws_safe_send(ws, {"type": "error", "message": "command required"})
            return
        cwd_path, cwd_err = _resolve_exec_cwd(cwd_raw if isinstance(cwd_raw, str) else "")
        if cwd_err:
            await _ws_safe_send(ws, {"type": "error", "message": cwd_err})
            return
        result = await _execute_run_command(command, cwd_path)
        if "error" in result:
            await _ws_safe_send(ws, {
                "type": "exec.result",
                "stdout": result.get("error", ""),
                "exit_code": result.get("exit_code", -1),
            })
            return
        await _ws_safe_send(ws, {
            "type": "exec.result",
            "stdout": result["stdout"],
            "exit_code": result["exit_code"],
        })
        return

    await _ws_safe_send(ws, {"type": "error", "message": f"Unknown type: {cmd}"})


async def _ws_reader(ws: web.WebSocketResponse, state: WSClientState) -> None:
    async for msg in ws:
        if msg.type == aiohttp.WSMsgType.TEXT:
            try:
                data = json.loads(msg.data)
            except json.JSONDecodeError:
                await _ws_safe_send(ws, {"type": "error", "message": "Invalid JSON"})
                continue
            if not isinstance(data, dict):
                await _ws_safe_send(ws, {"type": "error", "message": "JSON object expected"})
                continue
            await _ws_dispatch(ws, state, data)
        elif msg.type in (aiohttp.WSMsgType.ERROR, aiohttp.WSMsgType.CLOSE):
            break


async def _ws_writer(ws: web.WebSocketResponse, state: WSClientState, queue: asyncio.Queue) -> None:
    while True:
        event = await queue.get()
        if not _ws_should_deliver(state, event):
            continue
        try:
            await ws.send_json(event)
        except (ConnectionResetError, RuntimeError):
            break


async def _ws_handshake_auth(ws: web.WebSocketResponse, request: web.Request) -> bool:
    query_token = request.rel_url.query.get("token", "").strip()
    if query_token and len(query_token) == len(AUTH_TOKEN) and hmac.compare_digest(
        query_token, AUTH_TOKEN
    ):
        return True

    msg = await ws.receive()
    if msg.type == aiohttp.WSMsgType.CLOSE:
        return False
    if msg.type != aiohttp.WSMsgType.TEXT:
        await _ws_safe_send(ws, {"type": "error", "message": "First message must be JSON auth"})
        await ws.close()
        return False
    try:
        data = json.loads(msg.data)
    except json.JSONDecodeError:
        await _ws_safe_send(ws, {"type": "error", "message": "Invalid JSON"})
        await ws.close()
        return False
    if not isinstance(data, dict) or data.get("type") != "auth":
        await _ws_safe_send(ws, {"type": "error", "message": "Unauthorized"})
        await ws.close()
        return False
    msg_token = data.get("token", "")
    if not isinstance(msg_token, str) or len(msg_token) != len(AUTH_TOKEN) or not hmac.compare_digest(
        msg_token, AUTH_TOKEN
    ):
        await _ws_safe_send(ws, {"type": "error", "message": "Unauthorized"})
        await ws.close()
        return False
    return True


async def handle_ws(request):
    ws = web.WebSocketResponse()
    await ws.prepare(request)
    app = request.app

    if not await _ws_handshake_auth(ws, request):
        return ws

    state = WSClientState(ws)
    async with app["ws_lock"]:
        if len(app["ws_clients"]) >= _WS_MAX_CLIENTS:
            await ws.close(code=1013, message=b"Too many connections")
            return ws
        app["ws_clients"].append(state)
    queue = await session_mgr.subscribe()

    sessions = [s.to_dict() for s in session_mgr.sessions]
    await ws.send_json({
        "type": "connected",
        "sessions": sessions,
        "running_count": session_mgr.running_count,
    })

    try:
        reader_task = asyncio.create_task(_ws_reader(ws, state))
        writer_task = asyncio.create_task(_ws_writer(ws, state, queue))
        _done, pending = await asyncio.wait(
            [reader_task, writer_task], return_when=asyncio.FIRST_COMPLETED
        )
        for t in pending:
            t.cancel()
            try:
                await t
            except asyncio.CancelledError:
                pass
    finally:
        async with app["ws_lock"]:
            try:
                app["ws_clients"].remove(state)
            except ValueError:
                pass
        await session_mgr.unsubscribe(queue)

    return ws


# ── Helpers ──────────────────────────────────────────────────────────────

def _active_dir() -> str:
    active = session_mgr.active_sessions
    if active:
        return active[-1].project_dir
    all_s = session_mgr.sessions
    if all_s:
        return all_s[-1].project_dir
    return ""


# ── App setup ────────────────────────────────────────────────────────────

def create_app() -> web.Application:
    app = web.Application(middlewares=[auth_middleware])
    app["ws_clients"] = []
    app["ws_lock"] = asyncio.Lock()
    app.on_startup.append(_ws_startup)
    app.on_cleanup.append(_ws_cleanup)

    # System
    app.router.add_get("/api/ping", handle_ping)
    app.router.add_get("/api/system", handle_system)

    # Projects
    app.router.add_get("/api/projects", handle_projects)

    # Files
    app.router.add_get("/api/files/tree", handle_file_tree)
    app.router.add_get("/api/files/read", handle_file_read)
    app.router.add_get("/api/browse/roots", handle_browse_roots)
    app.router.add_get("/api/browse", handle_browse)
    app.router.add_get("/api/files/abs", handle_file_read_abs)

    # Git
    app.router.add_get("/api/git/diff", handle_diff)
    app.router.add_post("/api/git/approve", handle_approve)
    app.router.add_post("/api/git/reject", handle_reject)
    app.router.add_get("/api/git/log", handle_git_log)

    # Sessions (multi-agent)
    app.router.add_get("/api/sessions", handle_sessions_list)
    app.router.add_post("/api/sessions", handle_session_create)
    app.router.add_get("/api/sessions/{id}", handle_session_detail)
    app.router.add_get("/api/sessions/{id}/output", handle_session_output)
    app.router.add_post("/api/sessions/{id}/stop", handle_session_stop)
    app.router.add_delete("/api/sessions/{id}", handle_session_delete)
    app.router.add_post("/api/sessions/{id}/ask", handle_session_ask)
    app.router.add_post("/api/sessions/{id}/send", handle_session_send)

    # Legacy single-task endpoints (backward compat)
    app.router.add_post("/api/task", handle_task_start)
    app.router.add_get("/api/task/status", handle_task_status)
    app.router.add_post("/api/task/stop", handle_task_stop)
    app.router.add_get("/api/task/output", handle_task_output)
    app.router.add_post("/api/ask", handle_ask)

    # Docker
    app.router.add_get("/api/docker/status", handle_docker_status)
    app.router.add_get("/api/docker/containers", handle_docker_containers)
    app.router.add_get("/api/docker/images", handle_docker_images)
    app.router.add_post("/api/docker/action", handle_docker_action)
    app.router.add_get("/api/docker/logs", handle_docker_logs)
    app.router.add_get("/api/docker/df", handle_docker_df)

    # System / Toolkit
    app.router.add_get("/api/system/disk", handle_disk)
    app.router.add_get("/api/system/memory", handle_memory)
    app.router.add_get("/api/system/processes", handle_processes)
    app.router.add_get("/api/system/network", handle_network)
    app.router.add_get("/api/system/services", handle_services)
    app.router.add_get("/api/system/brew", handle_brew_services)

    # Run
    app.router.add_post("/api/run", handle_run)

    # WebSocket
    app.router.add_get("/ws", handle_ws)

    # Docker Health Dashboard (API + web UI)
    register_docker_health_routes(app)

    # Static files for web dashboards
    static_dir = os.path.join(os.path.dirname(__file__), "static")
    if os.path.isdir(static_dir):
        app.router.add_static("/static", static_dir)

    return app


if __name__ == "__main__":
    print(f"\n  KMac Pilot Server")
    print(f"  ─────────────────")
    print(f"  URL:   http://{HOST}:{PORT}")
    print("  Token: loaded")
    print(f"  Agent: {active_agent()}")
    print()
    web.run_app(create_app(), host=HOST, port=PORT, print=None)
