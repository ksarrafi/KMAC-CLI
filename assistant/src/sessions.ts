import { readFileSync, writeFileSync, readdirSync, unlinkSync, mkdirSync, existsSync } from "node:fs";
import { join } from "node:path";
import { v4 as uuid } from "uuid";
import type { Session, Message, AssistantConfig } from "./types.js";

export class SessionStore {
  private sessionsDir: string;
  private sessions = new Map<string, Session>();

  constructor(config: AssistantConfig) {
    this.sessionsDir = join(config.dataDir, "sessions");
    mkdirSync(this.sessionsDir, { recursive: true, mode: 0o700 });
    this.loadAll();
  }

  create(title?: string, model?: string): Session {
    const session: Session = {
      id: uuid(),
      title: title || "New conversation",
      createdAt: Date.now(),
      updatedAt: Date.now(),
      messages: [],
      model: model || "default",
    };
    this.sessions.set(session.id, session);
    this.persist(session);
    return session;
  }

  get(id: string): Session | undefined {
    return this.sessions.get(id);
  }

  list(): Session[] {
    return Array.from(this.sessions.values())
      .sort((a, b) => b.updatedAt - a.updatedAt);
  }

  addMessage(sessionId: string, message: Message): void {
    const session = this.sessions.get(sessionId);
    if (!session) throw new Error(`Session not found: ${sessionId}`);
    session.messages.push(message);
    session.updatedAt = Date.now();
    // Auto-title from first user message
    if (session.title === "New conversation" && message.role === "user") {
      session.title = message.content.slice(0, 80) + (message.content.length > 80 ? "..." : "");
    }
    this.persist(session);
  }

  getHistory(sessionId: string, maxMessages?: number): Message[] {
    const session = this.sessions.get(sessionId);
    if (!session) return [];
    const msgs = session.messages;
    if (maxMessages && msgs.length > maxMessages) {
      return msgs.slice(-maxMessages);
    }
    return msgs;
  }

  compact(sessionId: string): number {
    const session = this.sessions.get(sessionId);
    if (!session) throw new Error(`Session not found: ${sessionId}`);
    const before = session.messages.length;
    // Keep last 10 messages, summarize the rest as a system note
    if (session.messages.length <= 12) return 0;
    const kept = session.messages.slice(-10);
    const compactedCount = session.messages.length - 10;
    const note: Message = {
      role: "assistant",
      content: `[Context compacted: ${compactedCount} earlier messages removed to free context window]`,
      timestamp: Date.now(),
    };
    session.messages = [note, ...kept];
    session.updatedAt = Date.now();
    this.persist(session);
    return compactedCount;
  }

  delete(id: string): boolean {
    const session = this.sessions.get(id);
    if (!session) return false;
    this.sessions.delete(id);
    const filePath = join(this.sessionsDir, `${id}.json`);
    try { unlinkSync(filePath); } catch { /* ignore */ }
    return true;
  }

  private persist(session: Session): void {
    const filePath = join(this.sessionsDir, `${session.id}.json`);
    writeFileSync(filePath, JSON.stringify(session, null, 2), { mode: 0o600 });
  }

  private loadAll(): void {
    if (!existsSync(this.sessionsDir)) return;
    const files = readdirSync(this.sessionsDir).filter((f) => f.endsWith(".json"));
    for (const file of files) {
      try {
        const raw = readFileSync(join(this.sessionsDir, file), "utf-8");
        const session = JSON.parse(raw) as Session;
        if (session.id) this.sessions.set(session.id, session);
      } catch { /* skip corrupt files */ }
    }
  }
}
