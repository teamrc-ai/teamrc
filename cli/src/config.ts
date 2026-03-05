import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";

export interface TeambridgeConfig {
  platform: string;
  relay: string;
  token: string;
  teamId?: string;
}

function getConfigDir(): string {
  return path.join(os.homedir(), ".teambridge");
}

function getConfigPath(): string {
  return path.join(getConfigDir(), "config.json");
}

export function loadConfig(): TeambridgeConfig | null {
  const configPath = getConfigPath();
  if (!fs.existsSync(configPath)) {
    return null;
  }
  try {
    const raw = fs.readFileSync(configPath, "utf-8");
    return JSON.parse(raw) as TeambridgeConfig;
  } catch {
    return null;
  }
}

export function saveConfig(config: TeambridgeConfig): void {
  const dir = getConfigDir();
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
  fs.writeFileSync(getConfigPath(), JSON.stringify(config, null, 2));
}

export function detectPlatform(): string | null {
  const home = os.homedir();
  if (fs.existsSync(path.join(home, ".claude"))) {
    return "claude-code";
  }
  if (fs.existsSync(path.join(home, ".openclaw"))) {
    return "openclaw";
  }
  return null;
}

export function getRelayUrl(overrideUrl?: string): string {
  if (overrideUrl) {
    return overrideUrl;
  }
  const envUrl = process.env["TEAMBRIDGE_RELAY"];
  if (envUrl) {
    return envUrl;
  }
  const config = loadConfig();
  if (config?.relay) {
    return config.relay;
  }
  return "http://localhost:4000";
}
