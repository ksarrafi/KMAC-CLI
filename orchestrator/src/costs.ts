import { readFileSync, writeFileSync, appendFileSync, mkdirSync, existsSync } from "node:fs";
import { join } from "node:path";
import type { CostEntry, CostSummary } from "./types.js";

const PRICE_PER_1M: Record<string, { in: number; out: number }> = {
  "claude-4-sonnet":   { in: 3.0,  out: 15.0 },
  "claude-4-opus":     { in: 15.0, out: 75.0 },
  "claude-3.5-sonnet": { in: 3.0,  out: 15.0 },
  "gpt-4o":            { in: 2.5,  out: 10.0 },
  default:             { in: 3.0,  out: 15.0 },
};

export function estimateUsd(tokensIn: number, tokensOut: number, model = "default"): number {
  const prices = PRICE_PER_1M[model] || PRICE_PER_1M["default"];
  return (tokensIn * prices.in + tokensOut * prices.out) / 1_000_000;
}

export class CostTracker {
  private file: string;
  private entries: CostEntry[] = [];

  constructor(dataDir: string) {
    mkdirSync(dataDir, { recursive: true });
    this.file = join(dataDir, "costs.jsonl");
    this.load();
  }

  private load(): void {
    if (!existsSync(this.file)) return;
    try {
      const raw = readFileSync(this.file, "utf-8");
      for (const line of raw.split("\n")) {
        if (!line.trim()) continue;
        try { this.entries.push(JSON.parse(line)); } catch { /* skip */ }
      }
    } catch { /* fresh start */ }
  }

  record(entry: CostEntry): void {
    this.entries.push(entry);
    appendFileSync(this.file, JSON.stringify(entry) + "\n");
  }

  summary(): CostSummary {
    const now = Date.now();
    const h24 = now - 24 * 60 * 60 * 1000;
    const d7 = now - 7 * 24 * 60 * 60 * 1000;
    const byAgent: CostSummary["byAgent"] = {};
    let totalUsd = 0;
    let totalIn = 0;
    let totalOut = 0;
    let last24hUsd = 0;
    let last7dUsd = 0;

    for (const e of this.entries) {
      totalUsd += e.estimatedUsd;
      totalIn += e.tokensIn;
      totalOut += e.tokensOut;
      if (e.timestamp >= h24) last24hUsd += e.estimatedUsd;
      if (e.timestamp >= d7) last7dUsd += e.estimatedUsd;

      if (!byAgent[e.agentId]) {
        byAgent[e.agentId] = { usd: 0, tokensIn: 0, tokensOut: 0, tasks: 0 };
      }
      byAgent[e.agentId].usd += e.estimatedUsd;
      byAgent[e.agentId].tokensIn += e.tokensIn;
      byAgent[e.agentId].tokensOut += e.tokensOut;
      byAgent[e.agentId].tasks++;
    }

    return { totalUsd, totalTokensIn: totalIn, totalTokensOut: totalOut, byAgent, last24hUsd, last7dUsd };
  }

  entriesForAgent(agentId: string): CostEntry[] {
    return this.entries.filter((e) => e.agentId === agentId);
  }

  entriesForTask(taskId: string): CostEntry[] {
    return this.entries.filter((e) => e.taskId === taskId);
  }

  isOverBudget(dailyLimitUsd: number): boolean {
    const now = Date.now();
    const h24 = now - 24 * 60 * 60 * 1000;
    const todayTotal = this.entries
      .filter((e) => e.timestamp >= h24)
      .reduce((sum, e) => sum + e.estimatedUsd, 0);
    return todayTotal >= dailyLimitUsd;
  }
}
