import { describe, it, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";
import { TeamrcClient } from "../client.js";

// ---------------------------------------------------------------------------
// Helpers: We test the client by intercepting globalThis.fetch to inspect
// what options the client passes (signal, method, headers, body).
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

// Dummy key bytes (32 bytes for ed25519 private key — the signMessage call
// will be exercised but we only care about fetch options here).
const dummyKey = new Uint8Array(32);
const dummyToken = "trc_ak_AAAAAAAAAAAAAAAAAAAAAA";

describe("TeamrcClient fetch timeouts", () => {
  afterEach(() => restoreFetch());

  it("FETCH_TIMEOUT_MS is 30000", () => {
    assert.equal(TeamrcClient.FETCH_TIMEOUT_MS, 30_000);
  });

  it("createTeam sends signal with timeout", async () => {
    mockFetch({ team: { id: "t1", name: "t", members: [] } }, 201);
    const client = new TeamrcClient("http://localhost:4000", dummyKey, dummyToken);
    await client.createTeam("t", [{ name: "a", role: "r" }]);
    assert.equal(captured.length, 1);
    assert.ok(captured[0].init?.signal, "signal should be set on fetch");
  });

  it("joinByInvite sends signal with timeout", async () => {
    mockFetch({ team: { id: "t1", name: "t", members: [] } });
    const client = new TeamrcClient("http://localhost:4000", dummyKey, dummyToken);
    await client.joinByInvite("trc_inv_abc");
    assert.equal(captured.length, 1);
    assert.ok(captured[0].init?.signal, "signal should be set on fetch");
  });

  it("pushTeam sends signal with timeout", async () => {
    mockFetch({ team: { id: "t1", name: "t", members: [] } });
    const client = new TeamrcClient("http://localhost:4000", dummyKey, dummyToken);
    await client.pushTeam({ name: "t", members: [{ name: "a", role: "r" }] });
    assert.equal(captured.length, 1);
    assert.ok(captured[0].init?.signal, "signal should be set on fetch");
  });

  it("getTeam sends signal with timeout (via signedGet)", async () => {
    mockFetch({ team: { id: "t1", name: "t", members: [] } });
    const client = new TeamrcClient("http://localhost:4000", dummyKey, dummyToken);
    await client.getTeam();
    assert.equal(captured.length, 1);
    assert.ok(captured[0].init?.signal, "signal should be set on fetch");
  });

  it("cloneByToken sends signal with timeout", async () => {
    mockFetch({ team: { id: "t1", name: "t", members: [] } });
    const client = new TeamrcClient("http://localhost:4000", dummyKey, dummyToken);
    await client.cloneByToken("trc_cl_abc");
    assert.equal(captured.length, 1);
    assert.ok(captured[0].init?.signal, "signal should be set on fetch");
  });

  it("createInvite sends signal with timeout", async () => {
    mockFetch({ invite_code: "trc_inv_x", expires_at: "2026-01-01" });
    const client = new TeamrcClient("http://localhost:4000", dummyKey, dummyToken);
    await client.createInvite(24);
    assert.equal(captured.length, 1);
    assert.ok(captured[0].init?.signal, "signal should be set on fetch");
  });

  it("createDeviceAuth sends signal with timeout", async () => {
    mockFetch({ device_code: "dc", user_code: "uc", verification_url: "http://x", expires_in: 300, interval: 5 });
    const client = new TeamrcClient("http://localhost:4000", dummyKey, dummyToken);
    await client.createDeviceAuth();
    assert.equal(captured.length, 1);
    assert.ok(captured[0].init?.signal, "signal should be set on fetch");
  });

  it("previewByInvite sends signal with timeout", async () => {
    mockFetch({ team: { id: "t1", name: "t", members: [] } });
    const client = new TeamrcClient("http://localhost:4000", dummyKey, dummyToken);
    await client.previewByInvite("trc_inv_abc");
    assert.equal(captured.length, 1);
    assert.ok(captured[0].init?.signal, "signal should be set on fetch");
  });

  it("eraseToken sends signal with timeout and uses DELETE method", async () => {
    mockFetch({ status: "erased", teams_removed: 2 });
    const client = new TeamrcClient("http://localhost:4000", dummyKey, dummyToken);
    const result = await client.eraseToken();
    assert.equal(captured.length, 1);
    assert.ok(captured[0].init?.signal, "signal should be set on fetch");
    assert.equal(captured[0].init?.method, "DELETE");
    assert.equal(result.teams_removed, 2);
  });
});

describe("TeamrcClient cloneByToken error handling", () => {
  afterEach(() => restoreFetch());

  it("uses shared errorMessage format instead of leaking raw body", async () => {
    mockFetch({ error: "not_found" }, 404);
    const client = new TeamrcClient("http://localhost:4000", dummyKey, dummyToken);
    await assert.rejects(
      () => client.cloneByToken("trc_cl_bad"),
      (err: Error) => {
        // Should use the shared "context: status message" format
        assert.match(err.message, /clone failed: 404/);
        // Should NOT contain raw HTML or full response body
        assert.doesNotMatch(err.message, /<html/i);
        return true;
      },
    );
  });

  it("handles non-JSON error response gracefully", async () => {
    captured = [];
    globalThis.fetch = (async () => {
      return new Response("Internal Server Error", {
        status: 500,
        headers: { "Content-Type": "text/plain" },
      });
    }) as typeof fetch;

    const client = new TeamrcClient("http://localhost:4000", dummyKey, dummyToken);
    await assert.rejects(
      () => client.cloneByToken("trc_cl_bad"),
      (err: Error) => {
        assert.match(err.message, /clone failed: 500/);
        return true;
      },
    );
  });
});

describe("TeamrcClient pushTeam source body resolution", () => {
  let tmpDir: string;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "trc-push-"));
  });

  afterEach(() => {
    restoreFetch();
    fs.rmSync(tmpDir, { recursive: true });
  });

  it("resolves source-body skills to file content before sending", async () => {
    fs.writeFileSync(path.join(tmpDir, "rules.md"), "Be careful with SQL.");

    mockFetch({ team: { id: "t1", name: "t", members: [] } });
    const client = new TeamrcClient("http://localhost:4000", dummyKey, dummyToken);
    await client.pushTeam(
      {
        name: "test",
        members: [{ name: "agent", role: "dev" }],
        skills: [{ id: "sql_safety", body: { source: "./rules.md" } }],
      },
      undefined,
      tmpDir,
    );

    assert.equal(captured.length, 1);
    const sentBody = JSON.parse(captured[0].init?.body as string);
    assert.equal(sentBody.team.skills[0].body, "Be careful with SQL.");
    assert.equal(sentBody.team.skills[0].id, "sql_safety");
  });

  it("passes string-body skills through unchanged", async () => {
    mockFetch({ team: { id: "t1", name: "t", members: [] } });
    const client = new TeamrcClient("http://localhost:4000", dummyKey, dummyToken);
    await client.pushTeam(
      {
        name: "test",
        members: [{ name: "agent", role: "dev" }],
        skills: [{ id: "inline", body: "Just a string body." }],
      },
      undefined,
      tmpDir,
    );

    const sentBody = JSON.parse(captured[0].init?.body as string);
    assert.equal(sentBody.team.skills[0].body, "Just a string body.");
  });

  it("throws error when source file cannot be read", async () => {
    mockFetch({ team: { id: "t1", name: "t", members: [] } });
    const client = new TeamrcClient("http://localhost:4000", dummyKey, dummyToken);

    await assert.rejects(
      () =>
        client.pushTeam(
          {
            name: "test",
            members: [{ name: "agent", role: "dev" }],
            skills: [{ id: "missing", body: { source: "./nonexistent.md" } }],
          },
          undefined,
          tmpDir,
        ),
      (err: Error) => {
        assert.match(err.message, /Skill "missing" references source/);
        return true;
      },
    );
  });
});
