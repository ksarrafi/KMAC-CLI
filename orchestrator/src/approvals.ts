import { readFileSync, writeFileSync, readdirSync, mkdirSync, existsSync } from "node:fs";
import { join } from "node:path";
import { v4 as uuid } from "uuid";
import type { Approval, Task } from "./types.js";
import type { TaskStore } from "./tasks.js";

export class ApprovalStore {
  private dir: string;
  private approvals = new Map<string, Approval>();

  constructor(dataDir: string) {
    this.dir = join(dataDir, "approvals");
    mkdirSync(this.dir, { recursive: true });
    this.loadAll();
  }

  private file(id: string): string {
    return join(this.dir, `${id}.json`);
  }

  private loadAll(): void {
    if (!existsSync(this.dir)) return;
    for (const f of readdirSync(this.dir)) {
      if (!f.endsWith(".json")) continue;
      try {
        const raw = readFileSync(join(this.dir, f), "utf-8");
        const a = JSON.parse(raw) as Approval;
        this.approvals.set(a.id, a);
      } catch { /* skip */ }
    }
  }

  private save(a: Approval): void {
    writeFileSync(this.file(a.id), JSON.stringify(a, null, 2));
  }

  request(task: Task, summary: string, diff?: string): Approval {
    const a: Approval = {
      id: uuid(),
      taskId: task.id,
      agentId: task.assignedAgentId || "unknown",
      status: "pending",
      summary,
      diff: diff || null,
      requestedAt: Date.now(),
      resolvedAt: null,
      resolvedBy: null,
      comment: null,
    };
    this.approvals.set(a.id, a);
    this.save(a);
    return a;
  }

  approve(id: string, by: string, comment?: string, taskStore?: TaskStore): Approval | undefined {
    const a = this.approvals.get(id);
    if (!a || a.status !== "pending") return undefined;
    a.status = "approved";
    a.resolvedAt = Date.now();
    a.resolvedBy = by;
    a.comment = comment || null;
    this.save(a);
    if (taskStore) taskStore.setStatus(a.taskId, "approved");
    return a;
  }

  reject(id: string, by: string, comment?: string, taskStore?: TaskStore): Approval | undefined {
    const a = this.approvals.get(id);
    if (!a || a.status !== "pending") return undefined;
    a.status = "rejected";
    a.resolvedAt = Date.now();
    a.resolvedBy = by;
    a.comment = comment || null;
    this.save(a);
    if (taskStore) taskStore.setStatus(a.taskId, "rejected");
    return a;
  }

  get(id: string): Approval | undefined {
    return this.approvals.get(id);
  }

  listPending(): Approval[] {
    return Array.from(this.approvals.values())
      .filter((a) => a.status === "pending")
      .sort((a, b) => b.requestedAt - a.requestedAt);
  }

  listAll(): Approval[] {
    return Array.from(this.approvals.values())
      .sort((a, b) => b.requestedAt - a.requestedAt);
  }

  forTask(taskId: string): Approval | undefined {
    return Array.from(this.approvals.values()).find((a) => a.taskId === taskId);
  }
}
