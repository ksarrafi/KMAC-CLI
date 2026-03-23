"""System operations — expose toolkit-level commands over the API."""

import asyncio
import shutil


async def _run(cmd: list[str], timeout: int = 10) -> str:
    try:
        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.STDOUT,
        )
    except FileNotFoundError:
        return ""
    try:
        stdout, _ = await asyncio.wait_for(proc.communicate(), timeout=timeout)
        return stdout.decode("utf-8", errors="replace").strip()
    except asyncio.TimeoutError:
        proc.kill()
        await proc.wait()
        return ""


async def _run_returncode(argv: list[str], timeout: int = 10) -> int:
    """Run argv with stdout/stderr discarded; return process exit code."""
    try:
        proc = await asyncio.create_subprocess_exec(
            *argv,
            stdout=asyncio.subprocess.DEVNULL,
            stderr=asyncio.subprocess.DEVNULL,
        )
    except FileNotFoundError:
        return -1
    try:
        await asyncio.wait_for(proc.wait(), timeout=timeout)
    except asyncio.TimeoutError:
        proc.kill()
        await proc.wait()
        return -1
    return proc.returncode if proc.returncode is not None else -1


async def disk_usage() -> list[dict]:
    out = await _run(["df", "-h", "/", "/System/Volumes/Data"])
    disks = []
    for line in out.splitlines()[1:]:
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
    pages = await _run(["vm_stat"])
    total_raw = await _run(["sysctl", "-n", "hw.memsize"])
    total_gb = int(total_raw.strip()) / (1024**3) if total_raw.strip().isdigit() else 0

    pressure_full = await _run(["memory_pressure"])
    pressure = pressure_full.splitlines()[0] if pressure_full else ""

    return {
        "total_gb": round(total_gb, 1),
        "pressure": pressure,
        "raw": pages[:500],
    }


async def top_processes(count: int = 15) -> list[dict]:
    out = await _run(["ps", "aux", "-r"])
    procs = []
    lines = out.splitlines()
    for line in lines[1 : count + 1]:
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
    ip_local = ""
    for iface in ("en0", "en1"):
        out = await _run(["ipconfig", "getifaddr", iface], timeout=5)
        if out.strip():
            ip_local = out.strip()
            break

    ip_public = await _run(
        ["curl", "-s", "--max-time", "3", "https://ifconfig.me"],
        timeout=10,
    )

    ports_raw = await _run(["lsof", "-iTCP", "-sTCP:LISTEN", "-nP"], timeout=15)
    port_lines = ports_raw.splitlines()
    data_lines = port_lines[1:] if len(port_lines) > 1 else []
    tail_lines = data_lines[-20:] if len(data_lines) > 20 else data_lines

    listening = []
    for line in tail_lines:
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
    services = []

    rc = await _run_returncode(["docker", "info"], timeout=10)
    services.append({"name": "Docker", "status": "running" if rc == 0 else "stopped"})

    rc = await _run_returncode(["pg_isready", "-q"], timeout=5)
    services.append({"name": "PostgreSQL", "status": "running" if rc == 0 else "stopped"})

    out = await _run(["redis-cli", "ping"], timeout=5)
    services.append({
        "name": "Redis",
        "status": "running" if out.strip().upper() == "PONG" else "stopped",
    })

    rc = await _run_returncode(["pgrep", "-x", "nginx"], timeout=5)
    services.append({"name": "Nginx", "status": "running" if rc == 0 else "stopped"})

    rc = await _run_returncode(["pgrep", "-x", "node"], timeout=5)
    services.append({"name": "Node", "status": "running" if rc == 0 else "stopped"})

    rc = await _run_returncode(["pgrep", "-x", "python3"], timeout=5)
    services.append({"name": "Python", "status": "running" if rc == 0 else "stopped"})

    return services


async def homebrew_services() -> list[dict]:
    if not shutil.which("brew"):
        return []
    out = await _run(["brew", "services", "list"])
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
