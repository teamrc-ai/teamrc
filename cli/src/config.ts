import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";

export interface TeamrcConfig {
  token: string;
  relay: string;
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
  fs.chmodSync(dir, 0o700);
  fs.writeFileSync(getConfigPath(), JSON.stringify(config, null, 2), { mode: 0o600 });
}

export function detectPlatforms(): string[] {
  const home = os.homedir();
  const cwd = process.cwd();
  const platforms: string[] = [];

  const signals: Record<string, () => boolean> = {
    "claude-code": () => fs.existsSync(path.join(home, ".claude")),
    "cursor": () => fs.existsSync(path.join(cwd, ".cursor")),
    "codex": () => fs.existsSync(path.join(home, ".codex")) || fs.existsSync(path.join(cwd, ".codex")),
    "gemini": () => fs.existsSync(path.join(cwd, ".gemini")) || fs.existsSync(path.join(home, ".gemini")),
    "openclaw": () => fs.existsSync(path.join(home, ".agents")) || fs.existsSync(path.join(cwd, ".agents")),
    "copilot": () => fs.existsSync(path.join(cwd, ".github")),
    "amazon-q": () => fs.existsSync(path.join(home, ".amazonq")) || fs.existsSync(path.join(cwd, ".amazonq")),
    "windsurf": () => fs.existsSync(path.join(cwd, ".windsurf")),
    "cline": () => fs.existsSync(path.join(cwd, ".clinerules")) || fs.existsSync(path.join(cwd, ".cline")),
  };

  for (const [name, check] of Object.entries(signals)) {
    if (check()) platforms.push(name);
  }
  return platforms;
}

function isLocalUrl(url: string): boolean {
  try {
    const parsed = new URL(url);
    return parsed.hostname === "localhost" || parsed.hostname === "127.0.0.1" || parsed.hostname === "::1";
  } catch { return false; }
}

export function validateRelayUrl(url: string): void {
  if (!url.startsWith("https://") && !isLocalUrl(url)) {
    throw new Error(`Relay URL must use HTTPS for non-local servers: ${url}`);
  }
}

export function getRelayUrl(overrideUrl?: string): string {
  if (overrideUrl) {
    validateRelayUrl(overrideUrl);
    return overrideUrl;
  }
  const envUrl = process.env["TEAMRC_RELAY"];
  if (envUrl) {
    validateRelayUrl(envUrl);
    return envUrl;
  }
  const config = loadConfig();
  if (config?.relay) {
    return config.relay;
  }
  return "http://localhost:4000";
}
