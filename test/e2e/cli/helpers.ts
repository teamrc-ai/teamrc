/**
 * CLI subprocess E2E test helpers.
 *
 * Spawns the real `teamrc` CLI as a child process in isolated temp directories
 * with HOME overridden to prevent cross-contamination.
 */

import { spawn, execSync, type ChildProcess } from "node:child_process";
import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";

import { fileURLToPath } from "node:url";

export const RELAY_URL = process.env.RELAY_URL ?? "http://localhost:4002";

// Path to the CLI entry point (run via tsx)
const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT_DIR = path.resolve(__dirname, "..", "..", "..");
const CLI_ENTRY = path.join(ROOT_DIR, "cli", "src", "index.ts");
const TSX_BIN = path.join(ROOT_DIR, "cli", "node_modules", ".bin", "tsx");

// ─── Isolated environment ───

export interface IsolatedEnv {
  home: string;
  projectDir: string;
  env: Record<string, string>;
  cleanup: () => void;
}

/**
 * Create a fully isolated environment for CLI tests.
 * - Fresh HOME directory (isolates ~/.teamrc/key, config.json)
 * - Fresh project directory (isolates .teamrc.yaml, platform files)
 * - TEAMRC_RELAY pointed at localhost test server
 */
export function createIsolatedEnv(name?: string): IsolatedEnv {
  const base = fs.mkdtempSync(path.join(os.tmpdir(), `trc-e2e-${name ?? "test"}-`));
  const home = path.join(base, "home");
  const projectDir = path.join(base, "project");
  fs.mkdirSync(home, { recursive: true });
  fs.mkdirSync(projectDir, { recursive: true });

  // Create a .gitignore so init doesn't fail
  fs.writeFileSync(path.join(projectDir, ".gitignore"), "node_modules/\n");

  const env: Record<string, string> = {
    HOME: home,
    TEAMRC_RELAY: RELAY_URL,
    NO_COLOR: "1",
    NO_BROWSER: "1",
    // Ensure tsx can find node
    PATH: process.env.PATH ?? "",
    // Needed for node crypto
    NODE_OPTIONS: process.env.NODE_OPTIONS ?? "",
  };

  return {
    home,
    projectDir,
    env,
    cleanup: () => {
      try {
        fs.rmSync(base, { recursive: true, force: true });
      } catch {
        // best effort
      }
    },
  };
}

// ─── CLI runner (blocking) ───

export interface CliResult {
  stdout: string;
  stderr: string;
  exitCode: number;
}

/**
 * Run a CLI command and wait for it to complete.
 * Returns stdout, stderr, and exit code.
 */
export function runCli(
  args: string[],
  env: IsolatedEnv,
  opts?: { cwd?: string; timeout?: number },
): Promise<CliResult> {
  const cwd = opts?.cwd ?? env.projectDir;
  const timeout = opts?.timeout ?? 30_000;

  return new Promise((resolve) => {
    const child = spawn(TSX_BIN, [CLI_ENTRY, ...args], {
      cwd,
      env: env.env,
      stdio: ["pipe", "pipe", "pipe"],
      timeout,
    });

    let stdout = "";
    let stderr = "";

    child.stdout.on("data", (chunk: Buffer) => {
      stdout += chunk.toString();
    });

    child.stderr.on("data", (chunk: Buffer) => {
      stderr += chunk.toString();
    });

    // Close stdin immediately to signal non-interactive
    child.stdin.end();

    child.on("close", (code) => {
      resolve({ stdout, stderr, exitCode: code ?? 1 });
    });

    child.on("error", (err) => {
      resolve({ stdout, stderr: stderr + "\n" + err.message, exitCode: 1 });
    });
  });
}

// ─── CLI runner (streaming, for long-running commands like login/daemon) ───

export interface StreamingCli {
  process: ChildProcess;
  stdout: string;
  waitForOutput: (pattern: RegExp, timeoutMs?: number) => Promise<string>;
  kill: (signal?: NodeJS.Signals) => void;
  waitForExit: (timeoutMs?: number) => Promise<CliResult>;
}

/**
 * Spawn a CLI command that runs in the background.
 * Use waitForOutput() to detect specific patterns in stdout.
 */
