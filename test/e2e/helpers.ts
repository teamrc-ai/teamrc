/**
 * E2E test helpers — keypair generation, signed HTTP requests, server readiness.
 *
 * Imports CLI crypto directly so we test the same signing code that ships.
 */

import * as ed from "@noble/ed25519";
import { sha512 } from "@noble/hashes/sha512";

// Required: set sha512Sync for @noble/ed25519 (same as cli/src/auth.ts)
ed.etc.sha512Sync = (...m: Uint8Array[]) => {
  const combined = new Uint8Array(m.reduce((sum, a) => sum + a.length, 0));
  let offset = 0;
  for (const arr of m) {
    combined.set(arr, offset);
    offset += arr.length;
  }
  return sha512(combined);
};

export const RELAY_URL = process.env.RELAY_URL ?? "http://localhost:4002";

// ─── Base64url helpers (same as CLI) ───

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

// ─── Keypair + token ───

export interface TestKeypair {
  privateKey: Uint8Array;
  publicKey: Uint8Array;
  token: string;
}

export async function generateTestKeypair(): Promise<TestKeypair> {
  const privateKey = ed.utils.randomPrivateKey();
  const publicKey = await ed.getPublicKeyAsync(privateKey);
  const token = "trc_ak_" + base64UrlEncode(publicKey);
  return { privateKey, publicKey, token };
}

async function signMessage(privateKey: Uint8Array, message: string): Promise<string> {
  const msgBytes = new TextEncoder().encode(message);
  const signature = await ed.signAsync(msgBytes, privateKey);
  return base64UrlEncode(signature);
}

// ─── Signed HTTP requests ───

interface SignedRequestOpts {
  relay?: string;
  privateKey: Uint8Array;
  token: string;
}

export async function signedPost(
  path: string,
  body: Record<string, unknown>,
  opts: SignedRequestOpts,
): Promise<Response> {
  const relay = opts.relay ?? RELAY_URL;
  const rawBody = JSON.stringify(body);
  const timestamp = Math.floor(Date.now() / 1000).toString();
  const message = `${timestamp}.${rawBody}`;
  const signature = await signMessage(opts.privateKey, message);

  return fetch(`${relay}${path}`, {
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

export async function signedGet(
  path: string,
  opts: SignedRequestOpts,
): Promise<Response> {
  const relay = opts.relay ?? RELAY_URL;
  const timestamp = Math.floor(Date.now() / 1000).toString();
  const message = `${timestamp}.GET ${path}`;
  const signature = await signMessage(opts.privateKey, message);

  return fetch(`${relay}${path}`, {
    method: "GET",
    headers: {
      "X-Teamrc-Version": "1",
      "x-trc-signature": signature,
      "x-trc-timestamp": timestamp,
      "x-trc-token": opts.token,
    },
    signal: AbortSignal.timeout(10_000),
  });
}

export async function signedDelete(
  path: string,
  opts: SignedRequestOpts,
): Promise<Response> {
  const relay = opts.relay ?? RELAY_URL;
  const timestamp = Math.floor(Date.now() / 1000).toString();
  const message = `${timestamp}.DELETE ${path}`;
  const signature = await signMessage(opts.privateKey, message);

  return fetch(`${relay}${path}`, {
    method: "DELETE",
    headers: {
      "X-Teamrc-Version": "1",
      "x-trc-signature": signature,
      "x-trc-timestamp": timestamp,
      "x-trc-token": opts.token,
    },
    signal: AbortSignal.timeout(10_000),
  });
}

export async function unsignedGet(path: string, relay?: string): Promise<Response> {
  return fetch(`${relay ?? RELAY_URL}${path}`, {
    method: "GET",
    headers: { "X-Teamrc-Version": "1" },
    signal: AbortSignal.timeout(10_000),
  });
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

// ─── Convenience: create a team and return everything ───

export async function createTeamWithKeypair(
  name: string,
  members: Array<{ name: string; role: string; skills?: string[] }>,
  opts?: { skills?: Array<{ id: string; body: string; alwaysApply?: boolean }>; knowledge?: string },
) {
  const kp = await generateTestKeypair();
  const body: Record<string, unknown> = {
    token: kp.token,
    team: {
      name,
      members,
      ...(opts?.skills ? { skills: opts.skills } : {}),
      ...(opts?.knowledge ? { knowledge: opts.knowledge } : {}),
    },
  };
  const res = await signedPost("/api/teams", body, kp);
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`createTeamWithKeypair failed: ${res.status} ${text}`);
  }
  const data = (await res.json()) as { team: Record<string, unknown> };
  return { ...kp, team: data.team, teamId: data.team.id as string };
}
