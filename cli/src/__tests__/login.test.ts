import { describe, it, afterEach } from "node:test";
import assert from "node:assert/strict";
import { generateKeypair, toToken } from "../auth.js";

// We test the client methods by importing the class directly
import { TeamrcClient } from "../client.js";

// ---------------------------------------------------------------------------
// Helpers: centralized mockFetch / restoreFetch pattern
// ---------------------------------------------------------------------------

interface CapturedCall {
  url: string;
  init?: RequestInit;
}

let captured: CapturedCall[] = [];
const originalFetch = globalThis.fetch;

function mockFetch(response: object, status = 200) {
  captured = [];
  globalThis.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = typeof input === "string" ? input : input.toString();
    captured.push({ url, init });
    return new Response(JSON.stringify(response), {
      status,
      headers: { "Content-Type": "application/json" },
    });
  }) as typeof fetch;
}

function restoreFetch() {
  globalThis.fetch = originalFetch;
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

describe("device auth client methods", () => {
  afterEach(() => restoreFetch());

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

    mockFetch(deviceResponse);

    const client = new TeamrcClient("http://localhost:4000", kp.privateKey, token);
    const result = await client.createDeviceAuth();

    assert.equal(captured.length, 1);
    assert.equal(captured[0].url, "http://localhost:4000/api/auth/device");
    assert.equal(captured[0].init?.method, "POST");

    const headers = captured[0].init?.headers as Record<string, string>;
    assert.equal(headers["Content-Type"], "application/json");
    assert.ok(headers["x-trc-signature"]);
    assert.ok(headers["x-trc-timestamp"]);

    assert.equal(result.device_code, "dc_test123");
    assert.equal(result.user_code, "ABCD-1234");
    assert.equal(result.verification_url, "https://teamrc.dev/auth/verify");
    assert.equal(result.expires_in, 300);
    assert.equal(result.interval, 5);
  });

  it("pollDeviceAuth returns pending status", async () => {
    const kp = await generateKeypair();
    const token = toToken(kp.publicKey);

    mockFetch({ status: "pending" });

    const client = new TeamrcClient("http://localhost:4000", kp.privateKey, token);
    const result = await client.pollDeviceAuth("dc_test123");

    assert.equal(captured.length, 1);
    assert.equal(captured[0].url, "http://localhost:4000/api/auth/device/dc_test123");
    assert.equal(captured[0].init?.method, "GET");
    assert.equal(result.status, "pending");
    assert.equal(result.email, undefined);
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

    mockFetch(confirmedResponse);

    const client = new TeamrcClient("http://localhost:4000", kp.privateKey, token);
    const result = await client.pollDeviceAuth("dc_test123");

    assert.equal(result.status, "confirmed");
    assert.equal(result.email, "ben@example.com");
    assert.equal(result.machine_count, 1);
    assert.equal(result.team_count, 2);
  });
});
