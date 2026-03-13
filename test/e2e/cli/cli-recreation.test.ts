import { describe, it, before, beforeEach } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import YAML from "yaml";
import {
  createIsolatedEnv,
  runCli,
  testSetup,
  waitForServer,
  readYaml,
  fileExists,
  readFile,
  writeFile,
  listFiles,
  readConfig,
  getToken,
  getTeamId,
  loadKeypairFromEnv,
  signedGet,
  signedPost,
  writeYaml,
  editTeamYaml,
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

describe("team recreation", () => {
  it("push after erase creates a new team (logged-in)", { timeout: 30_000 }, async () => {
    const env = createIsolatedEnv("recreate-login");
    try {
      // Init local-only first (to generate keypair without relay)
      const initResult = await runCli(
        ["init", "--local", "--name", "recreate-login", "--team", "backend", "--platform", "claude-code"],
        env,
      );
      assert.equal(initResult.exitCode, 0, `Init failed.\nstdout: ${initResult.stdout}\nstderr: ${initResult.stderr}`);

      // Simulate login
      await setupLogin(env);

      // Push to create team on relay
      const pushResult1 = await runCli(["push"], env);
      assert.equal(pushResult1.exitCode, 0, `First push failed.\nstdout: ${pushResult1.stdout}\nstderr: ${pushResult1.stderr}`);

      // Record original teamId
      const originalTeamId = getTeamId(env);
      assert.ok(originalTeamId, "Should have teamId after first push");
      const token = getToken(env);
      assert.ok(token, "Token should exist");

      // Erase the token's association with the team on the relay
      await testSetup("erase_token", { token, team_id: originalTeamId });

      // Remove teamId/relay from YAML (simulate starting fresh)
      const yamlContent = readYaml(env);
      const freshYaml = yamlContent
        .replace(/^teamId:.*\n/m, "")
        .replace(/^relay:.*\n/m, "");
      writeYaml(env, freshYaml);

      // Push again → should create a NEW team (different teamId)
      const pushResult2 = await runCli(["push"], env);
      assert.equal(pushResult2.exitCode, 0, `Second push failed.\nstdout: ${pushResult2.stdout}\nstderr: ${pushResult2.stderr}`);

      const newTeamId = getTeamId(env);
      assert.ok(newTeamId, "Should have teamId after second push");
      assert.notEqual(newTeamId, originalTeamId, "New teamId should differ from original");

      // Logged-in user should see auto-ownership message
      const combined = pushResult2.stdout + pushResult2.stderr;
      assert.match(combined, /You own this team/i, "Output should confirm auto-ownership for logged-in user");
    } finally {
      env.cleanup();
    }
  });

  it("push after erase creates a new team (not logged-in)", { timeout: 30_000 }, async () => {
    const env = createIsolatedEnv("recreate-anon");
    try {
      // Init local-only (no login)
      const initResult = await runCli(
        ["init", "--local", "--name", "recreate-anon", "--team", "backend", "--platform", "claude-code"],
        env,
      );
      assert.equal(initResult.exitCode, 0, `Init failed.\nstdout: ${initResult.stdout}\nstderr: ${initResult.stderr}`);

      // Push to relay
      const pushResult1 = await runCli(["push"], env);
      assert.equal(pushResult1.exitCode, 0, `First push failed.\nstdout: ${pushResult1.stdout}\nstderr: ${pushResult1.stderr}`);

      const originalTeamId = getTeamId(env);
      assert.ok(originalTeamId, "Should have teamId after first push");
      const token = getToken(env);
      assert.ok(token, "Token should exist");

      // Erase the token's association with the team on the relay
      await testSetup("erase_token", { token, team_id: originalTeamId });

      // Remove teamId/relay from YAML
      const yamlContent = readYaml(env);
      const freshYaml = yamlContent
        .replace(/^teamId:.*\n/m, "")
        .replace(/^relay:.*\n/m, "");
      writeYaml(env, freshYaml);

      // Push again → should create a NEW team
      const pushResult2 = await runCli(["push"], env);
      assert.equal(pushResult2.exitCode, 0, `Second push failed.\nstdout: ${pushResult2.stdout}\nstderr: ${pushResult2.stderr}`);

      const newTeamId = getTeamId(env);
      assert.ok(newTeamId, "Should have teamId after second push");
      assert.notEqual(newTeamId, originalTeamId, "New teamId should differ from original");

      // Not logged in, should show claim secret
      const combined = pushResult2.stdout + pushResult2.stderr;
      assert.match(combined, /trc_ocs_/, "Output should contain claim secret for non-logged-in user");
    } finally {
      env.cleanup();
    }
  });

  it("recreation preserves team definition", { timeout: 30_000 }, async () => {
    const env = createIsolatedEnv("recreate-preserve");
    try {
      // Init local-only with the backend template
      const initResult = await runCli(
        ["init", "--local", "--name", "preserve-test", "--team", "backend", "--platform", "claude-code"],
        env,
      );
      assert.equal(initResult.exitCode, 0, `Init failed.\nstdout: ${initResult.stdout}\nstderr: ${initResult.stderr}`);

      // Add a custom member to make the team unique
      editTeamYaml(env, (doc) => {
        const members = doc.members as Array<{ name: string; role: string }>;
        members.unshift({ name: "custom-preserve-agent", role: "Custom Preservation Tester" });
      });

      // Push to relay (first time)
      const pushResult1 = await runCli(["push"], env);
      assert.equal(pushResult1.exitCode, 0, `First push failed.\nstdout: ${pushResult1.stdout}\nstderr: ${pushResult1.stderr}`);

      const originalTeamId = getTeamId(env);
      assert.ok(originalTeamId, "Should have teamId after first push");
      const token = getToken(env);
      assert.ok(token, "Token should exist");

      // Verify custom member is in the YAML
      const membersBefore = readYaml(env);
      assert.ok(
        membersBefore.includes("custom-preserve-agent"),
        "Members before should include custom-preserve-agent",
      );

      // Erase the token's association with the team on the relay
      await testSetup("erase_token", { token, team_id: originalTeamId });

      // Remove teamId/relay from YAML
      const yamlContent = readYaml(env);
      const freshYaml = yamlContent
        .replace(/^teamId:.*\n/m, "")
        .replace(/^relay:.*\n/m, "");
      writeYaml(env, freshYaml);

      // Push again → creates new team on relay
      const pushResult2 = await runCli(["push"], env);
      assert.equal(pushResult2.exitCode, 0, `Second push failed.\nstdout: ${pushResult2.stdout}\nstderr: ${pushResult2.stderr}`);

      const newTeamId = getTeamId(env);
      assert.ok(newTeamId, "Should have new teamId");
      assert.notEqual(newTeamId, originalTeamId, "New teamId should differ");

      // Verify the new team on the relay has the same members
      const kp = loadKeypairFromEnv(env);
      assert.ok(kp, "Keypair should exist");

      const res = await signedGet(`/api/teams/${kp.token}?team_id=${newTeamId}`, kp);
      assert.equal(res.status, 200, "GET team should return 200");
      const data = (await res.json()) as { team: { members: Array<{ name: string }> } };
      const remoteMembers = data.team.members.map((m) => m.name);

      assert.ok(
        remoteMembers.includes("custom-preserve-agent"),
        `Remote team should contain "custom-preserve-agent". Got: ${remoteMembers.join(", ")}`,
      );
    } finally {
      env.cleanup();
    }
  });
});
