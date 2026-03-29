import { readFileSync, writeFileSync, mkdirSync, existsSync } from "node:fs";
import { join } from "node:path";
import { homedir } from "node:os";
import type { AssistantConfig } from "./types.js";

const CONFIG_DIR = join(homedir(), ".config", "kmac", "assistant");
const CONFIG_FILE = join(CONFIG_DIR, "config.json");

const DEFAULT_SYSTEM_PROMPT = `You are KMac Assistant, a personal AI assistant built into the KMac CLI toolkit.
You run locally on the user's machine and have access to tools for shell commands, file operations, web access, and system information.
You are direct, concise, and technically capable. When asked to perform tasks, use your tools to actually do them — don't just describe what to do.
When working with files or code, show relevant context. For multi-step tasks, work through them systematically.
If a command could be destructive, briefly confirm before proceeding.`;

const DEFAULT_CONFIG: AssistantConfig = {
  port: 7891,
  host: "127.0.0.1",
  model: "claude-sonnet-4-20250514",
  maxTokens: 8192,
  systemPrompt: DEFAULT_SYSTEM_PROMPT,
  dataDir: join(CONFIG_DIR, "data"),
  skillsDir: join(CONFIG_DIR, "skills"),
  tools: {
    bash: { enabled: true },
    files: { enabled: true },
    web: { enabled: true },
    system: { enabled: true },
  },
  channels: {
    telegram: { enabled: false, parseMode: "Markdown" },
    discord: { enabled: false },
  },
  cron: [],
};

export function ensureConfigDir(): void {
  mkdirSync(CONFIG_DIR, { recursive: true, mode: 0o700 });
}

export function loadConfig(): AssistantConfig {
  ensureConfigDir();
  if (!existsSync(CONFIG_FILE)) {
    writeFileSync(CONFIG_FILE, JSON.stringify(DEFAULT_CONFIG, null, 2), {
      mode: 0o600,
    });
    return { ...DEFAULT_CONFIG };
  }
  try {
    const raw = readFileSync(CONFIG_FILE, "utf-8");
    const user = JSON.parse(raw) as Partial<AssistantConfig>;
    return {
      ...DEFAULT_CONFIG,
      ...user,
      tools: { ...DEFAULT_CONFIG.tools, ...user.tools },
      channels: {
        telegram: { ...DEFAULT_CONFIG.channels.telegram, ...user.channels?.telegram },
        discord: { ...DEFAULT_CONFIG.channels.discord, ...user.channels?.discord },
      },
      cron: user.cron || DEFAULT_CONFIG.cron,
    };
  } catch {
    return { ...DEFAULT_CONFIG };
  }
}

export function saveConfig(config: AssistantConfig): void {
  ensureConfigDir();
  writeFileSync(CONFIG_FILE, JSON.stringify(config, null, 2), { mode: 0o600 });
}

export function getConfigDir(): string {
  return CONFIG_DIR;
}
