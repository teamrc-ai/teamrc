import { describe, it, before, beforeEach } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import {
  createIsolatedEnv,
  runCli,
  spawnCli,
  testSetup,
  waitForServer,
  readConfig,
  readKey,
  getToken,
  getTeamId,
  type IsolatedEnv,
} from "./helpers.ts";

// ─── Helpers ───

/**
 * Run `init --local` to bootstrap a keypair and config in the isolated env.
 * This is required before `login` because login calls `requireKeypair()`.
 */
async function initLocal(env: IsolatedEnv): Promise<void> {
  const result = await runCli(
    ["init", "--local", "--name", "temp", "--team", "backend", "--platform", "claude-code"],
    env,
  );
  assert.equal(result.exitCode, 0, `init --local failed: ${result.stdout}\n${result.stderr}`);
}

/**
 * Perform the full device auth login flow:
 * 1. Spawn `login --name <machineName>`
 * 2. Wait for user_code in stdout
 * 3. Create a test user
 * 4. Link the machine's token to that user
 * 5. Confirm device auth with the user_code
 * 6. Wait for CLI to exit
 *
 * Returns the user info (user_id, email) for further assertions.
 */
async function performLogin(
  env: IsolatedEnv,
  machineName = "test-machine",
): Promise<{ userId: string; email: string }> {
  const token = getToken(env);
  assert.ok(token, "Token must exist before login (run init --local first)");

  const cli = spawnCli(["login", "--name", machineName], env);

  // Wait for the user code to appear in stdout
  const codeOutput = await cli.waitForOutput(/Code:\s+([A-Z0-9]{4}-[A-Z0-9]{4})/, 20_000);
  const codeMatch = codeOutput.match(/Code:\s+([A-Z0-9]{4}-[A-Z0-9]{4})/);
  assert.ok(codeMatch, "Should have matched user_code pattern");
  const userCode = codeMatch[1];

  // Create a test user on the server
  const { user_id, email } = (await testSetup("create_user")) as {
    user_id: string;
    email: string;
  };

  // Link the machine token to the user
  await testSetup("link_token", { user_id, token });

  // Confirm the device auth request
  await testSetup("confirm_device_auth", { user_code: userCode, user_id, email });

  // Wait for the CLI to detect confirmation and exit
  const result = await cli.waitForExit(30_000);
  assert.equal(result.exitCode, 0, `login exited with code ${result.exitCode}: ${result.stdout}\n${result.stderr}`);

  return { userId: user_id, email };
}

// ─── Tests ───

before(async () => {
  await waitForServer();
});

describe("CLI login (device auth)", () => {
  beforeEach(async () => {
    await testSetup("clear_rate_limits");
  });

  it("full login flow: init → login → config has account.email and machineName", async () => {
    const env = createIsolatedEnv("login-full");
    try {
      await initLocal(env);

      const { email } = await performLogin(env, "test-machine");

      // Verify config.json was updated with account info
      const config = readConfig(env);
      assert.ok(config, "config.json should exist after login");
      const account = config.account as { email: string } | undefined;
      assert.ok(account, "config should have account field");
      assert.equal(account.email, email, "account.email should match the confirmed user email");
      assert.equal(config.machineName, "test-machine", "machineName should be saved");
    } finally {
      env.cleanup();
    }
  });

  it("login persists across commands: whoami shows email", async () => {
    const env = createIsolatedEnv("login-whoami");
    try {
      await initLocal(env);
      const { email } = await performLogin(env, "whoami-machine");

      // Run whoami — should show the linked account email
      const result = await runCli(["whoami"], env);
      assert.equal(result.exitCode, 0, `whoami failed: ${result.stdout}\n${result.stderr}`);
      assert.ok(
        result.stdout.includes(email),
        `whoami output should contain email "${email}", got: ${result.stdout}`,
      );
    } finally {
      env.cleanup();
    }
  });

  it("login + init = auto-owner (no claim secret shown)", async () => {
    const env = createIsolatedEnv("login-auto-owner");
    try {
      // Step 1: init --local to get a keypair
      await initLocal(env);

      // Step 2: login to link the account
      await performLogin(env, "owner-machine");

      // Step 3: create a new project dir for a fresh relay-connected init
      const newProjectDir = path.join(env.home, "new-project");
      fs.mkdirSync(newProjectDir, { recursive: true });
      fs.writeFileSync(path.join(newProjectDir, ".gitignore"), "node_modules/\n");

      // Step 4: run init (with relay) in the new project dir
      const result = await runCli(
        ["init", "--name", "auto-own", "--team", "backend", "--platform", "claude-code"],
        env,
        { cwd: newProjectDir },
      );
      assert.equal(result.exitCode, 0, `init failed: ${result.stdout}\n${result.stderr}`);

      // Should say "You own this team" (auto-assigned ownership because token is linked)
      assert.ok(
        result.stdout.includes("You own this team"),
        `Expected "You own this team" in stdout, got: ${result.stdout}`,
      );

      // Should NOT show a claim secret (since ownership was auto-assigned)
      assert.ok(
        !result.stdout.includes("trc_ocs_"),
        `Should not show claim secret in stdout when auto-owner, got: ${result.stdout}`,
      );
    } finally {
      env.cleanup();
    }
  });

  it("login + init + share works", async () => {
    const env = createIsolatedEnv("login-share");
    try {
      // Step 1: init --local to get a keypair
      await initLocal(env);

      // Step 2: login to link the account
      await performLogin(env, "share-machine");

      // Step 3: create a new project and init with relay
      const newProjectDir = path.join(env.home, "share-project");
      fs.mkdirSync(newProjectDir, { recursive: true });
      fs.writeFileSync(path.join(newProjectDir, ".gitignore"), "node_modules/\n");

      const initResult = await runCli(
        ["init", "--name", "share-test", "--team", "backend", "--platform", "claude-code"],
        env,
        { cwd: newProjectDir },
      );
      assert.equal(initResult.exitCode, 0, `init failed: ${initResult.stdout}\n${initResult.stderr}`);

      // Step 4: run share in the new project dir
      const shareResult = await runCli(["share"], env, { cwd: newProjectDir });
      assert.equal(shareResult.exitCode, 0, `share failed: ${shareResult.stdout}\n${shareResult.stderr}`);

      // Should contain a clone URL or clone token
      const hasCloneInfo =
        shareResult.stdout.includes("trc_cl_") ||
        shareResult.stdout.includes("clone") ||
        shareResult.stdout.includes("Share URL");
      assert.ok(
        hasCloneInfo,
        `share output should contain clone info, got: ${shareResult.stdout}`,
      );
    } finally {
      env.cleanup();
    }
  });

  it("login timeout: unconfirmed login can be killed without hanging", async () => {
    const env = createIsolatedEnv("login-timeout");
    try {
      await initLocal(env);

      const cli = spawnCli(["login", "--name", "timeout-machine"], env);

      // Wait for the code to appear (proving the login process started)
      await cli.waitForOutput(/Code:\s+[A-Z0-9]{4}-[A-Z0-9]{4}/, 20_000);

      // Do NOT confirm — just kill the process after a short delay
      await new Promise((r) => setTimeout(r, 1_000));
      cli.kill("SIGINT");

      // Process should exit within a reasonable time (not hang forever)
      const result = await cli.waitForExit(10_000);

      // The process was killed, so it may exit with a non-zero code — that's fine.
      // The important thing is that it exited and didn't hang.
      assert.ok(
        result.exitCode !== undefined && result.exitCode !== null,
        "Process should have exited after being killed",
      );
    } finally {
      env.cleanup();
    }
  });
});
