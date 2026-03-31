"""Extended tools — web, browser, image, and patch tools.

Zero external dependencies. Uses urllib, html.parser, and subprocess.
"""

import asyncio
import base64
import json
import logging
import os
import re
import urllib.request
import urllib.error
from html.parser import HTMLParser

log = logging.getLogger("kmac-agent")

# ── Tool Schemas ─────────────────────────────────────────────────

EXTENDED_TOOLS = [
    {
        "name": "web_search",
        "description": (
            "Search the web and return a list of results with titles, "
            "URLs, and snippets. Use for finding current information, "
            "documentation, or answers not in local files."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "query": {"type": "string", "description": "Search query"},
                "num_results": {
                    "type": "integer",
                    "description": "Max results (default: 5)",
                },
            },
            "required": ["query"],
        },
    },
    {
        "name": "web_fetch",
        "description": (
            "Fetch a URL and return its content as readable text. "
            "HTML is stripped to plain text. Use for reading documentation, "
            "articles, or API responses."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "url": {"type": "string", "description": "URL to fetch"},
                "max_chars": {
                    "type": "integer",
                    "description": "Max chars to return (default: 20000)",
                },
            },
            "required": ["url"],
        },
    },
    {
        "name": "browser",
        "description": (
            "Control a web browser. Actions: 'navigate' to a URL, "
            "'screenshot' the current page, 'get_text' to extract page text. "
            "Uses headless Chrome if available, falls back to macOS Safari."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "action": {
                    "type": "string",
                    "enum": ["navigate", "screenshot", "get_text"],
                    "description": "Browser action",
                },
                "url": {"type": "string", "description": "URL (for navigate)"},
                "output_path": {
                    "type": "string",
                    "description": "Screenshot save path (for screenshot)",
                },
            },
            "required": ["action"],
        },
    },
    {
        "name": "image",
        "description": (
            "Analyze an image file using AI vision. Provide a path to a "
            "local image (jpg, png, gif, webp) and a question about it."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "path": {"type": "string", "description": "Path to image file"},
                "question": {
                    "type": "string",
                    "description": "What to analyze (default: describe the image)",
                },
            },
            "required": ["path"],
        },
    },
    {
        "name": "image_generate",
        "description": (
            "Generate an image from a text description using DALL-E. "
            "Requires OPENAI_API_KEY. Returns the path to the saved image."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "prompt": {"type": "string", "description": "Image description"},
                "output_path": {
                    "type": "string",
                    "description": "Save path (default: /tmp/generated.png)",
                },
                "size": {
                    "type": "string",
                    "description": "Size: 1024x1024, 1792x1024, 1024x1792",
                },
            },
            "required": ["prompt"],
        },
    },
    {
        "name": "apply_patch",
        "description": (
            "Apply a unified diff patch to one or more files. "
            "Supports multi-hunk patches. The patch should be in standard "
            "unified diff format (like output of 'diff -u' or 'git diff')."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "patch": {
                    "type": "string",
                    "description": "Unified diff content",
                },
                "base_dir": {
                    "type": "string",
                    "description": "Base directory for relative paths (default: cwd)",
                },
            },
            "required": ["patch"],
        },
    },
]


# ── HTML Stripping ───────────────────────────────────────────────

class _TextExtractor(HTMLParser):
    def __init__(self):
        super().__init__()
        self._parts = []
        self._skip = False
        self._skip_tags = {"script", "style", "noscript", "svg", "head"}

    def handle_starttag(self, tag, attrs):
        if tag in self._skip_tags:
            self._skip = True
        if tag in ("p", "br", "div", "h1", "h2", "h3", "h4", "li", "tr"):
            self._parts.append("\n")

    def handle_endtag(self, tag):
        if tag in self._skip_tags:
            self._skip = False

    def handle_data(self, data):
        if not self._skip:
            self._parts.append(data)

    def get_text(self):
        text = " ".join(self._parts)
        text = re.sub(r'\n{3,}', '\n\n', text)
        text = re.sub(r' {2,}', ' ', text)
        return text.strip()


def _html_to_text(html: str) -> str:
    parser = _TextExtractor()
    try:
        parser.feed(html)
        return parser.get_text()
    except Exception:
        return re.sub(r'<[^>]+>', ' ', html).strip()


def _make_request(url: str, timeout: int = 15) -> str:
    req = urllib.request.Request(url, headers={
        "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) KmacAgent/1.0",
        "Accept": "text/html,application/xhtml+xml,application/json,text/plain",
    })
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        data = resp.read(500_000)
        charset = resp.headers.get_content_charset() or "utf-8"
        return data.decode(charset, errors="replace")


