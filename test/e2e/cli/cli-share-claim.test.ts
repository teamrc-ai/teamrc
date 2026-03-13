import { describe, it, before, beforeEach } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import {
  createIsolatedEnv,
  runCli,
  testSetup,
  waitForServer,
  readYaml,
  readConfig,
  getToken,
  getTeamId,
  loadKeypairFromEnv,
  type IsolatedEnv,
} from "./helpers.ts";

before(async () => {
  await waitForServer();
});

beforeEach(async () => {
  await testSetup("clear_rate_limits");
});

// ─── Helpers ───

/**
 * Set up a "logged in" machine in the isolated env by creating a user,
 * linking the token, and writing config.json with account info.
 */
async function setupLogin(env: IsolatedEnv): Promise<{ userId: string }> {
  const token = getToken(env);
  assert.ok(token, "Token must exist before login setup");

  const { user_id } = (await testSetup("create_user")) as { user_id: string };
  await testSetup("link_token", { user_id, token });

  // Write config.json with account info to simulate login
  const configDir = path.join(env.home, ".teamrc");
  fs.mkdirSync(configDir, { recursive: true });
  const configPath = path.join(configDir, "config.json");
  const existingConfig = fs.existsSync(configPath)
    ? JSON.parse(fs.readFileSync(configPath, "utf-8"))
    : {};
  fs.writeFileSync(configPath, JSON.stringify({
    ...existingConfig,
    token,
    account: { email: "test@e2e.com" },
  }));

  return { userId: user_id };
}

/**
 * Init a relay-connected team and return the claim secret from init output.
 */
async function initRelay(env: IsolatedEnv, name = "share-test"): Promise<{ claimSecret: string }> {
  const initResult = await runCli(
    ["init", "--name", name, "--team", "backend", "--platform", "claude-code"],
    env,
  );
  assert.equal(initResult.exitCode, 0, `Init failed.\nstdout: ${initResult.stdout}\nstderr: ${initResult.stderr}`);

  const initOutput = initResult.stdout + initResult.stderr;
  const claimMatch = initOutput.match(/trc_ocs_[A-Za-z0-9_-]+/);
  assert.ok(claimMatch, `Init output should contain claim secret (trc_ocs_). Output: ${initOutput}`);

  return { claimSecret: claimMatch[0] };
}

