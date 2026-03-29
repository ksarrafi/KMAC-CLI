import type { AgentConfig, AgentState, AgentStatus, Heartbeat } from "../types.js";
import { type AgentAdapter, createAdapter } from "./adapter.js";

export interface RegisteredAgent {
  config: AgentConfig;
  adapter: AgentAdapter;
  state: AgentState;
}

export class AgentRegistry {
  private agents = new Map<string, RegisteredAgent>();
  private heartbeats: Heartbeat[] = [];
  private heartbeatTimeoutSec: number;

  constructor(heartbeatTimeoutSec: number) {
    this.heartbeatTimeoutSec = heartbeatTimeoutSec;
  }

  async register(config: AgentConfig): Promise<void> {
    if (this.agents.has(config.id)) return;
    const adapter = await createAdapter(config);
    const available = await adapter.isAvailable();
    const state: AgentState = {
      id: config.id,
      status: available ? "idle" : "offline",
      currentTaskId: null,
      lastHeartbeat: Date.now(),
      totalTasks: 0,
      totalCostUsd: 0,
      totalTokensIn: 0,
      totalTokensOut: 0,
      startedAt: Date.now(),
      errors: 0,
    };
    this.agents.set(config.id, { config, adapter, state });
  }

  get(id: string): RegisteredAgent | undefined {
    return this.agents.get(id);
  }

  list(): RegisteredAgent[] {
    return Array.from(this.agents.values());
  }

  listEnabled(): RegisteredAgent[] {
    return this.list().filter((a) => a.config.enabled);
  }

  setStatus(id: string, status: AgentStatus): void {
    const agent = this.agents.get(id);
    if (agent) agent.state.status = status;
  }

  setCurrentTask(id: string, taskId: string | null): void {
    const agent = this.agents.get(id);
    if (agent) {
      agent.state.currentTaskId = taskId;
      agent.state.status = taskId ? "busy" : "idle";
    }
  }

  recordHeartbeat(hb: Heartbeat): void {
    this.heartbeats.push(hb);
    if (this.heartbeats.length > 10000) this.heartbeats = this.heartbeats.slice(-5000);
    const agent = this.agents.get(hb.agentId);
    if (agent) {
      agent.state.lastHeartbeat = hb.timestamp;
      if (hb.status) agent.state.status = hb.status;
    }
  }

  recordCost(id: string, tokensIn: number, tokensOut: number, usd: number): void {
    const agent = this.agents.get(id);
    if (agent) {
      agent.state.totalCostUsd += usd;
      agent.state.totalTokensIn += tokensIn;
      agent.state.totalTokensOut += tokensOut;
    }
  }

  recordTaskComplete(id: string): void {
    const agent = this.agents.get(id);
    if (agent) agent.state.totalTasks++;
  }

  recordError(id: string): void {
    const agent = this.agents.get(id);
    if (agent) agent.state.errors++;
  }

  /** Find the best idle agent for a given task type preference */
  findAvailable(preferredType?: string): RegisteredAgent | undefined {
    const enabled = this.listEnabled();
    const idle = enabled.filter((a) => a.state.status === "idle");
    if (preferredType) {
      const match = idle.find((a) => a.config.type === preferredType);
      if (match) return match;
    }
    return idle[0];
  }

  /** Check for agents that missed their heartbeat */
  checkTimeouts(): string[] {
    const now = Date.now();
    const stale: string[] = [];
    for (const agent of this.list()) {
      if (agent.state.status === "offline") continue;
      const elapsed = (now - agent.state.lastHeartbeat) / 1000;
      if (elapsed > this.heartbeatTimeoutSec && agent.state.status === "busy") {
        agent.state.status = "error";
        stale.push(agent.config.id);
      }
    }
    return stale;
  }

  async pingAll(): Promise<Record<string, boolean>> {
    const results: Record<string, boolean> = {};
    for (const agent of this.list()) {
      try {
        results[agent.config.id] = await agent.adapter.ping();
        agent.state.status = results[agent.config.id]
          ? (agent.state.currentTaskId ? "busy" : "idle")
          : "offline";
      } catch {
        results[agent.config.id] = false;
        agent.state.status = "offline";
      }
    }
    return results;
  }
}
