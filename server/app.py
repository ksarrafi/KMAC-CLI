#!/usr/bin/env python3
"""KMac Pilot Server — REST API + WebSocket for remote AI agent control."""

import asyncio
import json
import os
import platform
import re
import shlex
import time

import aiohttp
from aiohttp import web

from config import HOST, PORT, get_or_create_token, load_config, active_agent
from session_manager import SessionManager
from projects import list_projects, resolve_project, file_tree, read_file, browse_directory, get_browse_roots
from git_ops import diff_stat, approve, reject, log_oneline
from docker_ops import docker_available, containers, images, container_action, container_logs, system_df
from docker_dashboard import register_routes as register_docker_health_routes
from system_ops import disk_usage, memory_info, top_processes, network_info, services_status, homebrew_services

session_mgr = SessionManager()
AUTH_TOKEN = get_or_create_token()

# ── Auth middleware ───────────────────────────────────────────────────────

@web.middleware
async def auth_middleware(request: web.Request, handler):
    if request.path in ("/api/ping", "/ws", "/docker-dashboard") or request.path.startswith("/static/"):
        return await handler(request)

    token = request.headers.get("Authorization", "").removeprefix("Bearer ").strip()
    if not token or token != AUTH_TOKEN:
        return web.json_response({"error": "Unauthorized"}, status=401)
    return await handler(request)


def json_ok(data: dict, status: int = 200) -> web.Response:
    return web.json_response(data, status=status)


# ── System ───────────────────────────────────────────────────────────────

async def handle_ping(_request):
    return json_ok({"ok": True, "ts": int(time.time())})


async def handle_system(_request):
    proc_up = await asyncio.create_subprocess_shell(
        "uptime | sed 's/.*up /up /' | sed 's/,.*//'",
        stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL,
    )
    stdout_up, _ = await proc_up.communicate()
    uptime = stdout_up.decode().strip() if stdout_up else "?"

    proc_ld = await asyncio.create_subprocess_shell(
        "sysctl -n vm.loadavg 2>/dev/null",
        stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.DEVNULL,
    )
    stdout_ld, _ = await proc_ld.communicate()
    load = stdout_ld.decode().split() if stdout_ld else []
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
    fp = P(file_path)
    try:
        fp.resolve().relative_to(P.home().resolve())
    except ValueError:
        return json_ok({"error": "Access denied"}, 403)

    if not fp.is_file():
        return json_ok({"error": "File not found"}, 404)

    size = fp.stat().st_size
    if size > 500_000:
        return json_ok({"error": f"File too large ({size} bytes)"}, 413)

    try:
        content = fp.read_text(errors="replace")
    except Exception as e:
        return json_ok({"error": str(e)}, 500)

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
    lines = session.output_lines[-tail:]
    return json_ok({"lines": lines, "total": len(session.output_lines), "session_id": sid})


async def handle_session_stop(request):
    sid = request.match_info["id"]
    result = await session_mgr.stop_session(sid)
    return json_ok(result, 200 if result.get("ok") else 400)


async def handle_session_delete(request):
    sid = request.match_info["id"]
    result = session_mgr.remove_session(sid)
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

_ALLOWED_PREFIXES = (
    "ls", "cat", "head", "tail", "wc", "grep", "rg", "find", "file",
    "git", "npm", "yarn", "pnpm", "bun", "node", "python", "python3",
    "pip", "pip3", "cargo", "go", "make", "swift", "xcodebuild",
    "echo", "env", "printenv", "which", "whoami", "date", "uptime",
    "df", "du", "pwd", "tree", "sort", "uniq", "awk", "sed", "cut",
    "docker", "brew", "pod", "flutter", "ruby", "gem", "bundler",
)


async def handle_run(request):
    try:
        body = await request.json()
    except Exception:
        return json_ok({"error": "Invalid JSON body"}, 400)
    cmd = body.get("command", "")
    project = body.get("project", "")

    if not cmd:
        return json_ok({"error": "command required"}, 400)

    for pat in _BLOCKED_PATTERNS:
        if pat.search(cmd):
            return json_ok({"error": "Blocked: potentially destructive command"}, 403)

    try:
        first_token = shlex.split(cmd)[0]
    except ValueError:
        return json_ok({"error": "Malformed command"}, 400)

    if first_token not in _ALLOWED_PREFIXES:
        return json_ok({"error": f"Command not allowed: {first_token}"}, 403)

    project_dir = resolve_project(project) if project else _active_dir()
    if not project_dir:
        return json_ok({"error": "No project context"}, 400)

    try:
        proc = await asyncio.create_subprocess_exec(
            *shlex.split(cmd),
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.STDOUT,
            cwd=project_dir,
        )
        stdout, _ = await asyncio.wait_for(proc.communicate(), timeout=30)
        output = stdout.decode("utf-8", errors="replace") if stdout else ""
        return json_ok({"output": output, "exit_code": proc.returncode})
    except asyncio.TimeoutError:
        if proc:
            proc.kill()
        return json_ok({"error": "Command timed out (30s)", "exit_code": -1}, 408)
    except FileNotFoundError:
        return json_ok({"error": f"Command not found: {first_token}", "exit_code": -1}, 400)


# ── WebSocket ────────────────────────────────────────────────────────────

async def handle_ws(request):
    # Auth check for WebSocket
    token = request.query.get("token", "")
    if token != AUTH_TOKEN:
        return web.Response(status=401, text="Unauthorized")

    ws = web.WebSocketResponse()
    await ws.prepare(request)

    queue = session_mgr.subscribe()

    # Send current state on connect
    sessions = [s.to_dict() for s in session_mgr.sessions]
    await ws.send_json({
        "type": "connected",
        "sessions": sessions,
        "running_count": session_mgr.running_count,
    })

    try:
        reader_task = asyncio.create_task(_ws_reader(ws))
        writer_task = asyncio.create_task(_ws_writer(ws, queue))
        done, pending = await asyncio.wait(
            [reader_task, writer_task], return_when=asyncio.FIRST_COMPLETED
        )
        for t in pending:
            t.cancel()
    finally:
        session_mgr.unsubscribe(queue)

    return ws


async def _ws_reader(ws: web.WebSocketResponse):
    async for msg in ws:
        if msg.type == aiohttp.WSMsgType.TEXT:
            pass  # future: handle client commands over WS
        elif msg.type in (aiohttp.WSMsgType.ERROR, aiohttp.WSMsgType.CLOSE):
            break


async def _ws_writer(ws: web.WebSocketResponse, queue: asyncio.Queue):
    while True:
        event = await queue.get()
        try:
            await ws.send_json(event)
        except (ConnectionResetError, RuntimeError):
            break


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
    print(f"  Token: {AUTH_TOKEN[:8]}…")
    print(f"  Agent: {active_agent()}")
    print()
    web.run_app(create_app(), host=None, port=PORT, print=None)
