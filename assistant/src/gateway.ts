import express from "express";
import { createServer } from "node:http";
import { WebSocketServer, WebSocket } from "ws";
import { randomUUID } from "node:crypto";
import { Agent, type AgentStreamEvent } from "./agent.js";
import { SessionStore } from "./sessions.js";
import { ChannelRouter } from "./channels/router.js";
import { SkillsLoader } from "./skills.js";
import { CronScheduler } from "./cron.js";
import type {
  AssistantConfig,
  RequestFrame,
  ResponseFrame,
  EventFrame,
  WireFrame,
  Message,
} from "./types.js";
import { buildToolRegistry } from "./tools.js";

interface WsClient {
  id: string;
  ws: WebSocket;
  authenticated: boolean;
  subscribedSessions: Set<string>;
}

export class Gateway {
  private config: AssistantConfig;
  private agent: Agent;
  private sessions: SessionStore;
  private channelRouter: ChannelRouter;
  private skills: SkillsLoader;
  private cron: CronScheduler;
  private clients = new Map<string, WsClient>();
  private authToken: string;
  private eventSeq = 0;

  constructor(config: AssistantConfig) {
    this.config = config;
    const tools = buildToolRegistry(config);

    // Load skills and augment system prompt
    this.skills = new SkillsLoader(config);
    const skillsPrompt = this.skills.buildSkillsPrompt();
    if (skillsPrompt) {
      config.systemPrompt += skillsPrompt;
    }

    this.agent = new Agent(config, tools);
    this.sessions = new SessionStore(config);
    this.channelRouter = new ChannelRouter(config, this.agent, this.sessions);
    this.cron = new CronScheduler(config, this.agent, this.sessions);
    this.authToken = process.env.KMAC_ASSISTANT_TOKEN || randomUUID();
  }

