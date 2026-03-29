import { WebSocket } from "ws";
import type { ChannelAdapter, InboundMessage, OutboundMessage, DiscordConfig } from "../types.js";

const API_BASE = "https://discord.com/api/v10";
const GATEWAY_URL = "wss://gateway.discord.gg/?v=10&encoding=json";

/**
 * Discord channel adapter using the Gateway WebSocket + REST API.
 * Connects as a bot, listens for messages, and responds via REST.
 */
export class DiscordChannel implements ChannelAdapter {
  type = "discord";
  onMessage: ((msg: InboundMessage) => Promise<void>) | null = null;

  private config: DiscordConfig;
  private token: string;
  private ws: WebSocket | null = null;
  private heartbeatInterval: ReturnType<typeof setInterval> | null = null;
  private seq: number | null = null;
  private sessionId: string | null = null;
  private botUserId: string | null = null;
  private running = false;

  constructor(config: DiscordConfig) {
    this.config = config;
    this.token = config.botToken || process.env.DISCORD_BOT_TOKEN || "";
  }

  async start(): Promise<void> {
    if (!this.token) {
      throw new Error("Discord bot token not configured (set channels.discord.botToken or DISCORD_BOT_TOKEN)");
    }
    this.running = true;
    await this.connect();
  }

  async stop(): Promise<void> {
    this.running = false;
    if (this.heartbeatInterval) clearInterval(this.heartbeatInterval);
    this.ws?.close(1000);
    this.ws = null;
  }

  async send(msg: OutboundMessage): Promise<void> {
    const channelId = msg.channelId;
    // Discord max is 2000 chars
    const chunks = this.chunkText(msg.text, 1950);
    for (const chunk of chunks) {
      await this.apiCall("POST", `/channels/${channelId}/messages`, { content: chunk });
    }
  }

  // ─── Gateway Connection ────────────────────────────────────────

  private async connect(): Promise<void> {
    return new Promise((resolve, reject) => {
      this.ws = new WebSocket(GATEWAY_URL);

      this.ws.on("message", (data) => {
        const payload = JSON.parse(data.toString());
        this.handleGatewayEvent(payload);
        if (payload.op === 0 && payload.t === "READY") {
          resolve();
        }
      });

      this.ws.on("close", (code) => {
        if (this.running && code !== 1000) {
          console.error(`  Discord: disconnected (${code}), reconnecting in 5s...`);
          setTimeout(() => this.connect().catch(() => {}), 5000);
        }
      });

      this.ws.on("error", (err) => {
        console.error(`  Discord: WebSocket error: ${err.message}`);
        reject(err);
      });
    });
  }

  private handleGatewayEvent(payload: {
    op: number;
    t?: string;
    s?: number;
    d?: Record<string, unknown>;
  }): void {
    if (payload.s) this.seq = payload.s;

    switch (payload.op) {
      case 10: // Hello
        this.startHeartbeat((payload.d as { heartbeat_interval: number }).heartbeat_interval);
        this.identify();
        break;

      case 11: // Heartbeat ACK
        break;

      case 0: // Dispatch
        this.handleDispatch(payload.t!, payload.d!);
        break;
    }
  }

  private startHeartbeat(intervalMs: number): void {
    if (this.heartbeatInterval) clearInterval(this.heartbeatInterval);
    this.heartbeatInterval = setInterval(() => {
      this.wsSend({ op: 1, d: this.seq });
    }, intervalMs);
  }

  private identify(): void {
    this.wsSend({
      op: 2,
      d: {
        token: this.token,
        intents: 1 << 9 | 1 << 12 | 1 << 15, // GUILD_MESSAGES | MESSAGE_CONTENT | DIRECT_MESSAGES
        properties: { os: "linux", browser: "kmac-assistant", device: "kmac-assistant" },
      },
    });
  }

  private handleDispatch(event: string, data: Record<string, unknown>): void {
    switch (event) {
      case "READY":
        this.sessionId = data.session_id as string;
        this.botUserId = (data.user as { id: string }).id;
        console.log(`  Discord: logged in as ${(data.user as { username: string }).username}`);
        break;

      case "MESSAGE_CREATE":
        this.handleMessage(data);
        break;
    }
  }

  private async handleMessage(data: Record<string, unknown>): Promise<void> {
    const author = data.author as { id: string; username: string; bot?: boolean };
    if (author.bot || author.id === this.botUserId) return;

    const content = data.content as string;
    if (!content) return;

    const channelId = data.channel_id as string;
    const guildId = data.guild_id as string | undefined;

    // Check guild allowlist
    if (guildId && this.config.allowedGuildIds?.length) {
      if (!this.config.allowedGuildIds.includes(guildId)) return;
    }

    // In guilds, only respond to mentions or DMs
    const isMentioned = (data.mentions as { id: string }[] | undefined)?.some(
      (m) => m.id === this.botUserId,
    );
    if (guildId && !isMentioned) return;

    // Strip bot mention from content
    const cleanContent = content.replace(/<@!?\d+>/g, "").trim();
    if (!cleanContent) return;

    const inbound: InboundMessage = {
      channelType: "discord",
      channelId,
      senderId: author.id,
      senderName: author.username,
      text: cleanContent,
      isGroup: !!guildId,
      groupId: guildId,
      replyTo: data.message_reference
        ? (data.message_reference as { message_id: string }).message_id
        : undefined,
      timestamp: Date.now(),
    };

    // Show typing
    await this.apiCall("POST", `/channels/${channelId}/typing`, {});

    if (this.onMessage) {
      await this.onMessage(inbound);
    }
  }

  // ─── Helpers ───────────────────────────────────────────────────

  private wsSend(data: unknown): void {
    if (this.ws?.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(data));
    }
  }

  private async apiCall(
    method: string,
    path: string,
    body?: Record<string, unknown>,
  ): Promise<unknown> {
    const url = `${API_BASE}${path}`;
    const opts: RequestInit = {
      method,
      headers: {
        Authorization: `Bot ${this.token}`,
        "Content-Type": "application/json",
      },
      signal: AbortSignal.timeout(10000),
    };
    if (body) opts.body = JSON.stringify(body);
    try {
      const res = await fetch(url, opts);
      if (!res.ok) {
        const text = await res.text();
        console.error(`  Discord API ${method} ${path}: ${res.status} ${text.slice(0, 200)}`);
      }
      return res.ok ? await res.json().catch(() => null) : null;
    } catch (e: unknown) {
      console.error(`  Discord API error: ${(e as Error).message}`);
      return null;
    }
  }

  private chunkText(text: string, maxLen: number): string[] {
    if (text.length <= maxLen) return [text];
    const chunks: string[] = [];
    let remaining = text;
    while (remaining.length > 0) {
      if (remaining.length <= maxLen) { chunks.push(remaining); break; }
      let splitAt = remaining.lastIndexOf("\n", maxLen);
      if (splitAt < maxLen * 0.5) splitAt = maxLen;
      chunks.push(remaining.slice(0, splitAt));
      remaining = remaining.slice(splitAt);
    }
    return chunks;
  }
}
