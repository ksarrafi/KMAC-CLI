"""Web UI — lightweight HTTP dashboard for the KmacAgent daemon.

Serves a single-page dashboard at http://localhost:7891 (default; see WEB_PORT) showing
agent status, sessions, memories, tasks, and token usage.
Uses only Python's built-in http.server — no external dependencies.
"""

import asyncio
import json
import logging
import os
import threading
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path

log = logging.getLogger("kmac-agent")

WEB_PORT = int(os.environ.get("KMAC_AGENT_WEB_PORT", "7891"))
MAX_BODY_SIZE = 65536

_DAEMON_REF = None
_WEB_TOKEN = None


def set_daemon(daemon):
    global _DAEMON_REF
    _DAEMON_REF = daemon


def _init_web_token():
    """Generate and persist a bearer token for the dashboard API."""
    global _WEB_TOKEN
    from .config import AGENT_HOME
    import secrets
    token_file = AGENT_HOME / "web-token"
    if token_file.exists():
        _WEB_TOKEN = token_file.read_text().strip()
    if not _WEB_TOKEN:
        _WEB_TOKEN = secrets.token_urlsafe(32)
        token_file.write_text(_WEB_TOKEN)
        os.chmod(str(token_file), 0o600)
    return _WEB_TOKEN


_HTML = """\
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>KmacAgent</title>
<style>
*{margin:0;padding:0;box-sizing:border-box}
body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;
     background:#0d1117;color:#c9d1d9;padding:20px;max-width:1000px;margin:0 auto}
h1{color:#58a6ff;margin-bottom:20px;font-size:1.6rem}
h2{color:#8b949e;font-size:1.1rem;margin:18px 0 8px;border-bottom:1px solid #21262d;padding-bottom:4px}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(200px,1fr));gap:12px;margin-bottom:20px}
.card{background:#161b22;border:1px solid #30363d;border-radius:8px;padding:16px}
.card .label{font-size:.75rem;color:#8b949e;text-transform:uppercase;letter-spacing:.5px}
.card .value{font-size:1.8rem;font-weight:700;color:#58a6ff;margin-top:4px}
.card .value.green{color:#3fb950}
.card .value.yellow{color:#d29922}
table{width:100%;border-collapse:collapse;background:#161b22;border:1px solid #30363d;border-radius:8px;overflow:hidden}
th,td{padding:8px 12px;text-align:left;border-bottom:1px solid #21262d;font-size:.85rem}
th{background:#0d1117;color:#8b949e;font-weight:600;text-transform:uppercase;font-size:.7rem;letter-spacing:.5px}
td{color:#c9d1d9}
.status{display:inline-block;width:8px;height:8px;border-radius:50%;margin-right:6px}
.status.running{background:#3fb950}.status.queued{background:#d29922}
.status.completed{background:#58a6ff}.status.failed{background:#f85149}
.badge{display:inline-block;padding:2px 8px;border-radius:12px;font-size:.7rem;font-weight:600}
.badge.green{background:#0d2818;color:#3fb950}
.badge.yellow{background:#2d1f00;color:#d29922}
.footer{margin-top:24px;text-align:center;color:#484f58;font-size:.75rem}
#error{color:#f85149;margin:12px 0;display:none}
</style>
</head>
<body>
<h1>KmacAgent Dashboard</h1>
<div id="error"></div>
<div class="grid" id="status-cards"></div>
<h2>Agents</h2>
<div id="agents-table"></div>
<h2>Recent Tasks</h2>
<div id="tasks-table"></div>
<h2>Token Usage (30d)</h2>
<div id="usage-table"></div>
<div class="footer">KmacAgent · auto-refreshes every 10s</div>
<script>
const API = '';
const TOKEN = new URLSearchParams(location.search).get('token') || '';
async function fetchJSON(action, params={}) {
  const headers = {'Content-Type': 'application/json'};
  if (TOKEN) headers['Authorization'] = 'Bearer ' + TOKEN;
  const r = await fetch('/api', {
    method: 'POST',
    headers,
    body: JSON.stringify({action, ...params})
  });
  return r.json();
}
function card(label, value, cls='') {
  return `<div class="card"><div class="label">${label}</div><div class="value ${cls}">${value}</div></div>`;
}
async function refresh() {
  try {
    const s = await fetchJSON('status');
    const d = s.data || {};
    document.getElementById('status-cards').innerHTML = [
      card('Status', d.running ? '● Running' : '○ Stopped', d.running ? 'green' : ''),
      card('Uptime', d.uptime_human || '-'),
      card('Sessions', d.sessions || 0),
      card('Memories', d.memories || 0),
      card('Tasks', `${d.running_tasks||0} active`, d.running_tasks ? 'yellow' : ''),
      card('Tokens', d.total_tokens > 1000 ? (d.total_tokens/1000).toFixed(1)+'K' : (d.total_tokens||0)),
    ].join('');

    const ag = await fetchJSON('agents-list');
    const agents = (ag.data||{}).agents||[];
    if(agents.length){
      let h='<table><tr><th>Name</th><th>Model</th><th>Sessions</th><th>Memories</th></tr>';
      agents.forEach(a=>{
        const m=a.model||'?';
        h+=`<tr><td><strong>${a.name}</strong></td><td>${m}</td><td>${a.sessions||0}</td><td>${a.memories||0}</td></tr>`;
      });
      document.getElementById('agents-table').innerHTML=h+'</table>';
    } else {
      document.getElementById('agents-table').innerHTML='<p style="color:#484f58">No agents</p>';
    }

    const tk = await fetchJSON('tasks-list');
    const tasks = (tk.data||{}).tasks||[];
    if(tasks.length){
      let h='<table><tr><th>Status</th><th>Description</th><th>ID</th><th>Created</th></tr>';
      tasks.slice(0,20).forEach(t=>{
        h+=`<tr><td><span class="status ${t.status}"></span>${t.status}</td><td>${t.description.slice(0,60)}</td><td>${t.id}</td><td>${(t.created||'').slice(0,16)}</td></tr>`;
      });
      document.getElementById('tasks-table').innerHTML=h+'</table>';
    } else {
      document.getElementById('tasks-table').innerHTML='<p style="color:#484f58">No tasks</p>';
    }

    const u = await fetchJSON('token-usage');
    const usage = (u.data||{}).usage||[];
    if(usage.length){
      let h='<table><tr><th>Model</th><th>Input</th><th>Output</th><th>Calls</th></tr>';
      usage.forEach(r=>{
        h+=`<tr><td>${r.model}</td><td>${(r.inp||0).toLocaleString()}</td><td>${(r.out||0).toLocaleString()}</td><td>${r.calls||0}</td></tr>`;
      });
      document.getElementById('usage-table').innerHTML=h+'</table>';
    } else {
      document.getElementById('usage-table').innerHTML='<p style="color:#484f58">No usage data</p>';
    }

    document.getElementById('error').style.display='none';
  } catch(e) {
    document.getElementById('error').textContent='Failed to connect: '+e.message;
    document.getElementById('error').style.display='block';
  }
}
refresh();
setInterval(refresh, 10000);
</script>
</body>
</html>"""


