import { writeFileSync, mkdirSync, unlinkSync } from "node:fs";
import { join } from "node:path";
import { loadConfig, getConfigDir } from "./config.js";
import { OrchestratorServer } from "./server.js";

const config = loadConfig();
const runDir = join(getConfigDir(), "run");
mkdirSync(runDir, { recursive: true });

const PID_FILE = join(runDir, "orchestrator.pid");
const INFO_FILE = join(runDir, "orchestrator.json");

const server = new OrchestratorServer(config);

function cleanup(): void {
  try { unlinkSync(PID_FILE); } catch { /* ok */ }
  try { unlinkSync(INFO_FILE); } catch { /* ok */ }
}

process.on("SIGTERM", async () => {
  console.log("\nShutting down...");
  await server.stop();
  cleanup();
  process.exit(0);
});

process.on("SIGINT", async () => {
  console.log("\nShutting down...");
  await server.stop();
  cleanup();
  process.exit(0);
});

async function main(): Promise<void> {
  console.log("KMac Orchestrator starting...");
  await server.start();

  writeFileSync(PID_FILE, String(process.pid));
  writeFileSync(INFO_FILE, JSON.stringify({
    pid: process.pid,
    port: config.port,
    host: config.host,
    startedAt: new Date().toISOString(),
    agents: config.agents.filter((a) => a.enabled).map((a) => ({ id: a.id, name: a.name, type: a.type })),
  }, null, 2));

  console.log(`  PID: ${process.pid}`);
  console.log(`  Agents: ${config.agents.filter((a) => a.enabled).length}`);
  console.log("  Ready.");
}

main().catch((err) => {
  console.error("Fatal:", err);
  cleanup();
  process.exit(1);
});
