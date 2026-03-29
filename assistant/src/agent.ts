import Anthropic from "@anthropic-ai/sdk";
import type { AssistantConfig, ToolEntry, Message } from "./types.js";

export interface AgentStreamEvent {
  type: "text" | "tool_use" | "tool_result" | "done" | "error";
  content?: string;
  toolName?: string;
  toolInput?: unknown;
  toolResult?: string;
  usage?: { inputTokens: number; outputTokens: number };
}

export type StreamCallback = (event: AgentStreamEvent) => void;

export class Agent {
  private client: Anthropic;
  private config: AssistantConfig;
  private tools: Map<string, ToolEntry>;
  private abortControllers = new Map<string, AbortController>();

  constructor(config: AssistantConfig, tools: Map<string, ToolEntry>) {
    this.config = config;
    this.tools = tools;
    this.client = new Anthropic(); // uses ANTHROPIC_API_KEY env var
  }

  async run(
    runId: string,
    userMessage: string,
    history: Message[],
    onStream: StreamCallback,
  ): Promise<Message> {
    const controller = new AbortController();
    this.abortControllers.set(runId, controller);

    try {
      return await this.agentLoop(runId, userMessage, history, onStream, controller);
    } finally {
      this.abortControllers.delete(runId);
    }
  }

  stop(runId: string): void {
    const controller = this.abortControllers.get(runId);
    if (controller) {
      controller.abort();
      this.abortControllers.delete(runId);
    }
  }

  private async agentLoop(
    runId: string,
    userMessage: string,
    history: Message[],
    onStream: StreamCallback,
    controller: AbortController,
  ): Promise<Message> {
    const messages = this.buildMessages(history, userMessage);
    const toolDefs = this.getToolDefinitions();
    let fullResponse = "";
    const toolUses: { name: string; input: unknown }[] = [];

    const MAX_ITERATIONS = 25;
    let iteration = 0;

    while (iteration < MAX_ITERATIONS) {
      iteration++;
      if (controller.signal.aborted) throw new Error("Agent run aborted");

      const streamParams: Anthropic.MessageCreateParams = {
        model: this.config.model,
        max_tokens: this.config.maxTokens,
        system: this.config.systemPrompt,
        messages,
        ...(toolDefs.length > 0 ? { tools: toolDefs as Anthropic.Tool[] } : {}),
      };

      const stream = this.client.messages.stream(streamParams);
      let stopReason: string | null = null;
      const contentBlocks: Anthropic.ContentBlock[] = [];

      stream.on("text", (text) => {
        fullResponse += text;
        onStream({ type: "text", content: text });
      });

      const finalMessage = await stream.finalMessage();
      stopReason = finalMessage.stop_reason;
      contentBlocks.push(...finalMessage.content);

      if (stopReason === "tool_use") {
        // Process all tool_use blocks
        const toolBlocks = contentBlocks.filter(
          (b): b is Anthropic.ToolUseBlock => b.type === "tool_use",
        );
        const toolResults: Anthropic.ToolResultBlockParam[] = [];

        for (const toolBlock of toolBlocks) {
          if (controller.signal.aborted) throw new Error("Agent run aborted");

          onStream({
            type: "tool_use",
            toolName: toolBlock.name,
            toolInput: toolBlock.input,
          });

          toolUses.push({ name: toolBlock.name, input: toolBlock.input });
          const result = await this.executeTool(
            toolBlock.name,
            toolBlock.input as Record<string, unknown>,
          );

          onStream({
            type: "tool_result",
            toolName: toolBlock.name,
            toolResult: result,
          });

          toolResults.push({
            type: "tool_result",
            tool_use_id: toolBlock.id,
            content: result,
          });
        }

        // Add assistant message + tool results, then loop
        messages.push({
          role: "assistant",
          content: contentBlocks.map((b) => {
            if (b.type === "text") return { type: "text" as const, text: b.text };
            if (b.type === "tool_use")
              return {
                type: "tool_use" as const,
                id: b.id,
                name: b.name,
                input: b.input as Record<string, unknown>,
              };
            return { type: "text" as const, text: "" };
          }),
        });
        messages.push({ role: "user", content: toolResults });

        continue;
      }

      // End of response (end_turn or max_tokens)
      onStream({
        type: "done",
        usage: {
          inputTokens: finalMessage.usage.input_tokens,
          outputTokens: finalMessage.usage.output_tokens,
        },
      });

      return {
        role: "assistant",
        content: fullResponse,
        timestamp: Date.now(),
        toolUse: toolUses.length > 0 ? toolUses : undefined,
      };
    }

    onStream({ type: "error", content: "Max tool iterations reached" });
    return {
      role: "assistant",
      content: fullResponse || "(max iterations reached)",
      timestamp: Date.now(),
      toolUse: toolUses.length > 0 ? toolUses : undefined,
    };
  }

  private buildMessages(
    history: Message[],
    userMessage: string,
  ): Anthropic.MessageParam[] {
    const msgs: Anthropic.MessageParam[] = [];
    for (const m of history) {
      msgs.push({ role: m.role, content: m.content });
    }
    msgs.push({ role: "user", content: userMessage });
    return msgs;
  }

  private getToolDefinitions(): Anthropic.Tool[] {
    return Array.from(this.tools.values()).map((t) => ({
      name: t.definition.name,
      description: t.definition.description,
      input_schema: t.definition.input_schema as Anthropic.Tool.InputSchema,
    }));
  }

  private async executeTool(
    name: string,
    input: Record<string, unknown>,
  ): Promise<string> {
    const tool = this.tools.get(name);
    if (!tool) return `Unknown tool: ${name}`;
    try {
      const result = await tool.handler(input);
      const text = result.output || "(no output)";
      // Cap tool output to avoid blowing context
      return text.length > 30_000
        ? text.slice(0, 30_000) + "\n...(truncated)"
        : text;
    } catch (e: unknown) {
      return `Tool error: ${(e as Error).message}`;
    }
  }
}
