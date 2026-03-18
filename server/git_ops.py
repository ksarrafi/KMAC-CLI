"""Git operations for the active project."""

import subprocess
from typing import Optional


def _git(project_dir: str, *args, timeout: int = 10) -> tuple[int, str]:
    try:
        result = subprocess.run(
            ["git", "-C", project_dir, *args],
            capture_output=True, text=True, timeout=timeout,
        )
        return result.returncode, (result.stdout + result.stderr).strip()
    except subprocess.TimeoutExpired:
        return -1, "Command timed out"
    except Exception as e:
        return -1, str(e)


def diff_stat(project_dir: str) -> dict:
    rc, stat = _git(project_dir, "diff", "--stat")
    _, full = _git(project_dir, "diff")
    _, untracked = _git(project_dir, "ls-files", "--others", "--exclude-standard")

    files_changed = []
    for line in stat.splitlines():
        line = line.strip()
        if "|" in line:
            fname = line.split("|")[0].strip()
            files_changed.append(fname)

    return {
        "stat": stat,
        "full_diff": full[:50000],
        "untracked": untracked.splitlines() if untracked else [],
        "files_changed": files_changed,
        "has_changes": bool(stat or untracked),
    }


def approve(project_dir: str, message: str = "") -> dict:
    rc, porcelain = _git(project_dir, "status", "--porcelain")
    if not porcelain:
        return {"error": "Nothing to commit"}

    _git(project_dir, "add", "-A")
    msg = message or "KMac Pilot: approved changes"
    rc, output = _git(project_dir, "commit", "-m", msg)

    if rc != 0:
        return {"error": f"Commit failed: {output}"}

    _, short_hash = _git(project_dir, "log", "-1", "--format=%h")
    return {"ok": True, "hash": short_hash, "message": msg}


def reject(project_dir: str) -> dict:
    _git(project_dir, "checkout", "--", ".")
    _git(project_dir, "clean", "-fd")
    return {"ok": True}


def log_oneline(project_dir: str, count: int = 20) -> list[dict]:
    rc, output = _git(project_dir, "log", f"--oneline", f"-{count}", "--format=%h|%s|%ar")
    if rc != 0:
        return []
    results = []
    for line in output.splitlines():
        parts = line.split("|", 2)
        if len(parts) == 3:
            results.append({"hash": parts[0], "message": parts[1], "time": parts[2]})
    return results
