import type { AgentConfig } from "../types.js";
import { type AgentAdapter, type RunResult, type LogCallback, emptyCost } from "./adapter.js";

/**
 * Adapter for KMac Assistant (our OpenClaw equivalent).
 * Communicates via the Assistant's REST API running on localhost.
 */
export class AssistantAdapter implements AgentAdapter {
  readonly type = "assistant";
  private config: AgentConfig;
  private baseUrl: string;
  private abortController: AbortController | null = null;

  constructor(config: AgentConfig) {
    this.config = config;
    this.baseUrl = (config.config.url as string) || "http://127.0.0.1:7891";
  }

  async isAvailable(): Promise<boolean> {
    return this.ping();
  }

  async run(task: string, _projectDir: string | null, onLog: LogCallback): Promise<RunResult> {
    const start = Date.now();
    this.abortController = new AbortController();

    try {
      const sessResp = await fetch(`${this.baseUrl}/api/sessions`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ name: `orchestrator-${Date.now()}` }),
        signal: this.abortController.signal,
      });
      if (!sessResp.ok) throw new Error(`Failed to create session: ${sessResp.status}`);
      const session = (await sessResp.json()) as { id: string };

      const msgResp = await fetch(`${this.baseUrl}/api/sessions/${session.id}/messages`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ message: task }),
        signal: this.abortController.signal,
      });

      if (!msgResp.ok) throw new Error(`Failed to send message: ${msgResp.status}`);
      const result = (await msgResp.json()) as { reply?: string; text?: string };
      const output = result.reply || result.text || JSON.stringify(result);
      onLog("stdout", output);

      return {
        success: true,
        output,
        error: null,
        cost: { ...emptyCost(), durationMs: Date.now() - start },
      };
    } catch (err: unknown) {
      const msg = err instanceof Error ? err.message : String(err);
      return {
        success: false,
        output: "",
        error: msg,
        cost: { ...emptyCost(), durationMs: Date.now() - start },
      };
    } finally {
      this.abortController = null;
    }
  }

  async stop(): Promise<void> {
    this.abortController?.abort();
    this.abortController = null;
  }

  async ping(): Promise<boolean> {
    try {
      const resp = await fetch(`${this.baseUrl}/health`, {
        signal: AbortSignal.timeout(3000),
      });
      return resp.ok;
    } catch {
      return false;
    }
  }
}
