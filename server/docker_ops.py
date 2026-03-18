"""Docker management operations."""

import asyncio
import json
import re
import shutil


_SAFE_ID = re.compile(r"^[a-zA-Z0-9][a-zA-Z0-9_.\-]*$")


def docker_available() -> bool:
    return shutil.which("docker") is not None


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
        return "Command timed out", -1


def _parse_json_lines(output: str) -> list[dict]:
    result = []
    for line in output.strip().splitlines():
        if line.strip():
            try:
                result.append(json.loads(line))
            except json.JSONDecodeError:
                pass
    return result


async def containers(all_containers: bool = True) -> list[dict]:
    fmt = '{"id":"{{.ID}}","name":"{{.Names}}","image":"{{.Image}}","status":"{{.Status}}","state":"{{.State}}","ports":"{{.Ports}}"}'
    args = ["docker", "ps", "--format", fmt]
    if all_containers:
        args.insert(2, "-a")
    out, rc = await _run(args)
    return _parse_json_lines(out) if rc == 0 else []


async def images() -> list[dict]:
    fmt = '{"id":"{{.ID}}","repo":"{{.Repository}}","tag":"{{.Tag}}","size":"{{.Size}}","created":"{{.CreatedSince}}"}'
    out, rc = await _run(["docker", "images", "--format", fmt])
    return _parse_json_lines(out) if rc == 0 else []


async def container_action(container_id: str, action: str) -> dict:
    allowed = {"start", "stop", "restart", "pause", "unpause", "remove"}
    if action not in allowed:
        return {"error": f"Invalid action: {action}"}
    if not _SAFE_ID.match(container_id):
        return {"error": "Invalid container ID"}

    if action == "remove":
        args = ["docker", "rm", "-f", container_id]
    else:
        args = ["docker", action, container_id]
    out, rc = await _run(args)
    return {"ok": rc == 0, "output": out, "action": action, "container": container_id}


async def container_logs(container_id: str, tail: int = 100) -> dict:
    if not _SAFE_ID.match(container_id):
        return {"logs": "Invalid container ID", "container": container_id}
    out, rc = await _run(["docker", "logs", "--tail", str(tail), container_id], timeout=10)
    return {"logs": out, "container": container_id}


async def compose_services(project_dir: str) -> dict:
    out, rc = await _run(
        ["docker", "compose", "--project-directory", project_dir, "ps", "--format", "json"],
        timeout=10,
    )
    if rc != 0:
        out2, _ = await _run(["docker-compose", "-f", f"{project_dir}/docker-compose.yml", "ps"], timeout=10)
        return {"output": out2, "format": "text"}
    return {"services": _parse_json_lines(out)}


async def system_df() -> dict:
    out, rc = await _run(["docker", "system", "df", "--format", "json"])
    if rc != 0:
        out2, _ = await _run(["docker", "system", "df"])
        return {"output": out2}
    return {"usage": _parse_json_lines(out)}
