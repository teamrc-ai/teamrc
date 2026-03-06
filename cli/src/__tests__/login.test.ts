import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { generateKeypair, signMessage, toToken } from "../auth.js";

// Mock fetch for testing client methods
function createMockFetch(response: { status: number; body: unknown }) {
  return async (_url: string | URL, _opts?: RequestInit) => ({
    ok: response.status >= 200 && response.status < 300,
    status: response.status,
    json: async () => response.body,
    text: async () => JSON.stringify(response.body),
  });
}

// We test the client methods by importing the class directly
import { TeamrcClient } from "../client.js";

describe("device auth client methods", () => {
  it("createDeviceAuth sends signed POST and returns device info", async () => {
    const kp = await generateKeypair();
    const token = toToken(kp.publicKey);

    const deviceResponse = {
      device_code: "dc_test123",
      user_code: "ABCD-1234",
      verification_url: "https://teamrc.dev/auth/verify",
      expires_in: 300,
      interval: 5,
    };

    let capturedUrl = "";
    let capturedMethod = "";
    let capturedHeaders: Record<string, string> = {};

    const originalFetch = globalThis.fetch;
    globalThis.fetch = async (url: string | URL, opts?: RequestInit) => {
      capturedUrl = url.toString();
      capturedMethod = opts?.method ?? "GET";
      capturedHeaders = Object.fromEntries(
        Object.entries(opts?.headers ?? {}),
      );
      return {
        ok: true,
        status: 200,
        json: async () => deviceResponse,
        text: async () => JSON.stringify(deviceResponse),
      } as Response;
    };

    try {
      const client = new TeamrcClient("http://localhost:4000", kp.privateKey, token);
      const result = await client.createDeviceAuth();

      assert.equal(capturedUrl, "http://localhost:4000/api/auth/device");
      assert.equal(capturedMethod, "POST");
      assert.equal(capturedHeaders["Content-Type"], "application/json");
      assert.ok(capturedHeaders["x-tb-signature"]);
      assert.ok(capturedHeaders["x-tb-timestamp"]);

      assert.equal(result.device_code, "dc_test123");
      assert.equal(result.user_code, "ABCD-1234");
      assert.equal(result.verification_url, "https://teamrc.dev/auth/verify");
      assert.equal(result.expires_in, 300);
      assert.equal(result.interval, 5);
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  it("pollDeviceAuth returns pending status", async () => {
    const kp = await generateKeypair();
    const token = toToken(kp.publicKey);

    const pendingResponse = { status: "pending" };

    let capturedUrl = "";
    let capturedMethod = "";

    const originalFetch = globalThis.fetch;
    globalThis.fetch = async (url: string | URL, opts?: RequestInit) => {
      capturedUrl = url.toString();
      capturedMethod = opts?.method ?? "GET";
      return {
        ok: true,
        status: 200,
        json: async () => pendingResponse,
        text: async () => JSON.stringify(pendingResponse),
      } as Response;
    };

    try {
      const client = new TeamrcClient("http://localhost:4000", kp.privateKey, token);
      const result = await client.pollDeviceAuth("dc_test123");

      assert.equal(capturedUrl, "http://localhost:4000/api/auth/device/dc_test123");
      assert.equal(capturedMethod, "GET");
      assert.equal(result.status, "pending");
      assert.equal(result.email, undefined);
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  it("pollDeviceAuth returns confirmed status with account info", async () => {
    const kp = await generateKeypair();
    const token = toToken(kp.publicKey);

    const confirmedResponse = {
      status: "confirmed",
      email: "ben@example.com",
      machine_count: 1,
      team_count: 2,
    };

    const originalFetch = globalThis.fetch;
    globalThis.fetch = async (_url: string | URL, _opts?: RequestInit) => {
      return {
        ok: true,
        status: 200,
        json: async () => confirmedResponse,
        text: async () => JSON.stringify(confirmedResponse),
      } as Response;
    };

    try {
      const client = new TeamrcClient("http://localhost:4000", kp.privateKey, token);
      const result = await client.pollDeviceAuth("dc_test123");

      assert.equal(result.status, "confirmed");
      assert.equal(result.email, "ben@example.com");
      assert.equal(result.machine_count, 1);
      assert.equal(result.team_count, 2);
    } finally {
      globalThis.fetch = originalFetch;
    }
  });
});
