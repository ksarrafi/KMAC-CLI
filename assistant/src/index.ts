import { writeFileSync, mkdirSync, unlinkSync } from "node:fs";
import { join } from "node:path";
import { loadConfig, getConfigDir } from "./config.js";
import { Gateway } from "./gateway.js";

const config = loadConfig();

// Ensure data directory exists
mkdirSync(config.dataDir, { recursive: true, mode: 0o700 });

// Start gateway
const gateway = new Gateway(config);
gateway.start();

// Write token + PID for the CLI wrapper
const runDir = join(getConfigDir(), "run");
mkdirSync(runDir, { recursive: true, mode: 0o700 });
writeFileSync(join(runDir, "gateway.pid"), String(process.pid), { mode: 0o600 });
writeFileSync(join(runDir, "gateway.token"), gateway.getToken(), { mode: 0o600 });
writeFileSync(
  join(runDir, "gateway.json"),
  JSON.stringify({
    pid: process.pid,
    host: config.host,
    port: config.port,
    model: config.model,
    startedAt: new Date().toISOString(),
  }),
  { mode: 0o600 },
);

// Graceful shutdown
function cleanup() {
  console.log("\nShutting down...");
  try { unlinkSync(join(runDir, "gateway.pid")); } catch { /* ignore */ }
  process.exit(0);
}

process.on("SIGINT", cleanup);
process.on("SIGTERM", cleanup);
