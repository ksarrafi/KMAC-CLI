import { execSync, spawn } from "node:child_process";
import {
  readFileSync,
  writeFileSync,
  existsSync,
  readdirSync,
  statSync,
} from "node:fs";
import { join, resolve, basename } from "node:path";
import { homedir, hostname, platform, arch, cpus, totalmem, freemem } from "node:os";
import type { ToolEntry, ToolResult, AssistantConfig } from "./types.js";

function ok(output: string): ToolResult {
  return { output };
}
function err(message: string): ToolResult {
  return { output: message, error: message, isError: true };
}

// ─── Bash Tool ─────────────────────────────────────────────────────────

const bashTool: ToolEntry = {
  definition: {
    name: "bash",
    description:
      "Execute a shell command and return stdout+stderr. Use for running programs, installing packages, git operations, and system tasks. Commands run in the user's default shell.",
    input_schema: {
      type: "object",
      properties: {
        command: {
          type: "string",
          description: "The shell command to execute",
        },
        cwd: {
          type: "string",
          description: "Working directory (default: home directory)",
        },
        timeout: {
          type: "number",
          description: "Timeout in milliseconds (default: 30000)",
        },
      },
      required: ["command"],
    },
  },
  handler: async (input) => {
    const command = input.command as string;
    const cwd = (input.cwd as string) || homedir();
    const timeout = (input.timeout as number) || 30000;

    try {
      const result = execSync(command, {
        cwd,
        timeout,
        maxBuffer: 1024 * 1024,
        encoding: "utf-8",
        stdio: ["pipe", "pipe", "pipe"],
        env: { ...process.env, HOME: homedir() },
      });
      return ok(result || "(no output)");
    } catch (e: unknown) {
      const error = e as { stdout?: string; stderr?: string; status?: number; message?: string };
      const stdout = error.stdout || "";
      const stderr = error.stderr || "";
      const exitCode = error.status ?? 1;
      return err(
        `Exit code ${exitCode}\n${stdout}${stderr ? "\nSTDERR:\n" + stderr : ""}`.trim(),
      );
    }
  },
};

// ─── File Tools ────────────────────────────────────────────────────────

const readFileTool: ToolEntry = {
  definition: {
    name: "read_file",
    description:
      "Read the contents of a file. Returns the full text content. For large files, use offset and limit to read a portion.",
    input_schema: {
      type: "object",
      properties: {
        path: { type: "string", description: "Absolute or relative file path" },
        offset: { type: "number", description: "Line number to start from (1-based)" },
        limit: { type: "number", description: "Number of lines to read" },
      },
      required: ["path"],
    },
  },
  handler: async (input) => {
    const filePath = resolve(input.path as string);
    if (!existsSync(filePath)) return err(`File not found: ${filePath}`);
    try {
      const content = readFileSync(filePath, "utf-8");
      const offset = input.offset as number | undefined;
      const limit = input.limit as number | undefined;
      if (offset || limit) {
        const lines = content.split("\n");
        const start = Math.max(0, (offset ?? 1) - 1);
        const end = limit ? start + limit : lines.length;
        return ok(
          lines
            .slice(start, end)
            .map((l, i) => `${String(start + i + 1).padStart(6)}|${l}`)
            .join("\n"),
        );
      }
      if (content.length > 100_000) {
        return ok(content.slice(0, 100_000) + "\n... (truncated, file is " + content.length + " bytes)");
      }
      return ok(content);
    } catch (e: unknown) {
      return err(`Failed to read: ${(e as Error).message}`);
    }
  },
};

const writeFileTool: ToolEntry = {
  definition: {
    name: "write_file",
    description: "Write content to a file. Creates the file if it doesn't exist, overwrites if it does.",
    input_schema: {
      type: "object",
      properties: {
        path: { type: "string", description: "Absolute or relative file path" },
        content: { type: "string", description: "Content to write" },
      },
      required: ["path", "content"],
    },
  },
  handler: async (input) => {
    const filePath = resolve(input.path as string);
    try {
      writeFileSync(filePath, input.content as string);
      return ok(`Written to ${filePath}`);
    } catch (e: unknown) {
      return err(`Failed to write: ${(e as Error).message}`);
    }
  },
};

