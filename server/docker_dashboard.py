"""Docker health monitoring — real-time stats, history, and alerts."""

import asyncio
import json
import os
import time
from collections import deque
from pathlib import Path

from aiohttp import web

# Thresholds
DISK_HEALTHY = 75
DISK_WARNING = 85
DISK_SEVERE = 90

MEM_WARNING = 75
MEM_CRITICAL = 90

CPU_HIGH = 80

# In-memory history (24h at ~1min intervals = ~1440 points)
_history: deque = deque(maxlen=1440)
_last_snapshot_ts: float = 0
_history_lock = asyncio.Lock()


def _docker_sock() -> str:
    for s in [
        os.path.expanduser("~/.docker/run/docker.sock"),
        "/var/run/docker.sock",
    ]:
        if os.path.exists(s):
            return s
    return ""


async def _run(args: list[str], timeout: int = 15) -> tuple[str, int]:
    proc = await asyncio.create_subprocess_exec(
        *args,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.STDOUT,
    )
    try:
        stdout, _ = await asyncio.wait_for(proc.communicate(), timeout=timeout)
        return stdout.decode("utf-8", errors="replace").strip(), proc.returncode or 0
    except asyncio.TimeoutError:
        proc.kill()
        await proc.wait()
        return "", -1


def _parse_json_lines(output: str) -> list[dict]:
    result = []
    for line in output.strip().splitlines():
        line = line.strip()
        if line:
            try:
                result.append(json.loads(line))
            except json.JSONDecodeError:
                pass
    return result


async def collect_health() -> dict:
    """Collect comprehensive Docker health data."""
    ts = time.time()

    # Host disk
    disk_info = {"pct": 0, "used": "?", "total": "?", "avail": "?", "status": "HEALTHY"}
    try:
        out, rc = await _run(["df", "-h", "/"])
        if rc == 0:
            lines = out.strip().splitlines()
            if len(lines) >= 2:
                parts = lines[-1].split()
                disk_info["total"] = parts[1] if len(parts) > 1 else "?"
                disk_info["used"] = parts[2] if len(parts) > 2 else "?"
                disk_info["avail"] = parts[3] if len(parts) > 3 else "?"
                pct_str = parts[4].rstrip("%") if len(parts) > 4 else "0"
                disk_info["pct"] = int(pct_str)
                pct = disk_info["pct"]
                if pct >= DISK_SEVERE:
                    disk_info["status"] = "CRITICAL"
                elif pct >= DISK_WARNING:
                    disk_info["status"] = "SEVERE"
                elif pct >= DISK_HEALTHY:
                    disk_info["status"] = "WARNING"
    except (ValueError, IndexError, OSError):
        pass

    # Container stats
    containers = []
    fmt = '{"name":"{{.Name}}","cpu":"{{.CPUPerc}}","mem_pct":"{{.MemPerc}}","mem_usage":"{{.MemUsage}}","net":"{{.NetIO}}","block":"{{.BlockIO}}","pids":"{{.PIDs}}"}'
    out, rc = await _run(["docker", "stats", "--no-stream", "--format", fmt])
    if rc == 0:
        for c in _parse_json_lines(out):
            cpu_str = c.get("cpu", "0%").rstrip("%")
            mem_str = c.get("mem_pct", "0%").rstrip("%")
            try:
                cpu_val = float(cpu_str)
            except ValueError:
                cpu_val = 0.0
            try:
                mem_val = float(mem_str)
            except ValueError:
                mem_val = 0.0
            c["cpu_val"] = cpu_val
            c["mem_val"] = mem_val
            containers.append(c)

    # Container details (health, ports, image, state)
    ps_fmt = '{"id":"{{.ID}}","name":"{{.Names}}","image":"{{.Image}}","status":"{{.Status}}","state":"{{.State}}","ports":"{{.Ports}}"}'
    out, rc = await _run(["docker", "ps", "-a", "--format", ps_fmt])
    ps_data = {}
    if rc == 0:
        for p in _parse_json_lines(out):
            ps_data[p.get("name", "")] = p

    # Merge ps data into stats
    for c in containers:
        name = c.get("name", "")
        ps = ps_data.get(name, {})
        c["image"] = ps.get("image", "")
        c["status"] = ps.get("status", "")
        c["state"] = ps.get("state", "")
        c["ports"] = ps.get("ports", "")
        c["id"] = ps.get("id", "")

    # Docker system df
    docker_disk = []
    out, rc = await _run(["docker", "system", "df", "--format", '{"type":"{{.Type}}","total":"{{.TotalCount}}","size":"{{.Size}}","reclaimable":"{{.Reclaimable}}"}'])
    if rc == 0:
        docker_disk = _parse_json_lines(out)

    # Stopped/exited containers
    out, rc = await _run(["docker", "ps", "-a", "-f", "status=exited", "--format", '{{.Names}}'])
    stopped_names = [n for n in out.strip().splitlines() if n.strip()] if rc == 0 else []

    # Build alerts
    alerts = []
    pct = disk_info["pct"]
    if pct >= DISK_SEVERE:
        alerts.append({"level": "CRITICAL", "message": f"Host disk at {pct}% — free space immediately", "type": "disk"})
    elif pct >= DISK_WARNING:
        alerts.append({"level": "SEVERE", "message": f"Host disk at {pct}% — cleanup recommended", "type": "disk"})
    elif pct >= DISK_HEALTHY:
        alerts.append({"level": "WARNING", "message": f"Host disk at {pct}% — monitor closely", "type": "disk"})

    for c in containers:
        if c["cpu_val"] > CPU_HIGH:
            alerts.append({"level": "WARNING", "message": f"High CPU: {c['name']} at {c['cpu_val']:.1f}%", "type": "cpu"})
        if c["mem_val"] > MEM_CRITICAL:
            alerts.append({"level": "CRITICAL", "message": f"OOM risk: {c['name']} memory at {c['mem_val']:.1f}%", "type": "memory"})
        elif c["mem_val"] > MEM_WARNING:
            alerts.append({"level": "WARNING", "message": f"High memory: {c['name']} at {c['mem_val']:.1f}%", "type": "memory"})

    if stopped_names:
        alerts.append({"level": "INFO", "message": f"{len(stopped_names)} stopped container(s): {', '.join(stopped_names[:5])}", "type": "containers"})

    # Running/stopped counts
    running = len([c for c in containers])
    stopped = len(stopped_names)

    result = {
        "timestamp": int(ts),
        "host_disk": disk_info,
        "docker": {
            "running": running,
            "stopped": stopped,
            "images": len(ps_data),
        },
        "containers": containers,
        "docker_disk": docker_disk,
        "alerts": alerts,
        "alert_count": len(alerts),
    }

    # Save to history
    global _last_snapshot_ts
    async with _history_lock:
        if ts - _last_snapshot_ts >= 60:
            _history.append({
                "ts": int(ts),
                "disk_pct": disk_info["pct"],
                "running": running,
                "alert_count": len(alerts),
                "avg_cpu": sum(c["cpu_val"] for c in containers) / max(len(containers), 1),
                "avg_mem": sum(c["mem_val"] for c in containers) / max(len(containers), 1),
            })
            _last_snapshot_ts = ts

    return result


