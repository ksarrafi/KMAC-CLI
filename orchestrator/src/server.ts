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
