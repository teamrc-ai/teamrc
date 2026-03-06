import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";

export interface TeamrcConfig {
  platform: string;
  relay: string;
  token: string;
  teamId?: string;
  account?: {
    email: string;
  };
  machineName?: string;
}

function getConfigDir(): string {
  return path.join(os.homedir(), ".teamrc");
}

function getConfigPath(): string {
  return path.join(getConfigDir(), "config.json");
}

export function loadConfig(): TeamrcConfig | null {
  const configPath = getConfigPath();
  if (!fs.existsSync(configPath)) {
    return null;
  }
  try {
    const raw = fs.readFileSync(configPath, "utf-8");
    return JSON.parse(raw) as TeamrcConfig;
  } catch {
    return null;
  }
}

export function saveConfig(config: TeamrcConfig): void {
  const dir = getConfigDir();
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true, mode: 0o700 });
  }
  fs.writeFileSync(getConfigPath(), JSON.stringify(config, null, 2), { mode: 0o600 });
}

export function detectPlatforms(): string[] {
  const home = os.homedir();
  const platforms: string[] = [];
  if (fs.existsSync(path.join(home, ".claude"))) {
    platforms.push("claude-code");
  }
  if (fs.existsSync(path.join(home, ".openclaw"))) {
    platforms.push("openclaw");
  }
  if (fs.existsSync(path.join(process.cwd(), ".cursor"))) {
    platforms.push("cursor");
  }
  if (fs.existsSync(path.join(home, ".codex")) || fs.existsSync(path.join(process.cwd(), ".codex"))) {
    platforms.push("codex");
  }
  if (fs.existsSync(path.join(process.cwd(), ".gemini")) || fs.existsSync(path.join(home, ".gemini"))) {
    platforms.push("gemini");
  }
  return platforms;
}

export function getRelayUrl(overrideUrl?: string): string {
  if (overrideUrl) {
    return overrideUrl;
  }
  const envUrl = process.env["TEAMRC_RELAY"];
  if (envUrl) {
    return envUrl;
  }
  const config = loadConfig();
  if (config?.relay) {
    return config.relay;
  }
  return "http://localhost:4000";
}