export function spawnCli(
  args: string[],
  env: IsolatedEnv,
  opts?: { cwd?: string },
): StreamingCli {
  const cwd = opts?.cwd ?? env.projectDir;

  const child = spawn(TSX_BIN, [CLI_ENTRY, ...args], {
    cwd,
    env: env.env,
    stdio: ["pipe", "pipe", "pipe"],
  });

  let stdout = "";
  let stderr = "";
  const listeners: Array<{ pattern: RegExp; resolve: (match: string) => void }> = [];

  child.stdout.on("data", (chunk: Buffer) => {
    const text = chunk.toString();
    stdout += text;

    // Check if any waitForOutput listeners match
    for (let i = listeners.length - 1; i >= 0; i--) {
      const match = stdout.match(listeners[i].pattern);
      if (match) {
        listeners[i].resolve(match[0]);
        listeners.splice(i, 1);
      }
    }
  });

  child.stderr.on("data", (chunk: Buffer) => {
    stderr += chunk.toString();
  });

  // Don't close stdin — some commands may need it open
  // But we don't write to it (non-interactive via !isTTY)

  return {
    process: child,
    get stdout() {
      return stdout;
    },
    waitForOutput(pattern: RegExp, timeoutMs = 15_000): Promise<string> {
      // Check if already matched
      const existing = stdout.match(pattern);
      if (existing) return Promise.resolve(existing[0]);

      return new Promise((resolve, reject) => {
        const timer = setTimeout(() => {
          reject(new Error(
            `Timed out waiting for pattern ${pattern} after ${timeoutMs}ms.\nStdout so far: ${stdout}\nStderr: ${stderr}`,
          ));
        }, timeoutMs);

        listeners.push({
          pattern,
          resolve: (match) => {
            clearTimeout(timer);
            resolve(match);
          },
        });
      });
    },
    kill(signal: NodeJS.Signals = "SIGTERM") {
      child.kill(signal);
    },
    waitForExit(timeoutMs = 15_000): Promise<CliResult> {
      return new Promise((resolve, reject) => {
        const timer = setTimeout(() => {
          child.kill("SIGKILL");
          reject(new Error(`Process did not exit within ${timeoutMs}ms`));
        }, timeoutMs);

        child.on("close", (code) => {
          clearTimeout(timer);
          resolve({ stdout, stderr, exitCode: code ?? 1 });
        });
      });
    },
  };
}

// ─── Test setup helper (calls server-side /api/test/setup) ───

export async function testSetup(
  action: string,
  params: Record<string, unknown> = {},
): Promise<Record<string, unknown>> {
  const res = await fetch(`${RELAY_URL}/api/test/setup`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ action, ...params }),
    signal: AbortSignal.timeout(10_000),
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`test/setup ${action} failed: ${res.status} ${text}`);
  }
  return (await res.json()) as Record<string, unknown>;
}

// ─── Server readiness ───

export async function waitForServer(timeoutMs = 30_000): Promise<void> {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    try {
      const res = await fetch(`${RELAY_URL}/health`, {
        signal: AbortSignal.timeout(2_000),
      });
      if (res.ok) return;
    } catch {
      // server not ready yet
    }
    await new Promise((r) => setTimeout(r, 500));
  }
  throw new Error(`Server not ready after ${timeoutMs}ms`);
}

// ─── File helpers ───

/** Read .teamrc.yaml as text */
export function readYaml(env: IsolatedEnv, scope: "project" | "global" = "project"): string {
  const yamlPath = scope === "global"
    ? path.join(env.home, ".teamrc", "team.yaml")
    : path.join(env.projectDir, ".teamrc.yaml");
  return fs.readFileSync(yamlPath, "utf-8");
}

/** Check if a file exists relative to the project dir */
export function fileExists(env: IsolatedEnv, relativePath: string): boolean {
  return fs.existsSync(path.join(env.projectDir, relativePath));
}

/** Read a file relative to the project dir */
export function readFile(env: IsolatedEnv, relativePath: string): string {
  return fs.readFileSync(path.join(env.projectDir, relativePath), "utf-8");
}

/** Write a file relative to the project dir */
export function writeFile(env: IsolatedEnv, relativePath: string, content: string): void {
  const fullPath = path.join(env.projectDir, relativePath);
  fs.mkdirSync(path.dirname(fullPath), { recursive: true });
  fs.writeFileSync(fullPath, content);
}

/** List files matching a glob-like prefix in the project dir */
export function listFiles(env: IsolatedEnv, dir: string): string[] {
  const fullDir = path.join(env.projectDir, dir);
  if (!fs.existsSync(fullDir)) return [];
  return fs.readdirSync(fullDir);
}

/** Read the config.json from the isolated HOME */
export function readConfig(env: IsolatedEnv): Record<string, unknown> | null {
  const configPath = path.join(env.home, ".teamrc", "config.json");
  if (!fs.existsSync(configPath)) return null;
  return JSON.parse(fs.readFileSync(configPath, "utf-8"));
}