const editFileTool: ToolEntry = {
  definition: {
    name: "edit_file",
    description:
      "Edit a file by replacing an exact string match with new text. The old_string must match exactly (including whitespace).",
    input_schema: {
      type: "object",
      properties: {
        path: { type: "string", description: "File path" },
        old_string: { type: "string", description: "Exact text to find and replace" },
        new_string: { type: "string", description: "Replacement text" },
        replace_all: { type: "boolean", description: "Replace all occurrences (default: false)" },
      },
      required: ["path", "old_string", "new_string"],
    },
  },
  handler: async (input) => {
    const filePath = resolve(input.path as string);
    if (!existsSync(filePath)) return err(`File not found: ${filePath}`);
    try {
      let content = readFileSync(filePath, "utf-8");
      const oldStr = input.old_string as string;
      const newStr = input.new_string as string;
      if (!content.includes(oldStr)) return err("old_string not found in file");
      if (input.replace_all) {
        content = content.split(oldStr).join(newStr);
      } else {
        const idx = content.indexOf(oldStr);
        content = content.slice(0, idx) + newStr + content.slice(idx + oldStr.length);
      }
      writeFileSync(filePath, content);
      return ok(`Edited ${filePath}`);
    } catch (e: unknown) {
      return err(`Failed to edit: ${(e as Error).message}`);
    }
  },
};

const listFilesTool: ToolEntry = {
  definition: {
    name: "list_files",
    description: "List files and directories at a given path. Shows names, sizes, and types.",
    input_schema: {
      type: "object",
      properties: {
        path: { type: "string", description: "Directory path to list" },
        recursive: { type: "boolean", description: "List recursively (default: false, max 200 entries)" },
        pattern: { type: "string", description: "Glob pattern to filter (e.g. '*.ts')" },
      },
      required: ["path"],
    },
  },
  handler: async (input) => {
    const dirPath = resolve(input.path as string);
    if (!existsSync(dirPath)) return err(`Path not found: ${dirPath}`);

    if (input.pattern) {
      try {
        const result = execSync(
          `find ${JSON.stringify(dirPath)} -maxdepth ${input.recursive ? 5 : 1} -name ${JSON.stringify(input.pattern)} 2>/dev/null | head -200`,
          { encoding: "utf-8", timeout: 5000 },
        );
        return ok(result || "(no matches)");
      } catch {
        return ok("(no matches)");
      }
    }

    try {
      const entries = readdirSync(dirPath, { withFileTypes: true });
      const lines = entries.slice(0, 200).map((e) => {
        const full = join(dirPath, e.name);
        if (e.isDirectory()) return `  ${e.name}/`;
        try {
          const s = statSync(full);
          const size = s.size < 1024 ? `${s.size}B` : s.size < 1048576 ? `${(s.size / 1024).toFixed(0)}K` : `${(s.size / 1048576).toFixed(1)}M`;
          return `  ${e.name}  (${size})`;
        } catch {
          return `  ${e.name}`;
        }
      });
      return ok(lines.join("\n"));
    } catch (e: unknown) {
      return err(`Failed to list: ${(e as Error).message}`);
    }
  },
};

const grepTool: ToolEntry = {
  definition: {
    name: "grep",
    description: "Search for a pattern in files using ripgrep. Returns matching lines with file paths and line numbers.",
    input_schema: {
      type: "object",
      properties: {
        pattern: { type: "string", description: "Regex pattern to search for" },
        path: { type: "string", description: "Directory or file to search in" },
        glob: { type: "string", description: "File glob filter (e.g. '*.ts')" },
        case_insensitive: { type: "boolean", description: "Case insensitive search" },
      },
      required: ["pattern", "path"],
    },
  },
  handler: async (input) => {
    const args = ["rg", "--max-count=50", "--line-number"];
    if (input.case_insensitive) args.push("-i");
    if (input.glob) args.push("--glob", input.glob as string);
    args.push(input.pattern as string, resolve(input.path as string));

    try {
      const result = execSync(args.join(" "), {
        encoding: "utf-8",
        timeout: 10000,
        maxBuffer: 512 * 1024,
      });
      return ok(result || "(no matches)");
    } catch (e: unknown) {
      const error = e as { stdout?: string; status?: number };
      if (error.status === 1) return ok("(no matches)");
      return err(error.stdout || "Search failed");
    }
  },
};