# ── Tool Implementations ─────────────────────────────────────────

async def execute(name: str, inp: dict, api_key: str = "") -> tuple[str, str]:
    """Execute an extended tool. Returns (result, preview)."""
    try:
        if name == "web_search":
            return await _web_search(inp)
        if name == "web_fetch":
            return await _web_fetch(inp)
        if name == "browser":
            return await _browser(inp)
        if name == "image":
            return await _image(inp, api_key)
        if name == "image_generate":
            return await _image_generate(inp)
        if name == "apply_patch":
            return _apply_patch(inp)
    except Exception as e:
        msg = f"Error ({name}): {e}"
        return msg, msg
    return f"Unknown extended tool: {name}", "unknown"


async def _web_search(inp) -> tuple[str, str]:
    query = inp["query"]
    num = min(inp.get("num_results", 5), 10)
    loop = asyncio.get_event_loop()

    def _search():
        encoded = urllib.request.quote(query)
        url = f"https://html.duckduckgo.com/html/?q={encoded}"
        req = urllib.request.Request(url, headers={
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)",
        })
        with urllib.request.urlopen(req, timeout=15) as resp:
            return resp.read(200_000).decode("utf-8", errors="replace")

    html = await loop.run_in_executor(None, _search)

    results = []
    pattern = re.compile(
        r'<a[^>]*class="result__a"[^>]*href="([^"]*)"[^>]*>(.*?)</a>'
        r'.*?<a[^>]*class="result__snippet"[^>]*>(.*?)</a>',
        re.DOTALL,
    )
    for match in pattern.finditer(html):
        if len(results) >= num:
            break
        href = match.group(1)
        title = re.sub(r'<[^>]+>', '', match.group(2)).strip()
        snippet = re.sub(r'<[^>]+>', '', match.group(3)).strip()
        if href.startswith("//duckduckgo.com/l/?"):
            url_match = re.search(r'uddg=([^&]+)', href)
            if url_match:
                href = urllib.request.unquote(url_match.group(1))
        if title and href:
            results.append({"title": title, "url": href, "snippet": snippet})

    if not results:
        link_pattern = re.compile(
            r'<a[^>]*class="result__a"[^>]*href="([^"]*)"[^>]*>(.*?)</a>',
            re.DOTALL,
        )
        for m in link_pattern.finditer(html):
            if len(results) >= num:
                break
            href = m.group(1)
            title = re.sub(r'<[^>]+>', '', m.group(2)).strip()
            if href.startswith("//duckduckgo.com/l/?"):
                url_match = re.search(r'uddg=([^&]+)', href)
                if url_match:
                    href = urllib.request.unquote(url_match.group(1))
            if title:
                results.append({"title": title, "url": href, "snippet": ""})

    if not results:
        return f"No results found for: {query}", "no results"

    text_parts = []
    for i, r in enumerate(results, 1):
        text_parts.append(f"{i}. {r['title']}\n   {r['url']}\n   {r['snippet']}")
    full = "\n\n".join(text_parts)
    preview = "\n".join(text_parts[:3])
    return full, preview


async def _web_fetch(inp) -> tuple[str, str]:
    url = inp["url"]
    max_chars = inp.get("max_chars", 20000)
    loop = asyncio.get_event_loop()

    def _fetch():
        return _make_request(url)

    raw = await loop.run_in_executor(None, _fetch)

    content_type = "text"
    if "<html" in raw[:500].lower() or "<head" in raw[:500].lower():
        content_type = "html"

    if content_type == "html":
        text = _html_to_text(raw)
    else:
        text = raw

    if len(text) > max_chars:
        text = text[:max_chars] + f"\n\n... (truncated at {max_chars} chars)"

    lines = text.split("\n")
    preview = "\n".join(lines[:15])
    if len(lines) > 15:
        preview += f"\n... ({len(lines) - 15} more lines)"
    return text, preview


async def _browser(inp) -> tuple[str, str]:
    action = inp["action"]
    url = inp.get("url", "")
    output_path = inp.get("output_path", "/tmp/kmac-screenshot.png")

    chrome = await _find_chrome()

    if action == "navigate":
        if not url:
            return "No URL provided", "no url"
        if chrome:
            return await _chrome_navigate(chrome, url)
        return await _osascript_navigate(url)

    if action == "screenshot":
        if chrome:
            target = url or "about:blank"
            return await _chrome_screenshot(chrome, target, output_path)
        return "Screenshot requires Chrome/Chromium", "no chrome"

    if action == "get_text":
        if not url:
            return "No URL provided for get_text", "no url"
        return await _web_fetch({"url": url, "max_chars": 30000})

    return f"Unknown browser action: {action}", "unknown action"


