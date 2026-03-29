import express, { type Request, type Response } from "express";
import type { OrchestratorConfig } from "./types.js";
import { AgentRegistry } from "./agents/registry.js";
import { TaskStore } from "./tasks.js";
import { CostTracker, estimateUsd } from "./costs.js";
import { ApprovalStore } from "./approvals.js";
import { HeartbeatMonitor } from "./heartbeat.js";

export class OrchestratorServer {
  private app: ReturnType<typeof express>;
  private config: OrchestratorConfig;
  private registry: AgentRegistry;
  private tasks: TaskStore;
  private costs: CostTracker;
  private approvals: ApprovalStore;
  private heartbeats: HeartbeatMonitor;
  private server: ReturnType<typeof express.prototype.listen> | null = null;

  constructor(config: OrchestratorConfig) {
    this.config = config;
    this.app = express();
    this.app.use(express.json());

    this.registry = new AgentRegistry(config.defaults.heartbeatTimeoutSec);
    this.tasks = new TaskStore(config.dataDir);
    this.costs = new CostTracker(config.dataDir);
    this.approvals = new ApprovalStore(config.dataDir);
    this.heartbeats = new HeartbeatMonitor(
      this.registry,
      this.tasks,
      30,
      (agentId, event) => {
        console.log(`[heartbeat] agent=${agentId} event=${event}`);
      },
    );

    this.registerRoutes();
  }

