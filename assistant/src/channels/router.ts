import { randomUUID } from "node:crypto";
import type {
  AssistantConfig,
  ChannelAdapter,
  InboundMessage,
  OutboundMessage,
  Message,
} from "../types.js";
import { Agent, type AgentStreamEvent } from "../agent.js";
import { SessionStore } from "../sessions.js";
import { TelegramChannel } from "./telegram.js";
import { DiscordChannel } from "./discord.js";

interface ChannelSession {
  sessionId: string;
  channelType: string;
  channelId: string;
}

// Chat commands recognized in any channel
const COMMANDS: Record<string, string> = {
  "/new":     "Start a new session (clears context)",
  "/reset":   "Same as /new",
  "/status":  "Show session status (model, messages, tokens)",
  "/compact": "Compact session context to free token space",
  "/think":   "Set thinking level: /think high|medium|low|off",
  "/help":    "Show available commands",
  "/model":   "Show or change model: /model [name]",
  "/tools":   "List available tools",
  "/whoami":  "Show your channel and session info",
};

export class ChannelRouter {
  private config: AssistantConfig;
  private agent: Agent;
  private sessions: SessionStore;
  private channels: ChannelAdapter[] = [];
  private channelSessions = new Map<string, ChannelSession>();

  constructor(config: AssistantConfig, agent: Agent, sessions: SessionStore) {
    this.config = config;
    this.agent = agent;
    this.sessions = sessions;
  }

  async start(): Promise<void> {
    // Start Telegram if configured
    if (this.config.channels.telegram.enabled) {
      const tg = new TelegramChannel(this.config.channels.telegram);
      tg.onMessage = (msg) => this.handleInbound(msg, tg);
      try {
        await tg.start();
        this.channels.push(tg);
      } catch (e: unknown) {
        console.error(`  Telegram failed: ${(e as Error).message}`);
      }
    }

    // Start Discord if configured
    if (this.config.channels.discord.enabled) {
      const dc = new DiscordChannel(this.config.channels.discord);
      dc.onMessage = (msg) => this.handleInbound(msg, dc);
      try {
        await dc.start();
        this.channels.push(dc);
      } catch (e: unknown) {
        console.error(`  Discord failed: ${(e as Error).message}`);
      }
    }

    console.log(`  Channels: ${this.channels.length} active (${this.channels.map(c => c.type).join(", ") || "none"})`);
  }

  async stop(): Promise<void> {
    for (const ch of this.channels) {
      await ch.stop().catch(() => {});
    }
    this.channels = [];
  }

  private sessionKey(channelType: string, channelId: string): string {
    return `${channelType}:${channelId}`;
  }

  private getOrCreateSession(channelType: string, channelId: string): string {
    const key = this.sessionKey(channelType, channelId);
    const existing = this.channelSessions.get(key);
    if (existing) {
      const session = this.sessions.get(existing.sessionId);
      if (session) return existing.sessionId;
    }

    const session = this.sessions.create(`${channelType} chat`);
    this.channelSessions.set(key, { sessionId: session.id, channelType, channelId });
    return session.id;
  }

  private resetSession(channelType: string, channelId: string): string {
    const key = this.sessionKey(channelType, channelId);
    const existing = this.channelSessions.get(key);
    if (existing) {
      this.sessions.delete(existing.sessionId);
    }
    const session = this.sessions.create(`${channelType} chat`);
    this.channelSessions.set(key, { sessionId: session.id, channelType, channelId });
    return session.id;
  }

