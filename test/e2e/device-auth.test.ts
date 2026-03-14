import { describe, it, before } from "node:test";
import assert from "node:assert/strict";
import {
  waitForServer,
  signedPost,
  signedGet,
  createTeamWithKeypair,
  testSetup,
} from "./helpers.ts";

before(async () => {
  await waitForServer();
});

describe("Device auth flow", () => {
  it("creates a device auth request", async () => {
    const cli = await createTeamWithKeypair("device-auth-create", [
      { name: "Agent", role: "Dev" },
    ]);

    const res = await signedPost(
      "/api/auth/device",
      { token: cli.token },
      cli,
    );
    assert.equal(res.status, 200);
    const data = (await res.json()) as {
      device_code: string;
      user_code: string;
      verification_url: string;
      expires_in: number;
      interval: number;
    };
    assert.ok(data.device_code, "should return device_code");
    assert.ok(data.user_code, "should return user_code");
    assert.ok(data.verification_url, "should return verification_url");
    assert.ok(data.expires_in > 0, "should return positive expires_in");
    assert.ok(data.interval > 0, "should return positive interval");
  });

  it("poll returns pending before confirmation", async () => {
    const cli = await createTeamWithKeypair("device-auth-pending", [
      { name: "Agent", role: "Dev" },
    ]);

    const createRes = await signedPost(
      "/api/auth/device",
      { token: cli.token },
      cli,
    );
    const { device_code } = (await createRes.json()) as { device_code: string };

    // Poll  --  should be pending
    const pollRes = await signedGet(
      `/api/auth/device/${encodeURIComponent(device_code)}`,
      cli,
    );
    assert.equal(pollRes.status, 200);
    const data = (await pollRes.json()) as { status: string };
    assert.equal(data.status, "pending");
  });

  it("poll returns confirmed after test helper confirms", async () => {
    const cli = await createTeamWithKeypair("device-auth-confirm", [
      { name: "Agent", role: "Dev" },
    ]);

    const createRes = await signedPost(
      "/api/auth/device",
      { token: cli.token },
      cli,
    );
    const { device_code, user_code } = (await createRes.json()) as {
      device_code: string;
      user_code: string;
    };

    // Create a user and confirm via test helper
    const { user_id, email } = (await testSetup("create_user")) as {
      user_id: string;
      email: string;
    };
    await testSetup("confirm_device_auth", { user_code, user_id, email });

    // Poll  --  should be confirmed
    const pollRes = await signedGet(
      `/api/auth/device/${encodeURIComponent(device_code)}`,
      cli,
    );
    assert.equal(pollRes.status, 200);
    const data = (await pollRes.json()) as {
      status: string;
      email?: string;
    };
    assert.equal(data.status, "confirmed");
    assert.equal(data.email, email);
  });
});
