import { readFileSync, writeFileSync, readdirSync, mkdirSync, existsSync, unlinkSync } from "node:fs";
import { join } from "node:path";
import { v4 as uuid } from "uuid";
import type { Task, TaskStatus, TaskPriority, TaskCost } from "./types.js";
import type { AgentRegistry } from "./agents/registry.js";
import type { RunResult, LogCallback } from "./agents/adapter.js";

export class TaskStore {
  private dir: string;
  private tasks = new Map<string, Task>();
  private logs = new Map<string, string[]>();

  constructor(dataDir: string) {
    this.dir = join(dataDir, "tasks");
    mkdirSync(this.dir, { recursive: true });
    this.loadAll();
  }

  private taskFile(id: string): string {
    return join(this.dir, `${id}.json`);
  }

  private loadAll(): void {
    if (!existsSync(this.dir)) return;
    for (const f of readdirSync(this.dir)) {
      if (!f.endsWith(".json")) continue;
      try {
        const raw = readFileSync(join(this.dir, f), "utf-8");
        const task = JSON.parse(raw) as Task;
        this.tasks.set(task.id, task);
      } catch { /* skip corrupted files */ }
    }
  }

  private save(task: Task): void {
    writeFileSync(this.taskFile(task.id), JSON.stringify(task, null, 2));
  }

  create(opts: {
    title: string;
    description?: string;
    priority?: TaskPriority;
    projectDir?: string;
    approvalRequired?: boolean;
    tags?: string[];
    parentTaskId?: string;
  }): Task {
    const task: Task = {
      id: uuid(),
      title: opts.title,
      description: opts.description || "",
      status: "pending",
      priority: opts.priority || "normal",
      assignedAgentId: null,
      projectDir: opts.projectDir || null,
      createdAt: Date.now(),
      updatedAt: Date.now(),
      startedAt: null,
      completedAt: null,
      result: null,
      error: null,
      cost: { tokensIn: 0, tokensOut: 0, estimatedUsd: 0, durationMs: 0 },
      approvalRequired: opts.approvalRequired ?? false,
      approvedBy: null,
      tags: opts.tags || [],
      parentTaskId: opts.parentTaskId || null,
      subtaskIds: [],
    };
    this.tasks.set(task.id, task);
    this.save(task);

    if (task.parentTaskId) {
      const parent = this.tasks.get(task.parentTaskId);
      if (parent) {
        parent.subtaskIds.push(task.id);
        parent.updatedAt = Date.now();
        this.save(parent);
      }
    }
    return task;
  }

  get(id: string): Task | undefined {
    return this.tasks.get(id);
  }

  list(filter?: { status?: TaskStatus; agentId?: string; tag?: string }): Task[] {
    let items = Array.from(this.tasks.values());
    if (filter?.status) items = items.filter((t) => t.status === filter.status);
    if (filter?.agentId) items = items.filter((t) => t.assignedAgentId === filter.agentId);
    if (filter?.tag) items = items.filter((t) => t.tags.includes(filter.tag!));
    return items.sort((a, b) => b.updatedAt - a.updatedAt);
  }

  assign(taskId: string, agentId: string): Task | undefined {
    const task = this.tasks.get(taskId);
    if (!task) return undefined;
    task.assignedAgentId = agentId;
    task.status = "assigned";
    task.updatedAt = Date.now();
    this.save(task);
    return task;
  }

  markRunning(taskId: string): void {
    const task = this.tasks.get(taskId);
    if (!task) return;
    task.status = "running";
    task.startedAt = Date.now();
    task.updatedAt = Date.now();
    this.save(task);
  }

  complete(taskId: string, result: string, cost: TaskCost): void {
    const task = this.tasks.get(taskId);
    if (!task) return;
    task.status = task.approvalRequired ? "review" : "done";
    task.result = result;
    task.cost = cost;
    task.completedAt = Date.now();
    task.updatedAt = Date.now();
    this.save(task);
  }

  fail(taskId: string, error: string, cost: TaskCost): void {
    const task = this.tasks.get(taskId);
    if (!task) return;
    task.status = "failed";
    task.error = error;
    task.cost = cost;
    task.completedAt = Date.now();
    task.updatedAt = Date.now();
    this.save(task);
  }

  setStatus(taskId: string, status: TaskStatus): void {
    const task = this.tasks.get(taskId);
    if (!task) return;
    task.status = status;
    task.updatedAt = Date.now();
    this.save(task);
  }

  appendLog(taskId: string, line: string): void {
    if (!this.logs.has(taskId)) this.logs.set(taskId, []);
    this.logs.get(taskId)!.push(line);
    const lines = this.logs.get(taskId)!;
    if (lines.length > 5000) this.logs.set(taskId, lines.slice(-2500));
  }

  getLogs(taskId: string): string[] {
    return this.logs.get(taskId) || [];
  }

  delete(id: string): boolean {
    const task = this.tasks.get(id);
    if (!task) return false;
    this.tasks.delete(id);
    this.logs.delete(id);
    try { unlinkSync(this.taskFile(id)); } catch { /* ok */ }
    return true;
  }

  stats(): { total: number; pending: number; running: number; done: number; failed: number } {
    const all = Array.from(this.tasks.values());
    return {
      total: all.length,
      pending: all.filter((t) => t.status === "pending").length,
      running: all.filter((t) => ["assigned", "running"].includes(t.status)).length,
      done: all.filter((t) => t.status === "done").length,
      failed: all.filter((t) => t.status === "failed").length,
    };
  }

  /** Dispatch a task to an agent — finds an available agent, runs it, records result */
  async dispatch(
    taskId: string,
    registry: AgentRegistry,
    preferredAgent?: string,
  ): Promise<Task | undefined> {
    const task = this.tasks.get(taskId);
    if (!task) return undefined;

    const targetId = preferredAgent || task.assignedAgentId;
    const agent = targetId
      ? registry.get(targetId)
      : registry.findAvailable();

    if (!agent) {
      task.error = "No available agent";
      task.status = "failed";
      task.updatedAt = Date.now();
      this.save(task);
      return task;
    }

    task.assignedAgentId = agent.config.id;
    this.markRunning(taskId);
    registry.setCurrentTask(agent.config.id, taskId);

    const onLog: LogCallback = (stream, data) => {
      this.appendLog(taskId, `[${stream}] ${data}`);
    };

    let result: RunResult;
    try {
      result = await agent.adapter.run(
        `${task.title}\n\n${task.description}`.trim(),
        task.projectDir,
        onLog,
      );
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : String(err);
      this.fail(taskId, msg, { tokensIn: 0, tokensOut: 0, estimatedUsd: 0, durationMs: 0 });
      registry.setCurrentTask(agent.config.id, null);
      registry.recordError(agent.config.id);
      return this.tasks.get(taskId);
    }

    registry.setCurrentTask(agent.config.id, null);
    registry.recordCost(agent.config.id, result.cost.tokensIn, result.cost.tokensOut, result.cost.estimatedUsd);
    registry.recordTaskComplete(agent.config.id);

    if (result.success) {
      this.complete(taskId, result.output, result.cost);
    } else {
      this.fail(taskId, result.error || "Unknown error", result.cost);
      registry.recordError(agent.config.id);
    }

    return this.tasks.get(taskId);
  }
}
