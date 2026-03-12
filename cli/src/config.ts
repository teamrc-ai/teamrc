import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";

export interface TeamrcConfig {
  token: string;
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
    const parsed = JSON.parse(raw);
    // Strip legacy `relay` field — relay is no longer persisted in global config
    if (parsed && typeof parsed === "object") {
      delete parsed.relay;
    }
    return parsed as TeamrcConfig;
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
  // Strip relay — it must never be persisted in global config
  const { relay: _relay, ...clean } = config as TeamrcConfig & { relay?: unknown };
  fs.writeFileSync(getConfigPath(), JSON.stringify(clean, null, 2), { mode: 0o600 });
}

export function detectPlatforms(scope?: "project" | "global"): string[] {
  const home = os.homedir();
  const cwd = process.cwd();
  const platforms: string[] = [];

  // Signals split by where they detect: home dir (global) vs cwd (project)
  const globalSignals: Record<string, () => boolean> = {
    "claude-code": () => fs.existsSync(path.join(home, ".claude")),
    "codex": () => fs.existsSync(path.join(home, ".codex")),
    "gemini": () => fs.existsSync(path.join(home, ".gemini")),
    "openclaw": () => fs.existsSync(path.join(home, ".openclaw")),
    "amazon-q": () => fs.existsSync(path.join(home, ".amazonq")),
  };

  const projectSignals: Record<string, () => boolean> = {
    "cursor": () => fs.existsSync(path.join(cwd, ".cursor")),
    "codex": () => fs.existsSync(path.join(cwd, ".codex")),
    "gemini": () => fs.existsSync(path.join(cwd, ".gemini")),
    "copilot": () => fs.existsSync(path.join(cwd, ".github")),
    "amazon-q": () => fs.existsSync(path.join(cwd, ".amazonq")),
    "windsurf": () => fs.existsSync(path.join(cwd, ".windsurf")),
    "cline": () => fs.existsSync(path.join(cwd, ".clinerules")) || fs.existsSync(path.join(cwd, ".cline")),
  };

  const found = new Set<string>();

  if (scope !== "project") {
    for (const [name, check] of Object.entries(globalSignals)) {
      if (check()) found.add(name);
    }
  }

  if (scope !== "global") {
    for (const [name, check] of Object.entries(projectSignals)) {
      if (check()) found.add(name);
    }
  }

  platforms.push(...found);
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

export function getRelayUrl(overrideUrl?: string, yamlRelay?: string): string {
  if (overrideUrl) {
    validateRelayUrl(overrideUrl);
    return overrideUrl;
  }
  const envUrl = process.env["TEAMRC_RELAY"];
  if (envUrl) {
    validateRelayUrl(envUrl);
    return envUrl;
  }
  if (yamlRelay) {
    validateRelayUrl(yamlRelay);
    return yamlRelay;
  }
  return "https://teamrc.ai";
}
