import { spawn, type ChildProcess } from "node:child_process";
import type { AgentConfig } from "../types.js";
import { type AgentAdapter, type RunResult, type LogCallback, emptyCost } from "./adapter.js";

/**
 * Adapter for Cursor Agent Mode.
 * Uses the `cursor` CLI to run agent tasks in headless/background mode.
 * Falls back to opening Cursor with a task hint if headless mode isn't available.
 */
export class CursorAdapter implements AgentAdapter {
  readonly type = "cursor";
  private proc: ChildProcess | null = null;
  private config: AgentConfig;

  constructor(config: AgentConfig) {
    this.config = config;
  }

  async isAvailable(): Promise<boolean> {
    return new Promise((resolve) => {
      const p = spawn("cursor", ["--version"], { stdio: "pipe", shell: true });
      p.on("error", () => resolve(false));
      p.on("close", (code) => resolve(code === 0));
    });
  }

  async run(task: string, projectDir: string | null, onLog: LogCallback): Promise<RunResult> {
    const start = Date.now();
    const args: string[] = [];

    if (projectDir) args.push(projectDir);
    args.push("--agent", task);

    return new Promise((resolve) => {
      let stdout = "";
      let stderr = "";

      this.proc = spawn("cursor", args, {
        cwd: projectDir || undefined,
        shell: true,
        stdio: "pipe",
      });

      this.proc.stdout?.on("data", (data: Buffer) => {
        const text = data.toString();
        stdout += text;
        onLog("stdout", text);
      });

      this.proc.stderr?.on("data", (data: Buffer) => {
        const text = data.toString();
        stderr += text;
        onLog("stderr", text);
      });

      this.proc.on("error", (err) => {
        this.proc = null;
        resolve({
          success: false,
          output: stdout,
          error: err.message,
          cost: { ...emptyCost(), durationMs: Date.now() - start },
        });
      });

      this.proc.on("close", (code) => {
        this.proc = null;
        resolve({
          success: code === 0,
          output: stdout.trim(),
          error: code !== 0 ? (stderr.trim() || `Exited with code ${code}`) : null,
          cost: { ...emptyCost(), durationMs: Date.now() - start },
        });
      });
    });
  }

  async stop(): Promise<void> {
    if (this.proc && !this.proc.killed) {
      this.proc.kill("SIGTERM");
      await new Promise<void>((r) => setTimeout(r, 1000));
      if (this.proc && !this.proc.killed) this.proc.kill("SIGKILL");
      this.proc = null;
    }
  }

  async ping(): Promise<boolean> {
    return this.isAvailable();
  }
}
