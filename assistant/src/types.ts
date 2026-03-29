// ─── WebSocket Protocol (modeled after OpenClaw's gateway wire format) ───

export interface RequestFrame {
  type: "req";
  id: string;
  method: string;
  params?: Record<string, unknown>;
}

export interface ResponseFrame {
  type: "res";
  id: string;
  ok: boolean;
  payload?: unknown;
  error?: { code?: string; message?: string };
}

export interface EventFrame {
  type: "event";
  event: string;
  payload?: Record<string, unknown>;
  seq?: number;
}

export type WireFrame = RequestFrame | ResponseFrame | EventFrame;

// ─── Agent & Tool Types ────────────────────────────────────────────────

export interface ToolDefinition {
  name: string;
  description: string;
  input_schema: Record<string, unknown>;
}

export interface ToolResult {
  output: string;
  error?: string;
  isError?: boolean;
}

export type ToolHandler = (input: Record<string, unknown>) => Promise<ToolResult>;

export interface ToolEntry {
  definition: ToolDefinition;
  handler: ToolHandler;
}

// ─── Session Types ─────────────────────────────────────────────────────

export interface Message {
  role: "user" | "assistant";
  content: string;
  timestamp: number;
  toolUse?: { name: string; input: unknown }[];
}

export interface Session {
  id: string;
  title: string;
  createdAt: number;
  updatedAt: number;
  messages: Message[];
  model: string;
  systemPrompt?: string;
}

// ─── Channel Types ─────────────────────────────────────────────────────

export interface InboundMessage {
  channelType: string;
  channelId: string;
  senderId: string;
  senderName?: string;
  text: string;
  isGroup: boolean;
  groupId?: string;
  replyTo?: string;
  mediaUrl?: string;
  mediaType?: string;
  timestamp: number;
}

export interface OutboundMessage {
  channelType: string;
  channelId: string;
  text: string;
  replyTo?: string;
  parseMode?: "Markdown" | "HTML" | "plain";
}

export interface ChannelAdapter {
  type: string;
  start(): Promise<void>;
  stop(): Promise<void>;
  send(msg: OutboundMessage): Promise<void>;
  onMessage: ((msg: InboundMessage) => Promise<void>) | null;
}

// ─── Skill Types ───────────────────────────────────────────────────────

export interface Skill {
  name: string;
  path: string;
  content: string;
}

// ─── Cron Types ────────────────────────────────────────────────────────

export interface CronJob {
  id: string;
  schedule: string;
  message: string;
  sessionId?: string;
  channelType?: string;
  channelId?: string;
  enabled: boolean;
}

// ─── Config Types ──────────────────────────────────────────────────────

export interface TelegramConfig {
  enabled: boolean;
  botToken?: string;
  allowedChatIds?: string[];
  parseMode?: "Markdown" | "HTML";
}

export interface DiscordConfig {
  enabled: boolean;
  botToken?: string;
  allowedGuildIds?: string[];
}

export interface ChannelsConfig {
  telegram: TelegramConfig;
  discord: DiscordConfig;
}

export interface AssistantConfig {
  port: number;
  host: string;
  model: string;
  maxTokens: number;
  systemPrompt: string;
  dataDir: string;
  skillsDir: string;
  tools: {
    bash: { enabled: boolean; allowedDirs?: string[] };
    files: { enabled: boolean; allowedDirs?: string[] };
    web: { enabled: boolean };
    system: { enabled: boolean };
  };
  channels: ChannelsConfig;
  cron: CronJob[];
}

// ─── Gateway Event Names ───────────────────────────────────────────────

export const GatewayEvents = {
  AGENT_STREAM: "agent.stream",
  AGENT_TOOL_USE: "agent.tool_use",
  AGENT_TOOL_RESULT: "agent.tool_result",
  AGENT_DONE: "agent.done",
  AGENT_ERROR: "agent.error",
  SESSION_CREATED: "session.created",
  SESSION_UPDATED: "session.updated",
} as const;

export const GatewayMethods = {
  CONNECT: "connect",
  AGENT_RUN: "agent.run",
  AGENT_STOP: "agent.stop",
  SESSION_LIST: "session.list",
  SESSION_GET: "session.get",
  SESSION_NEW: "session.new",
  SESSION_DELETE: "session.delete",
  SESSION_COMPACT: "session.compact",
} as const;
