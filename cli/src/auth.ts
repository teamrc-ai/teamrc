import * as ed from "@noble/ed25519";
import { sha512 } from "@noble/hashes/sha512";
import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";

// Required: set sha512Sync for @noble/ed25519 synchronous operations
ed.etc.sha512Sync = (...m: Uint8Array[]) => {
  const combined = new Uint8Array(m.reduce((sum, a) => sum + a.length, 0));
  let offset = 0;
  for (const arr of m) {
    combined.set(arr, offset);
    offset += arr.length;
  }
  return sha512(combined);
};

export interface Keypair {
  privateKey: Uint8Array;
  publicKey: Uint8Array;
}

function base64UrlEncode(data: Uint8Array): string {
  return Buffer.from(data)
    .toString("base64")
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

function base64UrlDecode(str: string): Uint8Array {
  let base64 = str.replace(/-/g, "+").replace(/_/g, "/");
  while (base64.length % 4 !== 0) {
    base64 += "=";
  }
  return new Uint8Array(Buffer.from(base64, "base64"));
}

export async function generateKeypair(): Promise<Keypair> {
  const privateKey = ed.utils.randomPrivateKey();
  const publicKey = await ed.getPublicKeyAsync(privateKey);
  return { privateKey, publicKey };
}

function getKeyDir(): string {
  return path.join(os.homedir(), ".teamrc");
}

function getKeyPath(): string {
  return path.join(getKeyDir(), "key");
}

export function saveKeypair(kp: Keypair): void {
  const dir = getKeyDir();
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true, mode: 0o700 });
  }
  fs.chmodSync(dir, 0o700);
  const data = JSON.stringify({
    privateKey: base64UrlEncode(kp.privateKey),
    publicKey: base64UrlEncode(kp.publicKey),
  });
  fs.writeFileSync(getKeyPath(), data, { mode: 0o600 });
}

export function loadKeypair(): Keypair | null {
  const keyPath = getKeyPath();
  if (!fs.existsSync(keyPath)) {
    return null;
  }
  try {
    const raw = fs.readFileSync(keyPath, "utf-8");
    const parsed = JSON.parse(raw) as {
      privateKey: string;
      publicKey: string;
    };
    return {
      privateKey: base64UrlDecode(parsed.privateKey),
      publicKey: base64UrlDecode(parsed.publicKey),
    };
  } catch (e) {
    // File exists but couldn't be parsed  --  warn the user
    console.warn(`Warning: Could not parse keypair file at ${keyPath}: ${e instanceof Error ? e.message : e}`);
    return null;
  }
}

export function toToken(publicKey: Uint8Array): string {
  return "trc_ak_" + base64UrlEncode(publicKey);
}

export async function signMessage(
  privateKey: Uint8Array,
  message: string,
): Promise<string> {
  const msgBytes = new TextEncoder().encode(message);
  const signature = await ed.signAsync(msgBytes, privateKey);
  return base64UrlEncode(signature);
}