  private registerRoutes(): void {
    const { app } = this;

    // ─── Landing page ─────────────────────────────────────────────
    app.get("/", (_req: Request, res: Response) => {
      const uptime = Math.floor(process.uptime());
      const h = Math.floor(uptime / 3600);
      const m = Math.floor((uptime % 3600) / 60);
      const agents = this.registry.list();
      const stats = this.tasks.stats();
      const costSummary = this.costs.summary();
      const pending = this.approvals.listPending().length;

      const agentRows = agents.map((a) => {
        const s = a.state;
        const color = s.status === "idle" ? "#3fb950" : s.status === "busy" ? "#d29922" : "#484f58";
        return `<tr><td><span style="color:${color}">&bull;</span> ${a.config.name}</td><td>${a.config.type}</td><td>${s.status}</td><td>${s.totalTasks}</td><td>$${s.totalCostUsd.toFixed(4)}</td></tr>`;
      }).join("");

      res.setHeader("Content-Type", "text/html");
      res.send(`<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>KMac Orchestrator</title>
  <style>
    *{margin:0;padding:0;box-sizing:border-box}
    body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;background:#0d1117;color:#e6edf3;min-height:100vh;display:flex;align-items:center;justify-content:center}
    .card{background:#161b22;border:1px solid #30363d;border-radius:12px;padding:40px;max-width:620px;width:100%}
    h1{font-size:1.6rem;margin-bottom:4px;color:#f0883e}
    .sub{color:#8b949e;margin-bottom:24px;font-size:.9rem}
    .status{display:flex;align-items:center;gap:8px;margin-bottom:20px;font-size:.95rem}
    .dot{width:10px;height:10px;border-radius:50%;background:#3fb950;display:inline-block}
    .grid{display:grid;grid-template-columns:1fr 1fr 1fr;gap:12px;margin-bottom:24px}
    .stat{background:#0d1117;border:1px solid #21262d;border-radius:8px;padding:12px 16px}
    .stat-label{color:#8b949e;font-size:.75rem;text-transform:uppercase;letter-spacing:.5px}
    .stat-value{font-size:1.3rem;font-weight:600;margin-top:2px}
    h2{font-size:.85rem;color:#8b949e;text-transform:uppercase;letter-spacing:.5px;margin:20px 0 12px}
    table{width:100%;border-collapse:collapse;font-size:.85rem}
    th{text-align:left;color:#8b949e;font-weight:500;padding:6px 8px;border-bottom:1px solid #21262d;font-size:.75rem;text-transform:uppercase}
    td{padding:6px 8px;border-bottom:1px solid #21262d}
    .endpoints{list-style:none}
    .endpoints li{padding:6px 0;border-bottom:1px solid #21262d;font-size:.85rem;display:flex;justify-content:space-between}
    .endpoints li:last-child{border:none}
    .method{background:#238636;color:#fff;padding:2px 6px;border-radius:4px;font-size:.7rem;font-weight:600}
    code{color:#79c0ff;font-size:.82rem}
    .footer{color:#484f58;font-size:.75rem;margin-top:20px;text-align:center}
    .warn{color:#d29922}
  </style>
</head>
<body>
  <div class="card">
    <h1>KMac Orchestrator</h1>
    <p class="sub">Multi-agent task management, cost tracking, and governance</p>
    <div class="status"><span class="dot"></span> Running &mdash; ${h}h ${m}m uptime</div>
    <div class="grid">
      <div class="stat"><div class="stat-label">Agents</div><div class="stat-value">${agents.length}</div></div>
      <div class="stat"><div class="stat-label">Tasks</div><div class="stat-value">${stats.total}</div></div>
      <div class="stat"><div class="stat-label">Cost (24h)</div><div class="stat-value">$${costSummary.last24hUsd.toFixed(2)}</div></div>
    </div>
    ${pending > 0 ? `<p class="warn" style="margin-bottom:16px">&#9888; ${pending} approval(s) pending review</p>` : ""}
    <h2>Agents</h2>
    <table><thead><tr><th>Name</th><th>Type</th><th>Status</th><th>Tasks</th><th>Cost</th></tr></thead><tbody>${agentRows}</tbody></table>
    <h2>API Endpoints</h2>
    <ul class="endpoints">
      <li><span><span class="method">GET</span> <code>/api/dashboard</code></span><span style="color:#8b949e">Full dashboard</span></li>
      <li><span><span class="method">GET</span> <code>/api/agents</code></span><span style="color:#8b949e">List agents</span></li>
      <li><span><span class="method">GET</span> <code>/api/tasks</code></span><span style="color:#8b949e">List tasks</span></li>
      <li><span><span class="method">POST</span> <code>/api/tasks</code></span><span style="color:#8b949e">Create task</span></li>
      <li><span><span class="method">POST</span> <code>/api/tasks/:id/dispatch</code></span><span style="color:#8b949e">Dispatch task</span></li>
      <li><span><span class="method">GET</span> <code>/api/costs</code></span><span style="color:#8b949e">Cost report</span></li>
      <li><span><span class="method">GET</span> <code>/api/approvals/pending</code></span><span style="color:#8b949e">Pending approvals</span></li>
    </ul>
    <div class="footer">KMac CLI &bull; <code>kmac orchestrator dashboard</code></div>
  </div>
</body>
</html>`);
    });

    // Chrome DevTools probe
    app.get("/.well-known/*splat", (_req: Request, res: Response) => {
      res.status(204).end();
    });

    // ─── Health ─────────────────────────────────────────────────────
    app.get("/health", (_req: Request, res: Response) => {
      const stats = this.tasks.stats();
      const agents = this.registry.list().map((a) => ({
        id: a.config.id,
        name: a.config.name,
        type: a.config.type,
        status: a.state.status,
      }));
      res.json({
        status: "ok",
        uptime: process.uptime(),
        agents: agents.length,
        tasks: stats,
      });
    });

    // ─── Dashboard (summary of everything) ─────────────────────────
    app.get("/api/dashboard", async (_req: Request, res: Response) => {
      const agents = this.registry.list().map((a) => ({
        ...a.config,
        state: a.state,
      }));
      const taskStats = this.tasks.stats();
      const recentTasks = this.tasks.list().slice(0, 10);
      const costSummary = this.costs.summary();
      const pendingApprovals = this.approvals.listPending();

      res.json({
        agents,
        tasks: { stats: taskStats, recent: recentTasks },
        costs: costSummary,
        approvals: { pending: pendingApprovals.length, items: pendingApprovals },
      });
    });

    // ─── Agents ─────────────────────────────────────────────────────
    app.get("/api/agents", (_req: Request, res: Response) => {
      const agents = this.registry.list().map((a) => ({
        id: a.config.id,
        name: a.config.name,
        type: a.config.type,
        enabled: a.config.enabled,
        state: a.state,
      }));
      res.json(agents);
    });

    app.get("/api/agents/:id", (req: Request, res: Response) => {
      const agent = this.registry.get(req.params.id as string);
      if (!agent) { res.status(404).json({ error: "Agent not found" }); return; }
      res.json({ ...agent.config, state: agent.state });
    });

    app.post("/api/agents/:id/ping", async (req: Request, res: Response) => {
      const agent = this.registry.get(req.params.id as string);
      if (!agent) { res.status(404).json({ error: "Agent not found" }); return; }
      const ok = await agent.adapter.ping();
      this.registry.setStatus(agent.config.id, ok ? "idle" : "offline");
      res.json({ agentId: agent.config.id, reachable: ok });
    });

    app.post("/api/agents/ping-all", async (_req: Request, res: Response) => {
      const results = await this.heartbeats.sweep();
      res.json(results);
    });

    // ─── Tasks ──────────────────────────────────────────────────────
    app.get("/api/tasks", (req: Request, res: Response) => {
      const status = req.query.status as string | undefined;
      const agentId = req.query.agent as string | undefined;
      const tag = req.query.tag as string | undefined;
      res.json(this.tasks.list({ status: status as any, agentId, tag }));
    });

    app.get("/api/tasks/:id", (req: Request, res: Response) => {
      const task = this.tasks.get(req.params.id as string);
      if (!task) { res.status(404).json({ error: "Task not found" }); return; }
      res.json(task);
    });

    app.get("/api/tasks/:id/logs", (req: Request, res: Response) => {
      const logs = this.tasks.getLogs(req.params.id as string);
      res.json({ taskId: req.params.id, logs });
    });

    app.post("/api/tasks", (req: Request, res: Response) => {
      const { title, description, priority, projectDir, approvalRequired, tags, parentTaskId } = req.body;
      if (!title) { res.status(400).json({ error: "title is required" }); return; }
      const task = this.tasks.create({
        title,
        description,
        priority,
        projectDir,
        approvalRequired: approvalRequired ?? this.config.defaults.approvalRequired,
        tags,
        parentTaskId,
      });
      res.status(201).json(task);
    });

    app.post("/api/tasks/:id/assign", (req: Request, res: Response) => {
      const { agentId } = req.body;
      if (!agentId) { res.status(400).json({ error: "agentId is required" }); return; }
      const task = this.tasks.assign(req.params.id as string, agentId);
      if (!task) { res.status(404).json({ error: "Task not found" }); return; }
      res.json(task);
    });

    app.post("/api/tasks/:id/dispatch", async (req: Request, res: Response) => {
      const taskId = req.params.id as string;
      const { agentId } = req.body || {};

      if (this.costs.isOverBudget(this.config.defaults.costLimitDailyUsd)) {
        res.status(429).json({ error: "Daily cost limit reached" });
        return;
      }

      const task = await this.tasks.dispatch(taskId, this.registry, agentId);
      if (!task) { res.status(404).json({ error: "Task not found" }); return; }

      if (task.cost.tokensIn || task.cost.tokensOut) {
        this.costs.record({
          timestamp: Date.now(),
          agentId: task.assignedAgentId || "unknown",
          taskId: task.id,
          tokensIn: task.cost.tokensIn,
          tokensOut: task.cost.tokensOut,
          estimatedUsd: task.cost.estimatedUsd || estimateUsd(task.cost.tokensIn, task.cost.tokensOut),
          model: "default",
        });
      }

      if (task.status === "review") {
        this.approvals.request(task, task.result?.slice(0, 500) || "Task completed");
      }

      res.json(task);
    });

    app.post("/api/tasks/:id/cancel", (req: Request, res: Response) => {
      const task = this.tasks.get(req.params.id as string);
      if (!task) { res.status(404).json({ error: "Task not found" }); return; }
      this.tasks.setStatus(task.id, "cancelled");
      const agent = task.assignedAgentId ? this.registry.get(task.assignedAgentId) : null;
      if (agent && agent.state.currentTaskId === task.id) {
        agent.adapter.stop().catch(() => {});
        this.registry.setCurrentTask(agent.config.id, null);
      }
      res.json({ ...task, status: "cancelled" });
    });

    app.delete("/api/tasks/:id", (req: Request, res: Response) => {
      const ok = this.tasks.delete(req.params.id as string);
      res.json({ deleted: ok });
    });

    // ─── Approvals ──────────────────────────────────────────────────
    app.get("/api/approvals", (_req: Request, res: Response) => {
      res.json(this.approvals.listAll());
    });

    app.get("/api/approvals/pending", (_req: Request, res: Response) => {
      res.json(this.approvals.listPending());
    });

    app.post("/api/approvals/:id/approve", (req: Request, res: Response) => {
      const { by, comment } = req.body;
      const a = this.approvals.approve(req.params.id as string, by || "cli", comment, this.tasks);
      if (!a) { res.status(404).json({ error: "Approval not found or already resolved" }); return; }
      res.json(a);
    });

    app.post("/api/approvals/:id/reject", (req: Request, res: Response) => {
      const { by, comment } = req.body;
      const a = this.approvals.reject(req.params.id as string, by || "cli", comment, this.tasks);
      if (!a) { res.status(404).json({ error: "Approval not found or already resolved" }); return; }
      res.json(a);
    });

    // ─── Costs ──────────────────────────────────────────────────────
    app.get("/api/costs", (_req: Request, res: Response) => {
      res.json(this.costs.summary());
    });

    app.get("/api/costs/agent/:id", (req: Request, res: Response) => {
      res.json(this.costs.entriesForAgent(req.params.id as string));
    });

    // ─── Stats ──────────────────────────────────────────────────────
    app.get("/api/stats", (_req: Request, res: Response) => {
      res.json({
        tasks: this.tasks.stats(),
        costs: this.costs.summary(),
        agents: this.registry.list().map((a) => ({
          id: a.config.id,
          status: a.state.status,
          tasks: a.state.totalTasks,
          cost: a.state.totalCostUsd,
          errors: a.state.errors,
        })),
      });
    });
  }

  async start(): Promise<void> {
    for (const ac of this.config.agents) {
      if (ac.enabled) {
        await this.registry.register(ac);
        console.log(`  registered agent: ${ac.name} (${ac.type})`);
      }
    }

    this.heartbeats.start();

    return new Promise((resolve) => {
      this.server = this.app.listen(this.config.port, this.config.host, () => {
        console.log(`KMac Orchestrator listening on http://${this.config.host}:${this.config.port}`);
        resolve();
      });
    });
  }

  async stop(): Promise<void> {
    this.heartbeats.stop();
    for (const agent of this.registry.list()) {
      if (agent.state.currentTaskId) {
        await agent.adapter.stop().catch(() => {});
      }
    }
    if (this.server) {
      await new Promise<void>((r) => this.server.close(() => r()));
    }
  }
}
