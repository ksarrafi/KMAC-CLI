import { spawn, type ChildProcess } from "node:child_process";
import type { AgentConfig } from "../types.js";
import { type AgentAdapter, type RunResult, type LogCallback, emptyCost } from "./adapter.js";

/**
 * Adapter for Claude Code CLI (`claude`).
 * Runs tasks by invoking `claude -p "<task>"` with an optional --project-dir.
 */
export class ClaudeCodeAdapter implements AgentAdapter {
  readonly type = "claude-code";
  private proc: ChildProcess | null = null;
  private config: AgentConfig;

  constructor(config: AgentConfig) {
    this.config = config;
  }

  async isAvailable(): Promise<boolean> {
    return new Promise((resolve) => {
      const p = spawn("claude", ["--version"], { stdio: "pipe", shell: true });
      p.on("error", () => resolve(false));
      p.on("close", (code) => resolve(code === 0));
    });
  }

  async run(task: string, projectDir: string | null, onLog: LogCallback): Promise<RunResult> {
    const start = Date.now();
    const args = ["-p", task, "--output-format", "text"];
    if (projectDir) args.push("--project-dir", projectDir);

    return new Promise((resolve) => {
      let stdout = "";
      let stderr = "";

      this.proc = spawn("claude", args, {
        cwd: projectDir || undefined,
        shell: true,
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
        const cost = { ...emptyCost(), durationMs: Date.now() - start };
        const tokenMatch = stdout.match(/tokens:\s*(\d+)\s*in\s*[,/]\s*(\d+)\s*out/i);
        if (tokenMatch) {
          cost.tokensIn = parseInt(tokenMatch[1], 10);
          cost.tokensOut = parseInt(tokenMatch[2], 10);
          cost.estimatedUsd = (cost.tokensIn * 3 + cost.tokensOut * 15) / 1_000_000;
        }
        resolve({
          success: code === 0,
          output: stdout.trim(),
          error: code !== 0 ? (stderr.trim() || `Exited with code ${code}`) : null,
          cost,
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