  start(): void {
    const app = express();
    app.use(express.json({ limit: "1mb" }));

    // ─── REST API ────────────────────────────────────────────────
    app.get("/health", (_req, res) => {
      res.json({
        status: "ok",
        version: "0.1.0",
        uptime: Math.floor(process.uptime()),
        model: this.config.model,
        sessions: this.sessions.list().length,
        clients: this.clients.size,
        skills: this.skills.getSkills().length,
        channels: {
          telegram: this.config.channels.telegram.enabled,
          discord: this.config.channels.discord.enabled,
        },
        cron: this.config.cron.filter((j) => j.enabled).length,
      });
    });

    app.get("/api/ping", (_req, res) => res.json({ pong: Date.now() }));

    // Auth middleware for API routes
    const requireAuth: express.RequestHandler = (req, res, next) => {
      const token = (req.headers.authorization || "").replace("Bearer ", "").trim();
      if (!token || token !== this.authToken) {
        res.status(401).json({ error: "Unauthorized" });
        return;
      }
      next();
    };

    app.get("/api/sessions", requireAuth, (_req, res) => {
      const sessions = this.sessions.list().map((s) => ({
        id: s.id,
        title: s.title,
        createdAt: s.createdAt,
        updatedAt: s.updatedAt,
        messageCount: s.messages.length,
        model: s.model,
      }));
      res.json(sessions);
    });

    app.post("/api/sessions", requireAuth, (req, res) => {
      const { title, model } = req.body as { title?: string; model?: string };
      const session = this.sessions.create(title, model);
      res.status(201).json({ id: session.id, title: session.title });
    });

    app.get("/api/sessions/:id", requireAuth, (req, res) => {
      const id = req.params.id as string;
      const session = this.sessions.get(id);
      if (!session) { res.status(404).json({ error: "Session not found" }); return; }
      res.json(session);
    });

    app.delete("/api/sessions/:id", requireAuth, (req, res) => {
      const id = req.params.id as string;
      this.sessions.delete(id);
      res.json({ ok: true });
    });

    app.post("/api/sessions/:id/compact", requireAuth, (req, res) => {
      const id = req.params.id as string;
      try {
        const removed = this.sessions.compact(id);
        res.json({ ok: true, removed });
      } catch (e: unknown) {
        res.status(404).json({ error: (e as Error).message });
      }
    });

    // Synchronous message endpoint (waits for full response)
    app.post("/api/sessions/:id/message", requireAuth, async (req, res) => {
      const id = req.params.id as string;
      const session = this.sessions.get(id);
      if (!session) { res.status(404).json({ error: "Session not found" }); return; }
      const { message } = req.body as { message: string };
      if (!message) { res.status(400).json({ error: "message is required" }); return; }

      const userMsg: Message = { role: "user", content: message, timestamp: Date.now() };
      this.sessions.addMessage(session.id, userMsg);

      const runId = randomUUID();
      try {
        const history = this.sessions.getHistory(session.id, 50);
        // Remove the last message (the one we just added) since agent.run prepends it
        const prior = history.slice(0, -1);
        const response = await this.agent.run(runId, message, prior, () => {});
        this.sessions.addMessage(session.id, response);
        res.json({
          runId,
          response: response.content,
          toolUse: response.toolUse,
        });
      } catch (e: unknown) {
        res.status(500).json({ error: (e as Error).message });
      }
    });

    app.get("/api/tools", requireAuth, (_req, res) => {
      const tools = buildToolRegistry(this.config);
      const defs = Array.from(tools.values()).map((t) => t.definition);
      res.json(defs);
    });

    app.get("/api/config", requireAuth, (_req, res) => {
      const { tools, model, port, host, maxTokens, channels, cron } = this.config;
      res.json({ model, port, host, maxTokens, tools, channels, cronJobs: cron.length });
    });

    app.get("/api/skills", requireAuth, (_req, res) => {
      res.json(this.skills.getSkills().map((s) => ({ name: s.name, path: s.path })));
    });

    app.get("/api/channels", requireAuth, (_req, res) => {
      res.json({
        telegram: { enabled: this.config.channels.telegram.enabled },
        discord: { enabled: this.config.channels.discord.enabled },
      });
    });

    // Webhook endpoint for external triggers (cron services, GitHub, etc.)
    app.post("/api/webhook", requireAuth, async (req, res) => {
      const { message, sessionId, source } = req.body as {
        message?: string;
        sessionId?: string;
        source?: string;
      };
      if (!message) { res.status(400).json({ error: "message is required" }); return; }

      let sid = sessionId;
      if (!sid || !this.sessions.get(sid)) {
        const session = this.sessions.create(`webhook:${source || "external"}`);
        sid = session.id;
      }

      const userMsg: Message = {
        role: "user",
        content: `[Webhook${source ? ` from ${source}` : ""}] ${message}`,
        timestamp: Date.now(),
      };
      this.sessions.addMessage(sid, userMsg);

      const runId = randomUUID();
      const history = this.sessions.getHistory(sid, 30);
      const prior = history.slice(0, -1);

      try {
        const response = await this.agent.run(runId, message, prior, () => {});
        this.sessions.addMessage(sid, response);
        res.json({ runId, sessionId: sid, response: response.content });
      } catch (e: unknown) {
        res.status(500).json({ error: (e as Error).message });
      }
    });

    // ─── WebSocket Gateway ───────────────────────────────────────

    const server = createServer(app);
    const wss = new WebSocketServer({ server, path: "/ws" });

    wss.on("connection", (ws) => {
      const clientId = randomUUID();
      const client: WsClient = {
        id: clientId,
        ws,
        authenticated: false,
        subscribedSessions: new Set(),
      };
      this.clients.set(clientId, client);

      // Send challenge
      this.sendEvent(ws, "connect.challenge", { nonce: randomUUID() });

      ws.on("message", async (data) => {
        let frame: WireFrame;
        try {
          frame = JSON.parse(data.toString()) as WireFrame;
        } catch {
          return;
        }

        if (frame.type === "req") {
          await this.handleRequest(client, frame);
        }
      });

      ws.on("close", () => {
        this.clients.delete(clientId);
      });

      ws.on("error", () => {
        this.clients.delete(clientId);
      });
    });

    server.listen(this.config.port, this.config.host, async () => {
      console.log(`KMac Assistant Gateway`);
      console.log(`  HTTP:    http://${this.config.host}:${this.config.port}`);
      console.log(`  WS:     ws://${this.config.host}:${this.config.port}/ws`);
      console.log(`  Token:  ${this.authToken.slice(0, 8)}...`);
      console.log(`  Model:  ${this.config.model}`);

      const skillCount = this.skills.getSkills().length;
      if (skillCount > 0) {
        console.log(`  Skills: ${skillCount} loaded (${this.skills.getSkills().map(s => s.name).join(", ")})`);
      }

      // Start channel adapters (Telegram, Discord, etc.)
      await this.channelRouter.start();

      // Start cron scheduler
      this.cron.start();

      console.log("");
    });
  }

