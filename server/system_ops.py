"""System operations — expose toolkit-level commands over the API."""

import asyncio
import os
import shutil


async def _run(cmd: str, timeout: int = 10) -> str:
    proc = await asyncio.create_subprocess_shell(
        cmd,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.STDOUT,
    )
    try:
        stdout, _ = await asyncio.wait_for(proc.communicate(), timeout=timeout)
        return stdout.decode("utf-8", errors="replace").strip()
    except asyncio.TimeoutError:
        proc.kill()
        return ""


async def disk_usage() -> list[dict]:
    out = await _run("df -h / /System/Volumes/Data 2>/dev/null | tail -n +2")
    disks = []
    for line in out.splitlines():
        parts = line.split()
        if len(parts) >= 9:
            disks.append({
                "filesystem": parts[0],
                "size": parts[1],
                "used": parts[2],
                "available": parts[3],
                "percent": parts[4],
                "mount": parts[8],
            })
    return disks


async def memory_info() -> dict:
    pages = await _run("vm_stat")
    total_raw = await _run("sysctl -n hw.memsize")
    total_gb = int(total_raw.strip()) / (1024**3) if total_raw.strip().isdigit() else 0

    pressure = await _run("memory_pressure 2>/dev/null | head -1")

    return {
        "total_gb": round(total_gb, 1),
        "pressure": pressure,
        "raw": pages[:500],
    }


async def top_processes(count: int = 15) -> list[dict]:
    out = await _run(f"ps aux -r | head -n {count + 1}")
    procs = []
    lines = out.splitlines()
    for line in lines[1:]:
        parts = line.split(None, 10)
        if len(parts) >= 11:
            procs.append({
                "user": parts[0],
                "pid": parts[1],
                "cpu": parts[2],
                "mem": parts[3],
                "command": parts[10][:80],
            })
    return procs


async def network_info() -> dict:
    ip_local = await _run("ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null")
    ip_public = await _run("curl -s --max-time 3 ifconfig.me 2>/dev/null")
    ports = await _run("lsof -iTCP -sTCP:LISTEN -nP 2>/dev/null | tail -20")

    listening = []
    for line in ports.splitlines()[1:]:
        parts = line.split()
        if len(parts) >= 9:
            listening.append({
                "process": parts[0],
                "pid": parts[1],
                "address": parts[8],
            })

    return {
        "local_ip": ip_local,
        "public_ip": ip_public,
        "listening": listening,
    }


async def services_status() -> list[dict]:
    """Check common dev services."""
    checks = [
        ("Docker", "docker info > /dev/null 2>&1 && echo running || echo stopped"),
        ("PostgreSQL", "pg_isready -q 2>/dev/null && echo running || echo stopped"),
        ("Redis", "redis-cli ping 2>/dev/null | grep -q PONG && echo running || echo stopped"),
        ("Nginx", "pgrep -x nginx > /dev/null && echo running || echo stopped"),
        ("Node", "pgrep -x node > /dev/null && echo running || echo stopped"),
        ("Python", "pgrep -x python3 > /dev/null 2>&1 && echo running || echo stopped"),
    ]

    services = []
    for name, cmd in checks:
        status = await _run(cmd)
        services.append({"name": name, "status": status.strip()})
    return services


async def homebrew_services() -> list[dict]:
    if not shutil.which("brew"):
        return []
    out = await _run("brew services list 2>/dev/null")
    services = []
    for line in out.splitlines()[1:]:
        parts = line.split()
        if len(parts) >= 2:
            services.append({
                "name": parts[0],
                "status": parts[1],
                "user": parts[2] if len(parts) > 2 else "",
            })
    return services
