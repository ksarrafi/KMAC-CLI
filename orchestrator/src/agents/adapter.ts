import type { AgentConfig, TaskCost } from "../types.js";

export interface RunResult {
  success: boolean;
  output: string;
  error: string | null;
  cost: TaskCost;
}

export type LogCallback = (stream: "stdout" | "stderr", data: string) => void;

export interface AgentAdapter {
  readonly type: string;
  isAvailable(): Promise<boolean>;
  run(task: string, projectDir: string | null, onLog: LogCallback): Promise<RunResult>;
  stop(): Promise<void>;
  ping(): Promise<boolean>;
}

export function emptyCost(): TaskCost {
  return { tokensIn: 0, tokensOut: 0, estimatedUsd: 0, durationMs: 0 };
}

export async function createAdapter(config: AgentConfig): Promise<AgentAdapter> {
  switch (config.type) {
    case "claude-code": {
      const { ClaudeCodeAdapter } = await import("./claude-code.js");
      return new ClaudeCodeAdapter(config);
    }
    case "cursor": {
      const { CursorAdapter } = await import("./cursor.js");
      return new CursorAdapter(config);
    }
    case "assistant": {
      const { AssistantAdapter } = await import("./assistant.js");
      return new AssistantAdapter(config);
    }
    case "shell":
    case "custom": {
      const { ShellAdapter } = await import("./shell.js");
      return new ShellAdapter(config);
    }
    default:
      throw new Error(`Unknown agent type: ${config.type}`);
  }
}
