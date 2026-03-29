import type { ChannelAdapter, InboundMessage, OutboundMessage, TelegramConfig } from "../types.js";

const API_BASE = "https://api.telegram.org/bot";

interface TgUpdate {
  update_id: number;
  message?: {
    message_id: number;
    chat: { id: number; type: string; title?: string };
    from?: { id: number; first_name?: string; username?: string };
    text?: string;
    date: number;
    reply_to_message?: { message_id: number };
    photo?: { file_id: string }[];
    document?: { file_id: string; file_name?: string };
    voice?: { file_id: string };
  };
}

export class TelegramChannel implements ChannelAdapter {
  type = "telegram";
  onMessage: ((msg: InboundMessage) => Promise<void>) | null = null;

  private config: TelegramConfig;
  private token: string;
  private offset = 0;
  private polling = false;
  private abortController: AbortController | null = null;

  constructor(config: TelegramConfig) {
    this.config = config;
    this.token = config.botToken || process.env.TELEGRAM_BOT_TOKEN || "";
  }

  async start(): Promise<void> {
    if (!this.token) {
      throw new Error("Telegram bot token not configured (set channels.telegram.botToken or TELEGRAM_BOT_TOKEN)");
    }

    // Verify token
    const me = await this.apiCall("getMe");
    if (!me.ok) throw new Error(`Telegram auth failed: ${JSON.stringify(me)}`);
    console.log(`  Telegram: @${me.result.username} connected`);

    this.polling = true;
    this.poll();
  }

  async stop(): Promise<void> {
    this.polling = false;
    this.abortController?.abort();
  }

  async send(msg: OutboundMessage): Promise<void> {
    const chatId = msg.channelId;
    const text = msg.text;

    // Telegram has a 4096-char limit per message
    const chunks = this.chunkText(text, 4000);
    for (const chunk of chunks) {
      const params: Record<string, unknown> = {
        chat_id: chatId,
        text: chunk,
      };
      if (msg.parseMode && msg.parseMode !== "plain") {
        params.parse_mode = msg.parseMode;
      } else if (this.config.parseMode) {
        params.parse_mode = this.config.parseMode;
      }
      if (msg.replyTo) {
        params.reply_to_message_id = parseInt(msg.replyTo, 10);
      }

      const result = await this.apiCall("sendMessage", params);
      if (!result.ok) {
        // Retry without parse mode if Markdown fails
        if (params.parse_mode) {
          delete params.parse_mode;
          await this.apiCall("sendMessage", params);
        }
      }
    }
  }

  // Send typing indicator
  async sendTyping(chatId: string): Promise<void> {
    await this.apiCall("sendChatAction", { chat_id: chatId, action: "typing" });
  }

  // ─── Long Polling ──────────────────────────────────────────────

  private async poll(): Promise<void> {
    while (this.polling) {
      try {
        this.abortController = new AbortController();
        const result = await this.apiCall("getUpdates", {
          offset: this.offset,
          timeout: 30,
          allowed_updates: ["message"],
        });

        if (result.ok && Array.isArray(result.result)) {
          for (const update of result.result as TgUpdate[]) {
            this.offset = update.update_id + 1;
            await this.handleUpdate(update);
          }
        }
      } catch (e: unknown) {
        if ((e as Error).name === "AbortError") break;
        console.error(`  Telegram poll error: ${(e as Error).message}`);
        await this.sleep(5000);
      }
    }
  }

  private async handleUpdate(update: TgUpdate): Promise<void> {
    const msg = update.message;
    if (!msg || !msg.text) return;

    // Security: check allowed chat IDs
    const chatId = String(msg.chat.id);
    if (this.config.allowedChatIds && this.config.allowedChatIds.length > 0) {
      if (!this.config.allowedChatIds.includes(chatId)) {
        await this.apiCall("sendMessage", {
          chat_id: chatId,
          text: `Access denied. Your chat ID: ${chatId}\nAdd it to channels.telegram.allowedChatIds to allow access.`,
        });
        return;
      }
    }

    const inbound: InboundMessage = {
      channelType: "telegram",
      channelId: chatId,
      senderId: String(msg.from?.id || "unknown"),
      senderName: msg.from?.first_name || msg.from?.username,
      text: msg.text,
      isGroup: msg.chat.type !== "private",
      groupId: msg.chat.type !== "private" ? chatId : undefined,
      replyTo: msg.reply_to_message ? String(msg.reply_to_message.message_id) : undefined,
      timestamp: msg.date * 1000,
    };

    if (this.onMessage) {
      await this.sendTyping(chatId);
      await this.onMessage(inbound);
    }
  }

  // ─── Helpers ───────────────────────────────────────────────────

  private async apiCall(method: string, params?: Record<string, unknown>): Promise<{ ok: boolean; result?: any }> {
    const url = `${API_BASE}${this.token}/${method}`;
    try {
      const opts: RequestInit = {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        signal: method === "getUpdates"
          ? AbortSignal.timeout(60000)
          : AbortSignal.timeout(10000),
      };
      if (params) opts.body = JSON.stringify(params);
      const res = await fetch(url, opts);
      return (await res.json()) as { ok: boolean; result?: any };
    } catch (e: unknown) {
      if ((e as Error).name === "AbortError") throw e;
      return { ok: false };
    }
  }

  private chunkText(text: string, maxLen: number): string[] {
    if (text.length <= maxLen) return [text];
    const chunks: string[] = [];
    let remaining = text;
    while (remaining.length > 0) {
      if (remaining.length <= maxLen) {
        chunks.push(remaining);
        break;
      }
      let splitAt = remaining.lastIndexOf("\n", maxLen);
      if (splitAt < maxLen * 0.5) splitAt = maxLen;
      chunks.push(remaining.slice(0, splitAt));
      remaining = remaining.slice(splitAt);
    }
    return chunks;
  }

  private sleep(ms: number): Promise<void> {
    return new Promise((r) => setTimeout(r, ms));
  }
}