  getToken(): string {
    return this.authToken;
  }

  // ─── WebSocket Handlers ──────────────────────────────────────

  private async handleRequest(client: WsClient, frame: RequestFrame): Promise<void> {
    const { id, method, params } = frame;
    const p = (params || {}) as Record<string, unknown>;

    try {
      switch (method) {
        case "connect":
          await this.handleConnect(client, id, p);
          break;
        case "agent.run":
          await this.handleAgentRun(client, id, p);
          break;
        case "agent.stop":
          this.handleAgentStop(client, id, p);
          break;
        case "session.list":
          this.sendResponse(client.ws, id, true, this.sessions.list().map((s) => ({
            id: s.id,
            title: s.title,
            updatedAt: s.updatedAt,
            messageCount: s.messages.length,
          })));
          break;
        case "session.get":
          this.handleSessionGet(client, id, p);
          break;
        case "session.new":
          this.handleSessionNew(client, id, p);
          break;
        case "session.delete":
          this.handleSessionDelete(client, id, p);
          break;
        case "session.compact":
          this.handleSessionCompact(client, id, p);
          break;
        case "session.subscribe":
          if (p.sessionId) client.subscribedSessions.add(p.sessionId as string);
          this.sendResponse(client.ws, id, true, { subscribed: true });
          break;
        default:
          this.sendResponse(client.ws, id, false, undefined, {
            code: "unknown_method",
            message: `Unknown method: ${method}`,
          });
      }
    } catch (e: unknown) {
      this.sendResponse(client.ws, id, false, undefined, {
        code: "internal_error",
        message: (e as Error).message,
      });
    }
  }

  private async handleConnect(
    client: WsClient,
    reqId: string,
    params: Record<string, unknown>,
  ): Promise<void> {
    const auth = params.auth as Record<string, unknown> | undefined;
    const token = (auth?.token as string) || (params.token as string) || "";
    if (token !== this.authToken) {
      this.sendResponse(client.ws, reqId, false, undefined, {
        code: "auth_failed",
        message: "Invalid token",
      });
      return;
    }
    client.authenticated = true;
    this.sendResponse(client.ws, reqId, true, {
      protocol: 1,
      clientId: client.id,
      sessions: this.sessions.list().length,
    });
  }

  private async handleAgentRun(
    client: WsClient,
    reqId: string,
    params: Record<string, unknown>,
  ): Promise<void> {
    if (!client.authenticated) {
      this.sendResponse(client.ws, reqId, false, undefined, {
        code: "not_authenticated",
        message: "Must connect first",
      });
      return;
    }

    let sessionId = params.sessionId as string | undefined;
    const message = params.message as string;
    if (!message) {
      this.sendResponse(client.ws, reqId, false, undefined, {
        code: "invalid_params",
        message: "message is required",
      });
      return;
    }

    // Auto-create session if none specified
    if (!sessionId || !this.sessions.get(sessionId)) {
      const session = this.sessions.create();
      sessionId = session.id;
      this.broadcastEvent("session.created", { id: session.id, title: session.title });
    }

    const runId = randomUUID();
    this.sendResponse(client.ws, reqId, true, {
      runId,
      sessionId,
      status: "accepted",
    });

    // Add user message
    const userMsg: Message = { role: "user", content: message, timestamp: Date.now() };
    this.sessions.addMessage(sessionId, userMsg);

    // Run agent with streaming
    const history = this.sessions.getHistory(sessionId, 50);
    const prior = history.slice(0, -1);

    const onStream = (event: AgentStreamEvent) => {
      const eventPayload: Record<string, unknown> = {
        runId,
        sessionId,
        stream: event.type,
      };
      switch (event.type) {
        case "text":
          eventPayload.delta = event.content;
          break;
        case "tool_use":
          eventPayload.tool = event.toolName;
          eventPayload.input = event.toolInput;
          break;
        case "tool_result":
          eventPayload.tool = event.toolName;
          eventPayload.result = event.toolResult;
          break;
        case "done":
          eventPayload.usage = event.usage;
          break;
        case "error":
          eventPayload.error = event.content;
          break;
      }

      // Send to subscribers of this session + the requesting client
      for (const [, c] of this.clients) {
        if (
          c.ws.readyState === WebSocket.OPEN &&
          (c.id === client.id || c.subscribedSessions.has(sessionId!))
        ) {
          this.sendEvent(c.ws, "agent", eventPayload);
        }
      }
    };

    try {
      const response = await this.agent.run(runId, message, prior, onStream);
      this.sessions.addMessage(sessionId, response);
    } catch (e: unknown) {
      onStream({ type: "error", content: (e as Error).message });
    }
  }