class DashboardHandler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def do_GET(self):
        self.send_response(200)
        self.send_header("Content-Type", "text/html")
        self.end_headers()
        self.wfile.write(_HTML.encode())

    def _check_auth(self) -> bool:
        if not _WEB_TOKEN:
            return True
        auth = self.headers.get("Authorization", "")
        if auth == f"Bearer {_WEB_TOKEN}":
            return True
        token_param = ""
        if "?" in self.path:
            from urllib.parse import parse_qs, urlparse
            token_param = parse_qs(urlparse(self.path).query).get("token", [""])[0]
        if token_param == _WEB_TOKEN:
            return True
        return False

    def do_POST(self):
        if self.path != "/api":
            self.send_response(404)
            self.end_headers()
            return

        if not self._check_auth():
            self._json_response({"error": "Unauthorized"}, 401)
            return

        try:
            length = int(self.headers.get("Content-Length", 0))
        except (ValueError, TypeError):
            self._json_response({"error": "Bad Content-Length"}, 400)
            return
        if length > MAX_BODY_SIZE:
            self._json_response({"error": "Request too large"}, 413)
            return

        body = self.rfile.read(length)
        try:
            req = json.loads(body)
        except Exception:
            self._json_response({"error": "Invalid JSON"}, 400)
            return

        if not _DAEMON_REF:
            self._json_response({"error": "Daemon not available"}, 503)
            return

        action = req.get("action", "")
        try:
            result = self._dispatch_sync(action, req)
            self._json_response(result)
        except Exception as e:
            self._json_response({"error": str(e)}, 500)

    def _dispatch_sync(self, action, req):
        daemon = _DAEMON_REF
        agent = req.get("agent", "default")

        sync_handlers = {
            "status": lambda: daemon._status(),
            "agents-list": lambda: daemon._agents_list(),
            "tasks-list": lambda: daemon._tasks_list(agent),
            "token-usage": lambda: daemon._token_usage(agent),
            "sessions-list": lambda: daemon._sessions_list(agent),
            "memory-list": lambda: daemon._memory_list(agent),
        }

        handler = sync_handlers.get(action)
        if handler:
            result = handler()
            if result.get("type") == "result":
                return result.get("data", {})
            return result
        return {"error": f"Unknown action: {action}"}

    def _json_response(self, data, code=200):
        body = json.dumps(data).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)


def start_web_server(daemon, port=None):
    """Start the web dashboard in a background thread."""
    set_daemon(daemon)
    token = _init_web_token()
    actual_port = port or WEB_PORT
    try:
        server = HTTPServer(("127.0.0.1", actual_port), DashboardHandler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        log.info("Web dashboard started at http://127.0.0.1:%d?token=%s", actual_port, token[:8] + "...")
        return server
    except OSError as e:
        log.warning("Web dashboard failed to start on port %d: %s", actual_port, e)
        return None
