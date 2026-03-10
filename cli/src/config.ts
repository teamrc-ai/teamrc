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
  } catch (e) {
    // File exists but couldn't be parsed — warn the user
    console.warn(`Warning: Could not parse config file at ${configPath}: ${e instanceof Error ? e.message : e}`);
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
    "openclaw": () => fs.existsSync(path.join(home, ".openclaw")),
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
    const host = parsed.hostname.replace(/^\[|\]$/g, ""); // strip IPv6 brackets
    if (host === "localhost" || host === "::1" || host === "0.0.0.0") return true;
    // Full IPv4 loopback range 127.0.0.0/8
    if (/^127\.\d{1,3}\.\d{1,3}\.\d{1,3}$/.test(host)) return true;
    // IPv4-mapped IPv6
    if (host.toLowerCase().startsWith("::ffff:127.")) return true;
    return false;
  } catch {
    return false;
  }
}

export function validateRelayUrl(url: string): void {
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    throw new Error(`Invalid relay URL: ${url}`);
  }
  if (parsed.protocol !== "https:" && parsed.protocol !== "http:") {
    throw new Error(`Relay URL must use http or https: ${url}`);
  }
  if (parsed.protocol === "http:" && !isLocalUrl(url)) {
    throw new Error(`HTTP relay URLs are only allowed for local development (localhost/127.x.x.x). Use HTTPS for remote relays: ${url}`);
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
    validateRelayUrl(config.relay);
    return config.relay;
  }
  return "http://localhost:4000";
}