async def get_history(minutes: int = 60) -> list[dict]:
    minutes = max(1, min(minutes, 1440))
    cutoff = time.time() - (minutes * 60)
    async with _history_lock:
        return [h for h in _history if h["ts"] > cutoff]


async def run_cleanup(cleanup_type: str) -> dict:
    """Run Docker cleanup operations."""
    allowed = {
        "containers": ["docker", "container", "prune", "-f"],
        "images": ["docker", "image", "prune", "-a", "-f"],
        "volumes": ["docker", "volume", "prune", "-f"],
        "cache": ["docker", "builder", "prune", "-f", "--filter", "until=168h"],
        "all": ["docker", "system", "prune", "-a", "--volumes", "-f"],
    }
    if cleanup_type not in allowed:
        return {"error": f"Invalid cleanup type: {cleanup_type}. Use: {', '.join(allowed.keys())}"}

    out, rc = await _run(allowed[cleanup_type], timeout=120)
    return {"ok": rc == 0, "output": out, "type": cleanup_type}


# ── API Handlers ─────────────────────────────────────────────────────────

async def handle_docker_health(request):
    """GET /api/docker/health — full health snapshot."""
    data = await collect_health()
    return web.json_response(data)


async def handle_docker_health_history(request):
    """GET /api/docker/history?minutes=60"""
    try:
        minutes = int(request.query.get("minutes", "60"))
    except ValueError:
        minutes = 60
    history = await get_history(minutes)
    return web.json_response({"history": history, "count": len(history)})


async def handle_docker_cleanup(request):
    """POST /api/docker/cleanup — run prune operations."""
    try:
        body = await request.json()
    except Exception:
        return web.json_response({"error": "Invalid JSON"}, status=400)
    cleanup_type = body.get("type", "")
    if not cleanup_type:
        return web.json_response({"error": "type required (containers|images|volumes|cache|all)"}, status=400)
    result = await run_cleanup(cleanup_type)
    return web.json_response(result, status=200 if result.get("ok") else 400)


async def handle_docker_dashboard(request):
    """GET /docker-dashboard — serve the HTML dashboard."""
    static_dir = Path(__file__).parent / "static"
    html_file = static_dir / "docker-dashboard.html"
    if not html_file.exists():
        return web.Response(text="Dashboard not found", status=404)
    return web.FileResponse(html_file)


def register_routes(app: web.Application):
    """Register all Docker health routes on the app."""
    app.router.add_get("/api/docker/health", handle_docker_health)
    app.router.add_get("/api/docker/history", handle_docker_health_history)
    app.router.add_post("/api/docker/cleanup", handle_docker_cleanup)
    app.router.add_get("/docker-dashboard", handle_docker_dashboard)