async def _find_chrome() -> str | None:
    for path in [
        "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
        "/Applications/Chromium.app/Contents/MacOS/Chromium",
        "google-chrome", "chromium", "chromium-browser",
    ]:
        proc = await asyncio.create_subprocess_shell(
            f'command -v "{path}" 2>/dev/null || test -x "{path}" && echo "{path}"',
            stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE,
        )
        stdout, _ = await proc.communicate()
        result = stdout.decode().strip()
        if result:
            return path if os.path.isabs(path) else result
    return None


async def _chrome_navigate(chrome: str, url: str) -> tuple[str, str]:
    cmd = f'"{chrome}" --headless --disable-gpu --dump-dom "{url}" 2>/dev/null'
    proc = await asyncio.create_subprocess_shell(
        cmd, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE,
    )
    stdout, _ = await asyncio.wait_for(proc.communicate(), timeout=30)
    html = stdout.decode("utf-8", errors="replace")
    text = _html_to_text(html)
    if len(text) > 20000:
        text = text[:20000] + "\n... (truncated)"
    preview = text[:500]
    return text, preview


async def _chrome_screenshot(chrome: str, url: str, path: str) -> tuple[str, str]:
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    cmd = (
        f'"{chrome}" --headless --disable-gpu --screenshot="{path}" '
        f'--window-size=1280,900 "{url}" 2>/dev/null'
    )
    proc = await asyncio.create_subprocess_shell(
        cmd, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE,
    )
    await asyncio.wait_for(proc.communicate(), timeout=30)
    if os.path.exists(path):
        size = os.path.getsize(path)
        return f"Screenshot saved: {path} ({size} bytes)", f"saved {path}"
    return "Screenshot failed", "failed"


async def _osascript_navigate(url: str) -> tuple[str, str]:
    script = f'''
    tell application "Safari"
        open location "{url}"
        delay 2
        set pageText to do JavaScript "document.body.innerText" in current tab of window 1
        return pageText
    end tell
    '''
    proc = await asyncio.create_subprocess_exec(
        "osascript", "-e", script,
        stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE,
    )
    stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=15)
    text = stdout.decode("utf-8", errors="replace").strip()
    if text:
        if len(text) > 20000:
            text = text[:20000] + "\n... (truncated)"
        return text, text[:500]
    err = stderr.decode().strip()
    return f"Safari navigation failed: {err or 'no output'}", "failed"


async def _image(inp, api_key: str) -> tuple[str, str]:
    path = inp["path"]
    question = inp.get("question", "Describe this image in detail.")

    if not os.path.exists(path):
        return f"Image not found: {path}", "not found"

    ext = os.path.splitext(path)[1].lower()
    media_types = {".jpg": "image/jpeg", ".jpeg": "image/jpeg",
                   ".png": "image/png", ".gif": "image/gif", ".webp": "image/webp"}
    media_type = media_types.get(ext, "image/png")

    with open(path, "rb") as f:
        data = base64.b64encode(f.read()).decode("ascii")

    if not api_key:
        from .runtime import get_api_key
        api_key = get_api_key()
    if not api_key:
        return "No API key for image analysis", "no key"

    body = json.dumps({
        "model": "claude-haiku-4-5",
        "max_tokens": 1024,
        "messages": [{
            "role": "user",
            "content": [
                {"type": "image", "source": {
                    "type": "base64", "media_type": media_type, "data": data,
                }},
                {"type": "text", "text": question},
            ],
        }],
    }).encode()

    req = urllib.request.Request(
        "https://api.anthropic.com/v1/messages", data=body,
        headers={
            "Content-Type": "application/json",
            "x-api-key": api_key,
            "anthropic-version": "2023-06-01",
        },
    )
    loop = asyncio.get_event_loop()

    def _call():
        with urllib.request.urlopen(req, timeout=30) as resp:
            return json.loads(resp.read())

    response = await loop.run_in_executor(None, _call)
    text = ""
    for block in response.get("content", []):
        if block.get("type") == "text":
            text += block["text"]
    if not text:
        err = response.get("error", {}).get("message", "unknown error")
        return f"Image analysis failed: {err}", "failed"
    return text, text[:300]


