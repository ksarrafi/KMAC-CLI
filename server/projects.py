"""Project discovery and file browsing."""

import os
import subprocess
from pathlib import Path
from typing import Optional

from config import project_scan_dirs

SKIP_DIRS = {
    "node_modules", ".git", ".next", "__pycache__", ".venv",
    "venv", "dist", "build", ".turbo", ".cache", ".tox",
}
DEEP_SKIP_DIRS = SKIP_DIRS | {"Backup", "Archive", "backup"}
MAX_SCAN_DEPTH = 3


def _get_branch(project_path: str) -> str:
    try:
        return subprocess.check_output(
            ["git", "-C", project_path, "branch", "--show-current"],
            stderr=subprocess.DEVNULL, timeout=3,
        ).decode().strip() or None
    except Exception:
        return "detached"


def _deep_scan_git_repos(directory: Path, label: str, filter_term: str,
                         results: list[dict], seen: set[str]):
    """Find git repos up to 2 extra levels inside a non-git directory."""
    for depth_glob in ["*", "*/*"]:
        for child in sorted(directory.glob(depth_glob)):
            if not child.is_dir() or not (child / ".git").is_dir():
                continue
            child_str = str(child)
            if child_str in seen:
                continue
            if any(skip in child.parts for skip in DEEP_SKIP_DIRS):
                continue
            name = child.name
            if filter_term and filter_term.lower() not in name.lower():
                continue
            seen.add(child_str)
            results.append({
                "name": name,
                "path": child_str,
                "branch": _get_branch(child_str),
                "is_git": True,
                "group": label,
            })


def list_projects(filter_term: str = "") -> list[dict]:
    """List projects from configured scan dirs.

    Shows immediate children (git or not), plus discovers git repos up to
    2 extra levels inside non-git 'namespace' directories.
    Deduplicates by path when scan dirs overlap.
    """
    results: list[dict] = []
    seen: set[str] = set()

    for scan_dir in project_scan_dirs():
        label = scan_dir.replace(str(Path.home()), "~")
        try:
            children = sorted(Path(scan_dir).iterdir())
        except PermissionError:
            continue

        for child in children:
            if not child.is_dir():
                continue
            name = child.name
            if name.startswith(".") or name in SKIP_DIRS:
                continue

            child_str = str(child)
            if child_str in seen:
                continue
            seen.add(child_str)

            is_git = (child / ".git").is_dir()

            if filter_term and filter_term.lower() not in name.lower() and is_git:
                continue

            if is_git:
                results.append({
                    "name": name,
                    "path": child_str,
                    "branch": _get_branch(child_str),
                    "is_git": True,
                    "group": label,
                })
            else:
                if not filter_term or filter_term.lower() in name.lower():
                    results.append({
                        "name": name,
                        "path": child_str,
                        "branch": None,
                        "is_git": False,
                        "group": label,
                    })
                if name not in DEEP_SKIP_DIRS:
                    _deep_scan_git_repos(child, label, filter_term, results, seen)

    return results


def resolve_project(name: str) -> Optional[str]:
    if not name or '/' in name or '\\' in name or name == '..' or name.startswith('.'):
        return None

    # Fast path: direct child of a scan dir
    for scan_dir in project_scan_dirs():
        candidate = os.path.join(scan_dir, name)
        candidate_resolved = os.path.realpath(candidate)
        scan_resolved = os.path.realpath(scan_dir)
        if not candidate_resolved.startswith(scan_resolved + os.sep):
            continue
        if os.path.isdir(candidate_resolved):
            return candidate_resolved

    # Deep search: walk up to 3 levels for a matching directory
    for scan_dir in project_scan_dirs():
        scan_resolved = os.path.realpath(scan_dir)
        for root, dirs, _files in os.walk(scan_dir):
            depth = root.replace(scan_dir, "").count(os.sep)
            if depth >= MAX_SCAN_DEPTH:
                dirs.clear()
                continue
            dirs[:] = [
                d for d in dirs
                if d not in DEEP_SKIP_DIRS and not d.startswith(".")
            ]
            if name in dirs:
                candidate = os.path.join(root, name)
                candidate_resolved = os.path.realpath(candidate)
                if not candidate_resolved.startswith(scan_resolved + os.sep):
                    continue
                return candidate_resolved
    return None