  private handleAgentStop(
    _client: WsClient,
    reqId: string,
    params: Record<string, unknown>,
  ): void {
    const runId = params.runId as string;
    if (runId) this.agent.stop(runId);
    this.sendResponse(_client.ws, reqId, true, { stopped: true });
  }

  private handleSessionGet(
    client: WsClient,
    reqId: string,
    params: Record<string, unknown>,
  ): void {
    const session = this.sessions.get(params.sessionId as string);
    if (!session) {
      this.sendResponse(client.ws, reqId, false, undefined, {
        code: "not_found",
        message: "Session not found",
      });
      return;
    }
    this.sendResponse(client.ws, reqId, true, session);
  }

  private handleSessionNew(
    client: WsClient,
    reqId: string,
    params: Record<string, unknown>,
  ): void {
    const session = this.sessions.create(
      params.title as string | undefined,
      params.model as string | undefined,
    );
    this.broadcastEvent("session.created", { id: session.id, title: session.title });
    this.sendResponse(client.ws, reqId, true, {
      id: session.id,
      title: session.title,
    });
  }

  private handleSessionDelete(
    client: WsClient,
    reqId: string,
    params: Record<string, unknown>,
  ): void {
    this.sessions.delete(params.sessionId as string);
    this.sendResponse(client.ws, reqId, true, { deleted: true });
  }

  private handleSessionCompact(
    client: WsClient,
    reqId: string,
    params: Record<string, unknown>,
  ): void {
    try {
      const removed = this.sessions.compact(params.sessionId as string);
      this.sendResponse(client.ws, reqId, true, { removed });
    } catch (e: unknown) {
      this.sendResponse(client.ws, reqId, false, undefined, {
        code: "not_found",
        message: (e as Error).message,
      });
    }
  }

  // ─── Wire Helpers ────────────────────────────────────────────

  private sendResponse(
    ws: WebSocket,
    id: string,
    ok: boolean,
    payload?: unknown,
    error?: { code?: string; message?: string },
  ): void {
    if (ws.readyState !== WebSocket.OPEN) return;
    const frame: ResponseFrame = { type: "res", id, ok };
    if (payload !== undefined) frame.payload = payload;
    if (error) frame.error = error;
    ws.send(JSON.stringify(frame));
  }

  private sendEvent(
    ws: WebSocket,
    event: string,
    payload?: Record<string, unknown>,
  ): void {
    if (ws.readyState !== WebSocket.OPEN) return;
    const frame: EventFrame = {
      type: "event",
      event,
      payload,
      seq: ++this.eventSeq,
    };
    ws.send(JSON.stringify(frame));
  }

  private broadcastEvent(
    event: string,
    payload?: Record<string, unknown>,
  ): void {
    for (const [, client] of this.clients) {
      if (client.ws.readyState === WebSocket.OPEN && client.authenticated) {
        this.sendEvent(client.ws, event, payload);
      }
    }
  }
}