// ─── Web Tool ──────────────────────────────────────────────────────────

const webFetchTool: ToolEntry = {
  definition: {
    name: "web_fetch",
    description: "Fetch content from a URL and return it as text. Useful for checking APIs, downloading data, or reading web pages.",
    input_schema: {
      type: "object",
      properties: {
        url: { type: "string", description: "URL to fetch" },
        method: { type: "string", description: "HTTP method (default: GET)" },
        headers: {
          type: "object",
          description: "Request headers",
          additionalProperties: { type: "string" },
        },
        body: { type: "string", description: "Request body (for POST/PUT)" },
      },
      required: ["url"],
    },
  },
  handler: async (input) => {
    const url = input.url as string;
    const method = (input.method as string) || "GET";
    try {
      const opts: RequestInit = {
        method,
        headers: (input.headers as Record<string, string>) || {},
        signal: AbortSignal.timeout(15000),
      };
      if (input.body) opts.body = input.body as string;
      const res = await fetch(url, opts);
      const text = await res.text();
      const truncated = text.length > 50_000 ? text.slice(0, 50_000) + "\n...(truncated)" : text;
      return ok(`HTTP ${res.status} ${res.statusText}\n\n${truncated}`);
    } catch (e: unknown) {
      return err(`Fetch failed: ${(e as Error).message}`);
    }
  },
};

// ─── System Tool ───────────────────────────────────────────────────────

const systemInfoTool: ToolEntry = {
  definition: {
    name: "system_info",
    description:
      "Get system information: hostname, OS, CPU, memory, disk, uptime, and running processes.",
    input_schema: {
      type: "object",
      properties: {
        section: {
          type: "string",
          enum: ["overview", "processes", "disk", "network"],
          description: "Which info section (default: overview)",
        },
      },
    },
  },
  handler: async (input) => {
    const section = (input.section as string) || "overview";
    switch (section) {
      case "processes":
        try {
          const ps = execSync("ps aux --sort=-%mem 2>/dev/null | head -20 || ps aux | head -20", {
            encoding: "utf-8",
            timeout: 5000,
          });
          return ok(ps);
        } catch {
          return ok("(could not list processes)");
        }
      case "disk":
        try {
          return ok(execSync("df -h", { encoding: "utf-8", timeout: 5000 }));
        } catch {
          return ok("(could not get disk info)");
        }
      case "network":
        try {
          const ifconfig = execSync(
            "ifconfig 2>/dev/null | grep -E 'inet |flags' | head -20 || ip addr show 2>/dev/null | head -20",
            { encoding: "utf-8", timeout: 5000 },
          );
          return ok(ifconfig);
        } catch {
          return ok("(could not get network info)");
        }
      default: {
        const totalMem = (totalmem() / 1073741824).toFixed(1);
        const freeMem = (freemem() / 1073741824).toFixed(1);
        const upSec = process.uptime();
        const info = [
          `Hostname: ${hostname()}`,
          `Platform: ${platform()} ${arch()}`,
          `CPUs:     ${cpus().length}x ${cpus()[0]?.model || "unknown"}`,
          `Memory:   ${freeMem} GB free / ${totalMem} GB total`,
          `Node:     ${process.version}`,
          `Uptime:   ${Math.floor(upSec / 3600)}h ${Math.floor((upSec % 3600) / 60)}m`,
          `User:     ${homedir().split("/").pop()}`,
          `CWD:      ${process.cwd()}`,
        ];
        return ok(info.join("\n"));
      }
    }
  },
};

// ─── Registry ──────────────────────────────────────────────────────────

export function buildToolRegistry(config: AssistantConfig): Map<string, ToolEntry> {
  const registry = new Map<string, ToolEntry>();

  if (config.tools.bash.enabled) {
    registry.set("bash", bashTool);
  }
  if (config.tools.files.enabled) {
    registry.set("read_file", readFileTool);
    registry.set("write_file", writeFileTool);
    registry.set("edit_file", editFileTool);
    registry.set("list_files", listFilesTool);
    registry.set("grep", grepTool);
  }
  if (config.tools.web.enabled) {
    registry.set("web_fetch", webFetchTool);
  }
  if (config.tools.system.enabled) {
    registry.set("system_info", systemInfoTool);
  }

  return registry;
}
