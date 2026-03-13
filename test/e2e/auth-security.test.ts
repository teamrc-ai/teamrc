import { describe, it, before } from "node:test";
import assert from "node:assert/strict";
import * as ed from "@noble/ed25519";
import { sha512 } from "@noble/hashes/sha512";
import {
  waitForServer,
  generateTestKeypair,
  signedPost,
  signedGet,
  RELAY_URL,
} from "./helpers.ts";

// Ensure sha512Sync is set
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

before(async () => {
  await waitForServer();
});

describe("Auth security", () => {
  it("accepts a valid POST signature", async () => {
    const kp = await generateTestKeypair();
    const res = await signedPost(
      "/api/teams",
      {
        token: kp.token,
        team: { name: "auth-valid-post", members: [{ name: "A", role: "R" }] },
      },
      kp,
    );
    assert.equal(res.status, 201);
  });

  it("accepts a valid GET signature", async () => {
    const kp = await generateTestKeypair();
    // Create a team first
    await signedPost(
      "/api/teams",
      {
        token: kp.token,
        team: { name: "auth-valid-get", members: [{ name: "A", role: "R" }] },
      },
      kp,
    );
    const res = await signedGet(`/api/teams/all/${kp.token}`, kp);
    assert.equal(res.status, 200);
  });

  it("rejects missing signature header", async () => {
    const kp = await generateTestKeypair();
    const body = JSON.stringify({
      token: kp.token,
      team: { name: "no-sig", members: [{ name: "A", role: "R" }] },
    });
    const res = await fetch(`${RELAY_URL}/api/teams`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Teamrc-Version": "1",
        "x-trc-timestamp": Math.floor(Date.now() / 1000).toString(),
      },
      body,
      signal: AbortSignal.timeout(10_000),
    });
    assert.equal(res.status, 401);
    const data = (await res.json()) as { reason: string };
    assert.ok(data.reason.includes("signature"), `reason should mention signature: ${data.reason}`);
  });

  it("rejects wrong private key (BOLA prevention)", async () => {
    const victim = await generateTestKeypair();
    const attacker = await generateTestKeypair();

    // Attacker signs a request but uses victim's token
    const body = JSON.stringify({
      token: victim.token, // victim's token
      team: { name: "bola-test", members: [{ name: "A", role: "R" }] },
    });
    const timestamp = Math.floor(Date.now() / 1000).toString();
    const message = `${timestamp}.${body}`;
    const msgBytes = new TextEncoder().encode(message);
    const signature = await ed.signAsync(msgBytes, attacker.privateKey); // attacker's key

    const res = await fetch(`${RELAY_URL}/api/teams`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Teamrc-Version": "1",
        "x-trc-signature": base64UrlEncode(signature),
        "x-trc-timestamp": timestamp,
      },
      body,
      signal: AbortSignal.timeout(10_000),
    });
    assert.equal(res.status, 401);
  });

  it("rejects tampered body", async () => {
    const kp = await generateTestKeypair();
    const originalBody = JSON.stringify({
      token: kp.token,
      team: { name: "tamper-test", members: [{ name: "A", role: "R" }] },
    });
    const timestamp = Math.floor(Date.now() / 1000).toString();
    const message = `${timestamp}.${originalBody}`;
    const msgBytes = new TextEncoder().encode(message);
    const signature = await ed.signAsync(msgBytes, kp.privateKey);

    // Tamper with the body after signing
    const tamperedBody = JSON.stringify({
      token: kp.token,
      team: { name: "tamper-HACKED", members: [{ name: "A", role: "R" }] },
    });

    const res = await fetch(`${RELAY_URL}/api/teams`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Teamrc-Version": "1",
        "x-trc-signature": base64UrlEncode(signature),
        "x-trc-timestamp": timestamp,
      },
      body: tamperedBody,
      signal: AbortSignal.timeout(10_000),
    });
    assert.equal(res.status, 401);
  });

  it("rejects expired timestamp (>30s old)", async () => {
    const kp = await generateTestKeypair();
    const body = JSON.stringify({
      token: kp.token,
      team: { name: "expired-ts", members: [{ name: "A", role: "R" }] },
    });
    const staleTimestamp = (Math.floor(Date.now() / 1000) - 60).toString(); // 60s ago
    const message = `${staleTimestamp}.${body}`;
    const msgBytes = new TextEncoder().encode(message);
    const signature = await ed.signAsync(msgBytes, kp.privateKey);

    const res = await fetch(`${RELAY_URL}/api/teams`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Teamrc-Version": "1",
        "x-trc-signature": base64UrlEncode(signature),
        "x-trc-timestamp": staleTimestamp,
      },
      body,
      signal: AbortSignal.timeout(10_000),
    });
    assert.equal(res.status, 401);
    const data = (await res.json()) as { reason: string };
    assert.ok(data.reason.includes("timestamp"), `reason should mention timestamp: ${data.reason}`);
  });

  it("rejects missing timestamp header", async () => {
    const kp = await generateTestKeypair();
    const body = JSON.stringify({
      token: kp.token,
      team: { name: "no-ts", members: [{ name: "A", role: "R" }] },
    });
    const timestamp = Math.floor(Date.now() / 1000).toString();
    const message = `${timestamp}.${body}`;
    const msgBytes = new TextEncoder().encode(message);
    const signature = await ed.signAsync(msgBytes, kp.privateKey);

    const res = await fetch(`${RELAY_URL}/api/teams`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Teamrc-Version": "1",
        "x-trc-signature": base64UrlEncode(signature),
        // No x-trc-timestamp header
      },
      body,
      signal: AbortSignal.timeout(10_000),
    });
    assert.equal(res.status, 401);
    const data = (await res.json()) as { reason: string };
    assert.ok(data.reason.includes("timestamp"), `reason should mention timestamp: ${data.reason}`);
  });
});