/** Read the keypair key file from the isolated HOME */
export function readKey(env: IsolatedEnv): Record<string, string> | null {
  const keyPath = path.join(env.home, ".teamrc", "key");
  if (!fs.existsSync(keyPath)) return null;
  return JSON.parse(fs.readFileSync(keyPath, "utf-8"));
}

/** Get token from the isolated env's config/keypair */
export function getToken(env: IsolatedEnv): string | null {
  const config = readConfig(env);
  if (config?.token) return config.token as string;
  const key = readKey(env);
  if (!key?.publicKey) return null;
  // Reconstruct token from public key
  return "trc_ak_" + key.publicKey;
}

/** Read .teamrc.yaml and extract teamId */
export function getTeamId(env: IsolatedEnv, scope: "project" | "global" = "project"): string | null {
  try {
    const yaml = readYaml(env, scope);
    const match = yaml.match(/teamId:\s*(.+)/);
    return match ? match[1].trim() : null;
  } catch {
    return null;
  }
}

/** Write content to the .teamrc.yaml */
export function writeYaml(env: IsolatedEnv, content: string, scope: "project" | "global" = "project"): void {
  const yamlPath = scope === "global"
    ? path.join(env.home, ".teamrc", "team.yaml")
    : path.join(env.projectDir, ".teamrc.yaml");
  fs.mkdirSync(path.dirname(yamlPath), { recursive: true });
  fs.writeFileSync(yamlPath, content);
}

// ─── YAML helpers ───

import YAML from "yaml";
export { YAML };

/** Parse .teamrc.yaml into an object, edit it, and write back */
export function editTeamYaml(
  env: IsolatedEnv,
  editor: (parsed: Record<string, unknown>) => void,
  scope: "project" | "global" = "project",
): void {
  const yamlText = readYaml(env, scope);
  const parsed = YAML.parse(yamlText);
  editor(parsed);
  writeYaml(env, YAML.stringify(parsed), scope);
}

// ─── Signed HTTP helpers (for verifying relay state from tests) ───

import * as ed from "@noble/ed25519";
import { sha512 } from "@noble/hashes/sha512";

ed.etc.sha512Sync = (...m: Uint8Array[]) => {
  const combined = new Uint8Array(m.reduce((sum, a) => sum + a.length, 0));
  let offset = 0;
  for (const arr of m) {
    combined.set(arr, offset);
    offset += arr.length;
  }
  return sha512(combined);
};

function base64UrlEncode(data: Uint8Array): string {
  return Buffer.from(data)
    .toString("base64")
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

function base64UrlDecode(str: string): Uint8Array {
  let base64 = str.replace(/-/g, "+").replace(/_/g, "/");
  while (base64.length % 4 !== 0) base64 += "=";
  return new Uint8Array(Buffer.from(base64, "base64"));
}

async function signMessage(privateKey: Uint8Array, message: string): Promise<string> {
  const msgBytes = new TextEncoder().encode(message);
  const signature = await ed.signAsync(msgBytes, privateKey);
  return base64UrlEncode(signature);
}

/** Load keypair from an isolated env and make signed API calls */
export function loadKeypairFromEnv(env: IsolatedEnv): { privateKey: Uint8Array; publicKey: Uint8Array; token: string } | null {
  const key = readKey(env);
  if (!key) return null;
  const privateKey = base64UrlDecode(key.privateKey);
  const publicKey = base64UrlDecode(key.publicKey);
  const token = "trc_ak_" + key.publicKey;
  return { privateKey, publicKey, token };
}

export async function signedGet(
  pathStr: string,
  kp: { privateKey: Uint8Array; token: string },
): Promise<Response> {
  const timestamp = Math.floor(Date.now() / 1000).toString();
  const message = `${timestamp}.GET ${pathStr}`;
  const signature = await signMessage(kp.privateKey, message);

  return fetch(`${RELAY_URL}${pathStr}`, {
    method: "GET",
    headers: {
      "X-Teamrc-Version": "1",
      "x-trc-signature": signature,
      "x-trc-timestamp": timestamp,
      "x-trc-token": kp.token,
    },
    signal: AbortSignal.timeout(10_000),
  });
}

export async function signedPost(
  pathStr: string,
  body: Record<string, unknown>,
  kp: { privateKey: Uint8Array; token: string },
): Promise<Response> {
  const rawBody = JSON.stringify(body);
  const timestamp = Math.floor(Date.now() / 1000).toString();
  const message = `${timestamp}.${rawBody}`;
  const signature = await signMessage(kp.privateKey, message);

  return fetch(`${RELAY_URL}${pathStr}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Teamrc-Version": "1",
      "x-trc-signature": signature,
      "x-trc-timestamp": timestamp,
    },
    body: rawBody,
    signal: AbortSignal.timeout(10_000),
  });
}