def file_tree(base_dir: str, sub_path: str = "", max_depth: int = 3) -> list[dict]:
    base = Path(base_dir).resolve()
    root = (base / sub_path).resolve() if sub_path else base
    if not root.is_dir():
        return []
    try:
        root.relative_to(base)
    except ValueError:
        return []
    return _walk(root, root, 0, max_depth)


def _walk(current: Path, root: Path, depth: int, max_depth: int) -> list[dict]:
    if depth >= max_depth:
        return []
    items = []
    try:
        entries = sorted(current.iterdir(), key=lambda p: (not p.is_dir(), p.name.lower()))
    except PermissionError:
        return []

    for entry in entries:
        name = entry.name
        if name in SKIP_DIRS or name.startswith("."):
            continue
        rel = str(entry.relative_to(root))
        if entry.is_dir():
            children = _walk(entry, root, depth + 1, max_depth)
            items.append({"name": name, "path": rel, "type": "dir", "children": children})
        else:
            size = entry.stat().st_size
            items.append({"name": name, "path": rel, "type": "file", "size": size})
    return items


def browse_directory(dir_path: str) -> dict:
    """List contents of a single directory. Returns folders and files, one level."""
    p = Path(dir_path).resolve()
    if not p.is_dir():
        return {"error": "Not a directory", "path": dir_path}

    # Security: must be under home directory
    try:
        p.relative_to(Path.home().resolve())
    except ValueError:
        return {"error": "Access denied"}

    items = []
    try:
        entries = sorted(p.iterdir(), key=lambda e: (not e.is_dir(), e.name.lower()))
    except PermissionError:
        return {"error": "Permission denied", "path": dir_path}

    for entry in entries:
        name = entry.name
        if name.startswith("."):
            continue

        if entry.is_dir():
            if name in SKIP_DIRS:
                continue
            is_git = (entry / ".git").is_dir()
            item = {"name": name, "path": str(entry), "type": "dir", "is_git": is_git}
            if is_git:
                item["branch"] = _get_branch(str(entry))
            items.append(item)
        else:
            try:
                size = entry.stat().st_size
            except OSError:
                size = 0
            items.append({"name": name, "path": str(entry), "type": "file", "size": size})

    parent_path = p.parent
    parent = str(parent_path)
    # Don't allow navigating above home
    try:
        parent_path.relative_to(Path.home().resolve())
        can_go_up = True
    except ValueError:
        can_go_up = False

    is_git = (p / ".git").is_dir()
    result = {
        "path": str(p),
        "label": str(p).replace(str(Path.home()), "~"),
        "parent": parent if can_go_up else None,
        "items": items,
        "is_git": is_git,
    }
    if is_git:
        result["branch"] = _get_branch(str(p))
        result["project_name"] = p.name
    return result


def get_browse_roots() -> list[dict]:
    """Return the top-level scan directories as browsable roots."""
    roots = []
    for scan_dir in project_scan_dirs():
        label = scan_dir.replace(str(Path.home()), "~")
        roots.append({"path": scan_dir, "label": label})
    return roots


def read_file(base_dir: str, file_path: str) -> dict:
    full = Path(base_dir) / file_path
    if not full.exists():
        return {"error": "File not found"}
    if not full.is_file():
        return {"error": "Not a file"}

    # Prevent path traversal
    try:
        full.resolve().relative_to(Path(base_dir).resolve())
    except ValueError:
        return {"error": "Access denied"}

    size = full.stat().st_size
    if size > 500_000:
        return {"error": f"File too large ({size} bytes)", "size": size}

    try:
        content = full.read_text(errors="replace")
    except Exception:
        return {"error": "Failed to read file"}

    return {
        "path": file_path,
        "content": content,
        "size": size,
        "extension": full.suffix.lstrip("."),
    }
