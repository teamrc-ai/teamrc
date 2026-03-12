import { describe, it, afterEach } from "node:test";
import assert from "node:assert/strict";
import { TeamrcClient, SyncConflictError, UpgradeRequiredError } from "../client.js";

// ---------------------------------------------------------------------------
// Helpers: intercept globalThis.fetch (same pattern as client-security.test.ts)
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

const dummyKey = new Uint8Array(32);
const dummyToken = "trc_ak_AAAAAAAAAAAAAAAAAAAAAA";

// ---------------------------------------------------------------------------
// SyncConflictError on 409 push
// ---------------------------------------------------------------------------

describe("TeamrcClient SyncConflictError", () => {
  afterEach(() => restoreFetch());

  it("pushTeam throws SyncConflictError with server hash on 409", async () => {
    mockFetch({ server_hash: "abc123" }, 409);
    const client = new TeamrcClient("http://localhost:4000", dummyKey, dummyToken);

    await assert.rejects(
      () => client.pushTeam({ name: "t", members: [{ name: "a", role: "r" }] }),
      (err: unknown) => {
        assert.ok(err instanceof SyncConflictError);
        assert.equal(err.serverHash, "abc123");
        assert.match(err.message, /pull/i);
        return true;
      },
    );
  });
});

// ---------------------------------------------------------------------------
// UpgradeRequiredError on 426
// ---------------------------------------------------------------------------

describe("TeamrcClient UpgradeRequiredError", () => {
  afterEach(() => restoreFetch());

  it("getTeam throws UpgradeRequiredError on 426", async () => {
    mockFetch({ error: "upgrade_required" }, 426);
    const client = new TeamrcClient("http://localhost:4000", dummyKey, dummyToken);

    await assert.rejects(
      () => client.getTeam(),
      (err: unknown) => {
        assert.ok(err instanceof UpgradeRequiredError);
        assert.match(err.message, /outdated/i);
        return true;
      },
    );
  });

  it("pushTeam throws UpgradeRequiredError on 426", async () => {
    mockFetch({ error: "upgrade_required" }, 426);
    const client = new TeamrcClient("http://localhost:4000", dummyKey, dummyToken);

    await assert.rejects(
      () => client.pushTeam({ name: "t", members: [{ name: "a", role: "r" }] }),
      (err: unknown) => {
        assert.ok(err instanceof UpgradeRequiredError);
        return true;
      },
    );
  });

  it("createTeam throws UpgradeRequiredError on 426", async () => {
    mockFetch({ error: "upgrade_required" }, 426);
    const client = new TeamrcClient("http://localhost:4000", dummyKey, dummyToken);

    await assert.rejects(
      () => client.createTeam("t", [{ name: "a", role: "r" }]),
      (err: unknown) => {
        assert.ok(err instanceof UpgradeRequiredError);
        return true;
      },
    );
  });
});

// ---------------------------------------------------------------------------
// claimOwnership
// ---------------------------------------------------------------------------

describe("TeamrcClient claimOwnership", () => {
  afterEach(() => restoreFetch());

  it("returns { status: 'claimed' } on 200", async () => {
    mockFetch({ status: "claimed" }, 200);
    const client = new TeamrcClient("http://localhost:4000", dummyKey, dummyToken);

    const result = await client.claimOwnership("trc_ocs_secret");
    assert.deepEqual(result, { status: "claimed" });
  });

  it("throws on non-ok response", async () => {
    mockFetch({ error: "invalid_secret" }, 403);
    const client = new TeamrcClient("http://localhost:4000", dummyKey, dummyToken);

    await assert.rejects(
      () => client.claimOwnership("trc_ocs_bad"),
      (err: Error) => {
        assert.match(err.message, /claimOwnership failed/);
        return true;
      },
    );
  });
});

// ---------------------------------------------------------------------------
// setVisibility
// ---------------------------------------------------------------------------

describe("TeamrcClient setVisibility", () => {
  afterEach(() => restoreFetch());

  it("returns visibility and clone_token on 200", async () => {
    mockFetch({ visibility: "public", clone_token: "trc_cl_abc" }, 200);
    const client = new TeamrcClient("http://localhost:4000", dummyKey, dummyToken);

    const result = await client.setVisibility("public");
    assert.equal(result.visibility, "public");
    assert.equal(result.clone_token, "trc_cl_abc");
  });

  it("throws on non-ok response", async () => {
    mockFetch({ error: "not_owner" }, 403);
    const client = new TeamrcClient("http://localhost:4000", dummyKey, dummyToken);

    await assert.rejects(
      () => client.setVisibility("public"),
      (err: Error) => {
        assert.match(err.message, /setVisibility failed/);
        return true;
      },
    );
  });
});

// ---------------------------------------------------------------------------
// createInvite
// ---------------------------------------------------------------------------

describe("TeamrcClient createInvite", () => {
  afterEach(() => restoreFetch());

  it("returns invite_code and expires_at on 200", async () => {
    mockFetch({ invite_code: "trc_inv_xyz", expires_at: "2026-04-01T00:00:00Z" }, 200);
    const client = new TeamrcClient("http://localhost:4000", dummyKey, dummyToken);

    const result = await client.createInvite(48);
    assert.equal(result.invite_code, "trc_inv_xyz");
    assert.equal(result.expires_at, "2026-04-01T00:00:00Z");
  });

  it("throws on non-ok response", async () => {
    mockFetch({ error: "not_authorized" }, 401);
    const client = new TeamrcClient("http://localhost:4000", dummyKey, dummyToken);

    await assert.rejects(
      () => client.createInvite(),
      (err: Error) => {
        assert.match(err.message, /createInvite failed/);
        return true;
      },
    );
  });
});

// ---------------------------------------------------------------------------
// disconnect with and without teamId
// ---------------------------------------------------------------------------

describe("TeamrcClient disconnect", () => {
  afterEach(() => restoreFetch());

  it("includes team_id query parameter when teamId is passed", async () => {
    mockFetch({ status: "disconnected", teams_removed: 1 }, 200);
    const client = new TeamrcClient("http://localhost:4000", dummyKey, dummyToken);

    await client.disconnect("my-team-id");
    assert.equal(captured.length, 1);
    assert.ok(
      captured[0].url.includes("?team_id=my-team-id"),
      `URL should contain team_id param, got: ${captured[0].url}`,
    );
  });

  it("does not include team_id param when no teamId is passed", async () => {
    mockFetch({ status: "disconnected", teams_removed: 2 }, 200);
    const client = new TeamrcClient("http://localhost:4000", dummyKey, dummyToken);

    await client.disconnect();
    assert.equal(captured.length, 1);
    assert.ok(
      !captured[0].url.includes("team_id"),
      `URL should not contain team_id param, got: ${captured[0].url}`,
    );
  });

  it("URL includes /erase path", async () => {
    mockFetch({ status: "disconnected", teams_removed: 1 }, 200);
    const client = new TeamrcClient("http://localhost:4000", dummyKey, dummyToken);

    await client.disconnect("test-team");
    assert.ok(captured[0].url.includes("/erase"), `URL should contain /erase, got: ${captured[0].url}`);
  });
});
