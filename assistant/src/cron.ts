import { randomUUID } from "node:crypto";
import type { CronJob, AssistantConfig, Message } from "./types.js";
import { Agent, type AgentStreamEvent } from "./agent.js";
import { SessionStore } from "./sessions.js";
import { ChannelRouter } from "./channels/router.js";

interface ParsedSchedule {
  intervalMs: number;
}

/**
 * Simple cron system for scheduled agent wake-ups.
 * Supports interval-based schedules (e.g., "every 5m", "every 1h", "every 30s").
 * Runs the cron message as an agent task, optionally routing the response to a channel.
 */
export class CronScheduler {
  private config: AssistantConfig;
  private agent: Agent;
  private sessions: SessionStore;
  private timers = new Map<string, ReturnType<typeof setInterval>>();

  constructor(config: AssistantConfig, agent: Agent, sessions: SessionStore) {
    this.config = config;
    this.agent = agent;
    this.sessions = sessions;
  }

  start(): void {
    for (const job of this.config.cron) {
      if (!job.enabled) continue;
      this.scheduleJob(job);
    }
    if (this.config.cron.filter((j) => j.enabled).length > 0) {
      console.log(`  Cron: ${this.timers.size} job(s) scheduled`);
    }
  }

  stop(): void {
    for (const [id, timer] of this.timers) {
      clearInterval(timer);
    }
    this.timers.clear();
  }

  private scheduleJob(job: CronJob): void {
    const schedule = this.parseSchedule(job.schedule);
    if (!schedule) {
      console.error(`  Cron: invalid schedule "${job.schedule}" for job ${job.id}`);
      return;
    }

    const timer = setInterval(() => {
      this.runJob(job).catch((e) => {
        console.error(`  Cron job ${job.id} failed: ${(e as Error).message}`);
      });
    }, schedule.intervalMs);

    this.timers.set(job.id, timer);
  }

  private async runJob(job: CronJob): Promise<void> {
    const sessionId = job.sessionId || this.getOrCreateCronSession(job.id);
    const userMsg: Message = {
      role: "user",
      content: `[Scheduled task: ${job.id}] ${job.message}`,
      timestamp: Date.now(),
    };
    this.sessions.addMessage(sessionId, userMsg);

    const history = this.sessions.getHistory(sessionId, 30);
    const prior = history.slice(0, -1);
    const runId = randomUUID();

    const response = await this.agent.run(runId, job.message, prior, () => {});
    this.sessions.addMessage(sessionId, response);
  }

  private getOrCreateCronSession(jobId: string): string {
    const sessions = this.sessions.list();
    const existing = sessions.find((s) => s.title === `cron:${jobId}`);
    if (existing) return existing.id;
    return this.sessions.create(`cron:${jobId}`).id;
  }

  private parseSchedule(schedule: string): ParsedSchedule | null {
    const match = schedule.match(/^every\s+(\d+)\s*(s|sec|seconds?|m|min|minutes?|h|hr|hours?|d|days?)$/i);
    if (!match) return null;

    const value = parseInt(match[1], 10);
    const unit = match[2].toLowerCase();

    let ms: number;
    if (unit.startsWith("s")) ms = value * 1000;
    else if (unit.startsWith("m")) ms = value * 60_000;
    else if (unit.startsWith("h")) ms = value * 3_600_000;
    else if (unit.startsWith("d")) ms = value * 86_400_000;
    else return null;

    if (ms < 10_000) ms = 10_000; // minimum 10s
    return { intervalMs: ms };
  }
}
