"""RAG — lightweight project-file indexer for smarter context injection.

No external dependencies. Uses file-path heuristics and grep to find
relevant files, then injects their content into the system prompt.

Not embedding-based — relies on keyword matching and file-structure awareness.
"""

import asyncio
import logging
import os
import subprocess
from pathlib import Path

log = logging.getLogger("kmac-agent")

IGNORED_DIRS = {
    ".git", "node_modules", "__pycache__", ".venv", "venv",
    ".tox", ".mypy_cache", ".pytest_cache", "dist", "build",
    ".next", ".nuxt", "vendor", "target", ".cache",
}

IGNORED_EXTENSIONS = {
    ".pyc", ".pyo", ".o", ".so", ".dylib", ".a",
    ".png", ".jpg", ".jpeg", ".gif", ".webp", ".ico",
    ".mp4", ".mp3", ".wav", ".zip", ".tar", ".gz",
    ".woff", ".woff2", ".ttf", ".eot",
    ".lock", ".min.js", ".min.css",
}

KEY_FILES = [
    "README.md", "Makefile", "Dockerfile", "docker-compose.yml",
    "package.json", "pyproject.toml", "Cargo.toml", "go.mod",
    "requirements.txt", "setup.py", "setup.cfg",
    ".env.example", "tsconfig.json", "webpack.config.js",
]


def index_project(root: str = ".", max_files: int = 200) -> list[dict]:
    """Build a lightweight file index for the project.

    Returns list of {path, size, type} dicts.
    """
    root = os.path.abspath(root)
    index = []

    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in IGNORED_DIRS]
        rel_dir = os.path.relpath(dirpath, root)
        if rel_dir == ".":
            rel_dir = ""

        for fname in sorted(filenames):
            if len(index) >= max_files:
                return index
            ext = os.path.splitext(fname)[1].lower()
            if ext in IGNORED_EXTENSIONS:
                continue
            if fname.startswith(".") and fname not in (".env.example",):
                continue

            rel_path = os.path.join(rel_dir, fname) if rel_dir else fname
            full_path = os.path.join(dirpath, fname)
            try:
                size = os.path.getsize(full_path)
            except OSError:
                continue

            if size > 500_000:
                continue

            ftype = _classify_file(fname, ext)
            index.append({"path": rel_path, "size": size, "type": ftype})

    return index


def _classify_file(name: str, ext: str) -> str:
    config_exts = {".json", ".yaml", ".yml", ".toml", ".ini", ".cfg", ".env"}
    doc_exts = {".md", ".rst", ".txt"}
    code_exts = {
        ".py", ".js", ".ts", ".tsx", ".jsx", ".go", ".rs",
        ".java", ".rb", ".sh", ".bash", ".zsh", ".c", ".cpp", ".h",
    }
    if ext in config_exts or name in ("Makefile", "Dockerfile"):
        return "config"
    if ext in doc_exts:
        return "doc"
    if ext in code_exts:
        return "code"
    return "other"


def find_relevant_files(query: str, index: list[dict], limit: int = 8) -> list[dict]:
    """Score and rank files by relevance to a query."""
    keywords = set(query.lower().split())
    scored = []

    for entry in index:
        path_lower = entry["path"].lower()
        score = 0

        for kw in keywords:
            if kw in path_lower:
                score += 3
            basename = os.path.basename(path_lower)
            if kw in basename:
                score += 2

        if os.path.basename(entry["path"]) in KEY_FILES:
            score += 1

        if entry["type"] == "config":
            score += 0.5

        if score > 0:
            scored.append((score, entry))

    scored.sort(key=lambda x: -x[0])
    return [e for _, e in scored[:limit]]


def build_rag_context(query: str, root: str = ".", max_chars: int = 8000) -> str:
    """Build a RAG context string for the system prompt.

    Indexes the project, finds relevant files, reads their content,
    and returns a formatted context block.
    """
    index = index_project(root)
    if not index:
        return ""

    relevant = find_relevant_files(query, index)
    if not relevant:
        tree = "\n".join(f"  {e['path']}" for e in index[:30])
        return f"\nProject structure ({len(index)} files):\n{tree}"

    parts = [f"\nProject has {len(index)} files. Relevant files for this query:"]
    chars_used = 0

    for entry in relevant:
        full_path = os.path.join(os.path.abspath(root), entry["path"])
        try:
            with open(full_path, "r", errors="replace") as f:
                content = f.read(max_chars - chars_used)
        except Exception:
            continue

        if not content.strip():
            continue

        if len(content) > 2000:
            content = content[:2000] + "\n... (truncated)"

        parts.append(f"\n--- {entry['path']} ---\n{content}")
        chars_used += len(content)

        if chars_used >= max_chars:
            break

    return "\n".join(parts)


async def grep_context(query: str, root: str = ".", max_lines: int = 30) -> str:
    """Use ripgrep/grep to find query-related content in the project."""
    keywords = query.split()[:3]
    if not keywords:
        return ""

    pattern = "|".join(keywords)
    rg_check = await asyncio.create_subprocess_shell(
        "command -v rg",
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    await rg_check.communicate()

    if rg_check.returncode == 0:
        cmd = f"rg -n --max-count 3 --no-heading -i '{pattern}' '{root}' 2>/dev/null | head -{max_lines}"
    else:
        cmd = f"grep -rn -i '{pattern}' '{root}' 2>/dev/null | head -{max_lines}"

    proc = await asyncio.create_subprocess_shell(
        cmd,
        stdout=asyncio.subprocess.PIPE,
        stderr=asyncio.subprocess.PIPE,
    )
    stdout, _ = await asyncio.wait_for(proc.communicate(), timeout=10)
    out = stdout.decode().strip()
    return f"\nGrep matches:\n{out}" if out else ""