async def _image_generate(inp) -> tuple[str, str]:
    prompt = inp["prompt"]
    output = inp.get("output_path", "/tmp/kmac-generated.png")
    size = inp.get("size", "1024x1024")

    api_key = os.environ.get("OPENAI_API_KEY", "")
    if not api_key:
        return "No OPENAI_API_KEY set for image generation", "no key"

    body = json.dumps({
        "model": "dall-e-3",
        "prompt": prompt,
        "n": 1,
        "size": size,
        "response_format": "b64_json",
    }).encode()

    req = urllib.request.Request(
        "https://api.openai.com/v1/images/generations", data=body,
        headers={
            "Content-Type": "application/json",
            "Authorization": f"Bearer {api_key}",
        },
    )
    loop = asyncio.get_event_loop()

    def _call():
        with urllib.request.urlopen(req, timeout=60) as resp:
            return json.loads(resp.read())

    response = await loop.run_in_executor(None, _call)
    images = response.get("data", [])
    if not images:
        return "No image generated", "failed"

    b64 = images[0].get("b64_json", "")
    if not b64:
        url = images[0].get("url", "")
        if url:
            return f"Image URL: {url}", f"generated: {url[:60]}"
        return "No image data returned", "failed"

    os.makedirs(os.path.dirname(output) or ".", exist_ok=True)
    with open(output, "wb") as f:
        f.write(base64.b64decode(b64))

    revised = images[0].get("revised_prompt", prompt)
    msg = f"Image saved: {output}\nPrompt: {revised[:200]}"
    return msg, f"saved {output}"


def _apply_patch(inp) -> tuple[str, str]:
    patch_text = inp["patch"]
    base_dir = inp.get("base_dir", ".")

    files_patched = 0
    hunks_applied = 0
    errors = []

    current_file = None
    hunks: list[dict] = []

    for line in patch_text.split("\n"):
        if line.startswith("--- "):
            if current_file and hunks:
                ok, err = _apply_hunks(current_file, hunks, base_dir)
                if ok:
                    files_patched += 1
                    hunks_applied += ok
                if err:
                    errors.append(err)
            hunks = []

        elif line.startswith("+++ "):
            path = line[4:].strip()
            if path.startswith("b/"):
                path = path[2:]
            current_file = path

        elif line.startswith("@@ "):
            match = re.match(r'@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@', line)
            if match:
                hunks.append({
                    "old_start": int(match.group(1)),
                    "old_count": int(match.group(2) or 1),
                    "new_start": int(match.group(3)),
                    "new_count": int(match.group(4) or 1),
                    "lines": [],
                })

        elif hunks and (line.startswith("+") or line.startswith("-") or line.startswith(" ")):
            hunks[-1]["lines"].append(line)

    if current_file and hunks:
        ok, err = _apply_hunks(current_file, hunks, base_dir)
        if ok:
            files_patched += 1
            hunks_applied += ok
        if err:
            errors.append(err)

    if errors:
        msg = f"Patch partially applied: {files_patched} files, {hunks_applied} hunks\nErrors:\n" + "\n".join(errors)
    elif files_patched == 0:
        msg = "No files patched — could not parse the diff"
    else:
        msg = f"Patch applied: {files_patched} file(s), {hunks_applied} hunk(s)"
    return msg, msg


def _apply_hunks(filepath: str, hunks: list[dict], base_dir: str) -> tuple[int, str]:
    full_path = os.path.join(base_dir, filepath)
    if not os.path.exists(full_path):
        parent = os.path.dirname(full_path)
        if parent:
            os.makedirs(parent, exist_ok=True)
        with open(full_path, "w") as f:
            for hunk in hunks:
                for line in hunk["lines"]:
                    if line.startswith("+"):
                        f.write(line[1:] + "\n")
        return len(hunks), ""

    try:
        with open(full_path, "r") as f:
            original = f.readlines()
    except Exception as e:
        return 0, f"{filepath}: {e}"

    result = list(original)
    offset = 0
    applied = 0

    for hunk in hunks:
        start = hunk["old_start"] - 1 + offset
        old_lines = []
        new_lines = []
        for line in hunk["lines"]:
            if line.startswith("-"):
                old_lines.append(line[1:] + "\n" if not line[1:].endswith("\n") else line[1:] + "\n")
            elif line.startswith("+"):
                new_lines.append(line[1:] + "\n" if not line[1:].endswith("\n") else line[1:] + "\n")
            elif line.startswith(" "):
                old_lines.append(line[1:] + "\n" if not line[1:].endswith("\n") else line[1:] + "\n")
                new_lines.append(line[1:] + "\n" if not line[1:].endswith("\n") else line[1:] + "\n")

        end = start + len(old_lines)
        result[start:end] = new_lines
        offset += len(new_lines) - len(old_lines)
        applied += 1

    tmp = full_path + ".tmp"
    with open(tmp, "w") as f:
        f.writelines(result)
    os.replace(tmp, full_path)
    return applied, ""