describe("teamrc share & claim", () => {
  it("share (logged-in owner) outputs clone token and URL", async () => {
    const env = createIsolatedEnv("share-owner");
    try {
      // Init relay-connected team (produces claim secret)
      const { claimSecret } = await initRelay(env);

      // Set up login
      await setupLogin(env);

      // Claim ownership
      const claimResult = await runCli(["claim", claimSecret], env);
      assert.equal(claimResult.exitCode, 0, `Claim failed.\nstdout: ${claimResult.stdout}\nstderr: ${claimResult.stderr}`);

      // Share
      const shareResult = await runCli(["share"], env);
      assert.equal(shareResult.exitCode, 0, `Share failed.\nstdout: ${shareResult.stdout}\nstderr: ${shareResult.stderr}`);

      const shareOutput = shareResult.stdout + shareResult.stderr;

      // Should contain a clone token
      assert.match(shareOutput, /trc_cl_[A-Za-z0-9_-]+/, "Share output should contain a clone token (trc_cl_)");

      // Should contain a clone URL or share URL
      const hasUrl = shareOutput.includes("/t/trc_cl_") || shareOutput.includes("Share URL") || shareOutput.includes("Clone cmd");
      assert.ok(hasUrl, `Share output should contain clone URL or clone command. Output: ${shareOutput}`);
    } finally {
      env.cleanup();
    }
  });

  it("share --off makes team private", async () => {
    const env = createIsolatedEnv("share-off");
    try {
      // Init, login, claim, share (make public first)
      const { claimSecret } = await initRelay(env, "share-off-test");
      await setupLogin(env);

      const claimResult = await runCli(["claim", claimSecret], env);
      assert.equal(claimResult.exitCode, 0, `Claim failed.\nstdout: ${claimResult.stdout}\nstderr: ${claimResult.stderr}`);

      const shareResult = await runCli(["share"], env);
      assert.equal(shareResult.exitCode, 0, `Share failed.\nstdout: ${shareResult.stdout}\nstderr: ${shareResult.stderr}`);

      // Now make private
      const offResult = await runCli(["share", "--off"], env);
      assert.equal(offResult.exitCode, 0, `Share --off failed.\nstdout: ${offResult.stdout}\nstderr: ${offResult.stderr}`);

      const offOutput = offResult.stdout + offResult.stderr;
      assert.ok(
        offOutput.includes("private") || offOutput.includes("Private"),
        `Share --off output should confirm team is private. Output: ${offOutput}`,
      );
    } finally {
      env.cleanup();
    }
  });

  it("claim with valid secret succeeds", async () => {
    const env = createIsolatedEnv("claim-valid");
    try {
      // Init relay-connected team (produces claim secret)
      const { claimSecret } = await initRelay(env, "claim-test");

      // Set up login
      await setupLogin(env);

      // Claim ownership
      const claimResult = await runCli(["claim", claimSecret], env);
      assert.equal(claimResult.exitCode, 0, `Claim should succeed.\nstdout: ${claimResult.stdout}\nstderr: ${claimResult.stderr}`);

      const claimOutput = claimResult.stdout + claimResult.stderr;
      assert.ok(
        claimOutput.includes("owner") || claimOutput.includes("Ownership") || claimOutput.includes("claimed"),
        `Claim output should confirm ownership. Output: ${claimOutput}`,
      );
    } finally {
      env.cleanup();
    }
  });

  it("claim with invalid secret fails", async () => {
    const env = createIsolatedEnv("claim-invalid");
    try {
      // Init relay-connected team (we need a valid project context)
      await initRelay(env, "claim-invalid-test");

      // Set up login
      await setupLogin(env);

      // Try to claim with an invalid secret
      const claimResult = await runCli(["claim", "trc_ocs_INVALID_SECRET_12345"], env);
      assert.notEqual(claimResult.exitCode, 0, `Claim with invalid secret should fail.\nstdout: ${claimResult.stdout}\nstderr: ${claimResult.stderr}`);
    } finally {
      env.cleanup();
    }
  });

  it("share requires login (account in config)", async () => {
    const env = createIsolatedEnv("share-no-login");
    try {
      // Init relay-connected team but do NOT set up login
      await initRelay(env, "share-nologin-test");

      // Try to share without being logged in
      const shareResult = await runCli(["share"], env);
      assert.notEqual(shareResult.exitCode, 0, `Share without login should fail.\nstdout: ${shareResult.stdout}\nstderr: ${shareResult.stderr}`);

      const shareOutput = shareResult.stdout + shareResult.stderr;
      assert.ok(
        shareOutput.includes("login") || shareOutput.includes("account") || shareOutput.includes("linked"),
        `Share output should mention login requirement. Output: ${shareOutput}`,
      );
    } finally {
      env.cleanup();
    }
  });

  it("share after claim works end-to-end", async () => {
    const env = createIsolatedEnv("share-after-claim");
    try {
      // Init relay-connected team
      const { claimSecret } = await initRelay(env, "claim-then-share");

      // Set up login
      await setupLogin(env);

      // Claim ownership
      const claimResult = await runCli(["claim", claimSecret], env);
      assert.equal(claimResult.exitCode, 0, `Claim failed.\nstdout: ${claimResult.stdout}\nstderr: ${claimResult.stderr}`);

      // Share should work now that we are the owner
      const shareResult = await runCli(["share"], env);
      assert.equal(shareResult.exitCode, 0, `Share after claim should succeed.\nstdout: ${shareResult.stdout}\nstderr: ${shareResult.stderr}`);

      const shareOutput = shareResult.stdout + shareResult.stderr;

      // Should have clone info
      assert.match(shareOutput, /trc_cl_[A-Za-z0-9_-]+/, "Share output should contain a clone token");

      const hasCloneInfo = shareOutput.includes("clone") || shareOutput.includes("Clone") || shareOutput.includes("Share URL");
      assert.ok(hasCloneInfo, `Share output should contain clone info. Output: ${shareOutput}`);
    } finally {
      env.cleanup();
    }
  });
});
