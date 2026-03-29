// ─── Agent Types ───────────────────────────────────────────────────────

export type AgentType = "claude-code" | "cursor" | "assistant" | "shell" | "custom";
export type AgentStatus = "idle" | "busy" | "offline" | "error";

export interface AgentConfig {
  id: string;
  name: string;
  type: AgentType;
  enabled: boolean;
  projectDir?: string;
  maxConcurrent: number;
  costLimitUsd?: number;
  heartbeatIntervalSec: number;
  config: Record<string, unknown>;
}

export interface AgentState {
  id: string;
  status: AgentStatus;
  currentTaskId: string | null;
  lastHeartbeat: number;
  totalTasks: number;
  totalCostUsd: number;
  totalTokensIn: number;
  totalTokensOut: number;
  startedAt: number;
  errors: number;
}

// ─── Task Types ────────────────────────────────────────────────────────

export type TaskStatus = "pending" | "assigned" | "running" | "review" | "approved" | "rejected" | "done" | "failed" | "cancelled";
export type TaskPriority = "low" | "normal" | "high" | "urgent";

export interface Task {
  id: string;
  title: string;
  description: string;
  status: TaskStatus;
  priority: TaskPriority;
  assignedAgentId: string | null;
  projectDir: string | null;
  createdAt: number;
  updatedAt: number;
  startedAt: number | null;
  completedAt: number | null;
  result: string | null;
  error: string | null;
  cost: TaskCost;
  approvalRequired: boolean;
  approvedBy: string | null;
  tags: string[];
  parentTaskId: string | null;
  subtaskIds: string[];
}

export interface TaskCost {
  tokensIn: number;
  tokensOut: number;
  estimatedUsd: number;
  durationMs: number;
}

// ─── Approval Types ────────────────────────────────────────────────────

export interface Approval {
  id: string;
  taskId: string;
  agentId: string;
  status: "pending" | "approved" | "rejected";
  summary: string;
  diff: string | null;
  requestedAt: number;
  resolvedAt: number | null;
  resolvedBy: string | null;
  comment: string | null;
}

// ─── Cost Types ────────────────────────────────────────────────────────

export interface CostEntry {
  timestamp: number;
  agentId: string;
  taskId: string;
  tokensIn: number;
  tokensOut: number;
  estimatedUsd: number;
  model: string;
}

export interface CostSummary {
  totalUsd: number;
  totalTokensIn: number;
  totalTokensOut: number;
  byAgent: Record<string, { usd: number; tokensIn: number; tokensOut: number; tasks: number }>;
  last24hUsd: number;
  last7dUsd: number;
}

// ─── Heartbeat Types ───────────────────────────────────────────────────

export interface Heartbeat {
  agentId: string;
  timestamp: number;
  status: AgentStatus;
  taskId: string | null;
  memoryMb: number | null;
  cpuPercent: number | null;
}

// ─── Config ────────────────────────────────────────────────────────────

export interface OrchestratorConfig {
  port: number;
  host: string;
  dataDir: string;
  agents: AgentConfig[];
  defaults: {
    approvalRequired: boolean;
    costLimitPerTaskUsd: number;
    costLimitDailyUsd: number;
    maxConcurrentTasks: number;
    heartbeatTimeoutSec: number;
  };
}
