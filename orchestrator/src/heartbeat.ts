import type { AgentRegistry } from "./agents/registry.js";
import type { TaskStore } from "./tasks.js";

export type HeartbeatCallback = (agentId: string, event: "timeout" | "recovered") => void;

export class HeartbeatMonitor {
  private interval: ReturnType<typeof setInterval> | null = null;
  private registry: AgentRegistry;
  private tasks: TaskStore;
  private checkIntervalSec: number;
  private callback: HeartbeatCallback;

  constructor(
    registry: AgentRegistry,
    tasks: TaskStore,
    checkIntervalSec: number,
    callback: HeartbeatCallback,
  ) {
    this.registry = registry;
    this.tasks = tasks;
    this.checkIntervalSec = checkIntervalSec;
    this.callback = callback;
  }

  start(): void {
    if (this.interval) return;
    this.interval = setInterval(() => this.check(), this.checkIntervalSec * 1000);
  }

  stop(): void {
    if (this.interval) {
      clearInterval(this.interval);
      this.interval = null;
    }
  }

  private check(): void {
    const stale = this.registry.checkTimeouts();
    for (const agentId of stale) {
      this.callback(agentId, "timeout");

      const agent = this.registry.get(agentId);
      if (agent?.state.currentTaskId) {
        this.tasks.fail(
          agent.state.currentTaskId,
          `Agent ${agentId} timed out (heartbeat missed)`,
          { tokensIn: 0, tokensOut: 0, estimatedUsd: 0, durationMs: 0 },
        );
        this.registry.setCurrentTask(agentId, null);
      }
    }
  }

  /** Manually trigger a full ping sweep */
  async sweep(): Promise<Record<string, boolean>> {
    return this.registry.pingAll();
  }
}
