import { readFileSync, writeFileSync, mkdirSync, existsSync } from "node:fs";
import { join } from "node:path";
import { homedir } from "node:os";
import type { OrchestratorConfig } from "./types.js";

const CONFIG_DIR = join(homedir(), ".config", "kmac", "orchestrator");
const CONFIG_FILE = join(CONFIG_DIR, "config.json");

const DEFAULT_CONFIG: OrchestratorConfig = {
  port: 7892,
  host: "127.0.0.1",
  dataDir: join(CONFIG_DIR, "data"),
  agents: [
    {
      id: "claude-code-default",
      name: "Claude Code",
      type: "claude-code",
      enabled: true,
      maxConcurrent: 1,
      heartbeatIntervalSec: 30,
      config: {},
    },
    {
      id: "cursor-default",
      name: "Cursor Agent",
      type: "cursor",
      enabled: true,
      maxConcurrent: 1,
      heartbeatIntervalSec: 30,
      config: {},
    },
    {
      id: "assistant-default",
      name: "KMac Assistant",
      type: "assistant",
      enabled: true,
      maxConcurrent: 3,
      heartbeatIntervalSec: 15,
      config: { url: "http://127.0.0.1:7891" },
    },
  ],
  defaults: {
    approvalRequired: false,
    costLimitPerTaskUsd: 5.0,
    costLimitDailyUsd: 50.0,
    maxConcurrentTasks: 5,
    heartbeatTimeoutSec: 120,
  },
};

export function ensureConfigDir(): void {
  mkdirSync(CONFIG_DIR, { recursive: true, mode: 0o700 });
}

export function loadConfig(): OrchestratorConfig {
  ensureConfigDir();
  if (!existsSync(CONFIG_FILE)) {
    writeFileSync(CONFIG_FILE, JSON.stringify(DEFAULT_CONFIG, null, 2), { mode: 0o600 });
    return { ...DEFAULT_CONFIG };
  }
  try {
    const raw = readFileSync(CONFIG_FILE, "utf-8");
    const user = JSON.parse(raw) as Partial<OrchestratorConfig>;
    return {
      ...DEFAULT_CONFIG,
      ...user,
      defaults: { ...DEFAULT_CONFIG.defaults, ...user.defaults },
      agents: user.agents || DEFAULT_CONFIG.agents,
    };
  } catch {
    return { ...DEFAULT_CONFIG };
  }
}

export function getConfigDir(): string {
  return CONFIG_DIR;
}