  private async handleInbound(msg: InboundMessage, channel: ChannelAdapter): Promise<void> {
    const text = msg.text.trim();

    // Handle slash commands
    if (text.startsWith("/")) {
      const handled = await this.handleCommand(text, msg, channel);
      if (handled) return;
    }

    // Route to agent
    const sessionId = this.getOrCreateSession(msg.channelType, msg.channelId);
    const userMsg: Message = { role: "user", content: text, timestamp: msg.timestamp };
    this.sessions.addMessage(sessionId, userMsg);

    const history = this.sessions.getHistory(sessionId, 50);
    const prior = history.slice(0, -1);
    const runId = randomUUID();

    let fullText = "";
    const onStream = (event: AgentStreamEvent) => {
      if (event.type === "text" && event.content) {
        fullText += event.content;
      }
    };

    try {
      const response = await this.agent.run(runId, text, prior, onStream);
      this.sessions.addMessage(sessionId, response);

      const replyText = response.content || "(no response)";
      await channel.send({
        channelType: msg.channelType,
        channelId: msg.channelId,
        text: replyText,
        parseMode: "Markdown",
      });
    } catch (e: unknown) {
      await channel.send({
        channelType: msg.channelType,
        channelId: msg.channelId,
        text: `Error: ${(e as Error).message}`,
        parseMode: "plain",
      });
    }
  }

  private async handleCommand(
    text: string,
    msg: InboundMessage,
    channel: ChannelAdapter,
  ): Promise<boolean> {
    const parts = text.split(/\s+/);
    const cmd = parts[0].toLowerCase();
    const args = parts.slice(1).join(" ");

    const reply = async (t: string, mode: "Markdown" | "plain" = "plain") => {
      await channel.send({
        channelType: msg.channelType,
        channelId: msg.channelId,
        text: t,
        parseMode: mode,
      });
    };

    switch (cmd) {
      case "/new":
      case "/reset": {
        this.resetSession(msg.channelType, msg.channelId);
        await reply("Session reset. Fresh context.");
        return true;
      }

      case "/status": {
        const sessionId = this.getOrCreateSession(msg.channelType, msg.channelId);
        const session = this.sessions.get(sessionId);
        if (!session) { await reply("No active session."); return true; }
        const msgCount = session.messages.length;
        const charCount = session.messages.reduce((n, m) => n + m.content.length, 0);
        await reply(
          `Session: ${session.id.slice(0, 8)}...\n` +
          `Model: ${this.config.model}\n` +
          `Messages: ${msgCount}\n` +
          `Context: ~${Math.round(charCount / 4)} tokens\n` +
          `Created: ${new Date(session.createdAt).toLocaleString()}`,
        );
        return true;
      }

      case "/compact": {
        const sessionId = this.getOrCreateSession(msg.channelType, msg.channelId);
        try {
          const removed = this.sessions.compact(sessionId);
          await reply(removed > 0 ? `Compacted: removed ${removed} messages.` : "Nothing to compact.");
        } catch {
          await reply("Failed to compact session.");
        }
        return true;
      }

      case "/model": {
        if (args) {
          await reply(`Model switching not yet supported. Current: ${this.config.model}`);
        } else {
          await reply(`Current model: ${this.config.model}`);
        }
        return true;
      }

      case "/tools": {
        const { buildToolRegistry } = await import("../tools.js");
        const tools = buildToolRegistry(this.config);
        const list = Array.from(tools.values()).map(t => `• ${t.definition.name} — ${t.definition.description.slice(0, 60)}...`).join("\n");
        await reply(`Available tools:\n\n${list}`);
        return true;
      }

      case "/whoami": {
        const sessionId = this.getOrCreateSession(msg.channelType, msg.channelId);
        await reply(
          `Channel: ${msg.channelType}\n` +
          `Chat ID: ${msg.channelId}\n` +
          `Sender: ${msg.senderName || msg.senderId}\n` +
          `Session: ${sessionId.slice(0, 8)}...\n` +
          `Group: ${msg.isGroup ? "yes" : "no"}`,
        );
        return true;
      }

      case "/think": {
        await reply("Thinking level adjustment — not yet implemented. Using model defaults.");
        return true;
      }

      case "/help": {
        const lines = Object.entries(COMMANDS).map(([k, v]) => `${k} — ${v}`);
        await reply(`KMac Assistant Commands:\n\n${lines.join("\n")}`);
        return true;
      }

      default:
        return false; // Not a recognized command, pass to agent
    }
  }
}
