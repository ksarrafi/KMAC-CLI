import { spawn, type ChildProcess } from "node:child_process";
import type { AgentConfig } from "../types.js";
import { type AgentAdapter, type RunResult, type LogCallback, emptyCost } from "./adapter.js";

/**
 * Generic shell adapter — runs tasks as shell commands.
 * Useful for build scripts, test runners, deploy tools, or any CLI-based agent.
 * config.config.shell — override shell (default: /bin/bash)
 * config.config.prefix — command prefix prepended to each task
 */
export class ShellAdapter implements AgentAdapter {
  readonly type = "shell";
  private proc: ChildProcess | null = null;
  private config: AgentConfig;
  private shell: string;
  private prefix: string;

  constructor(config: AgentConfig) {
    this.config = config;
    this.shell = (config.config.shell as string) || "/bin/bash";
    this.prefix = (config.config.prefix as string) || "";
  }

  async isAvailable(): Promise<boolean> {
    return true;
  }

  async run(task: string, projectDir: string | null, onLog: LogCallback): Promise<RunResult> {
    const start = Date.now();
    const command = this.prefix ? `${this.prefix} ${task}` : task;

    return new Promise((resolve) => {
      let stdout = "";
      let stderr = "";

      this.proc = spawn(this.shell, ["-c", command], {
        cwd: projectDir || undefined,
        stdio: "pipe",
        env: { ...process.env },
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
    return true;
  }
}
