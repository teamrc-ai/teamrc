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
  fileExists,
  listFiles,
  getToken,
  getTeamId,
  loadKeypairFromEnv,
  signedPost,
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
 * Init a relay-connected team, set up login, claim ownership, and share.
 * Returns the clone token for use by machine B.
 */
async function initAndShare(env: IsolatedEnv): Promise<{ cloneToken: string; inviteCode: string }> {
  // Init a relay-connected team
  const initResult = await runCli(
    ["init", "--name", "clone-source", "--team", "fullstack", "--platform", "claude-code"],
    env,
  );
  assert.equal(initResult.exitCode, 0, `Init failed.\nstdout: ${initResult.stdout}\nstderr: ${initResult.stderr}`);

  const initOutput = initResult.stdout + initResult.stderr;

  // Extract claim secret from init output
  const claimMatch = initOutput.match(/trc_ocs_[A-Za-z0-9_-]+/);
  assert.ok(claimMatch, `Init output should contain claim secret (trc_ocs_). Output: ${initOutput}`);
  const claimSecret = claimMatch[0];

  // Extract invite code from init output
  const inviteMatch = initOutput.match(/trc_inv_[A-Za-z0-9_-]+/);
  assert.ok(inviteMatch, `Init output should contain invite code. Output: ${initOutput}`);
  const inviteCode = inviteMatch[0];

  // Set up login (create user, link token, write config)
  await setupLogin(env);

  // Claim ownership
  const claimResult = await runCli(["claim", claimSecret], env);
  assert.equal(claimResult.exitCode, 0, `Claim failed.\nstdout: ${claimResult.stdout}\nstderr: ${claimResult.stderr}`);

  // Share to get clone token
  const shareResult = await runCli(["share"], env);
  assert.equal(shareResult.exitCode, 0, `Share failed.\nstdout: ${shareResult.stdout}\nstderr: ${shareResult.stderr}`);

  const shareOutput = shareResult.stdout + shareResult.stderr;
  const cloneTokenMatch = shareOutput.match(/trc_cl_[A-Za-z0-9_-]+/);
  assert.ok(cloneTokenMatch, `Share output should contain clone token. Output: ${shareOutput}`);

  return { cloneToken: cloneTokenMatch[0], inviteCode };
}

describe("teamrc clone", () => {
  it("clone by clone token", async () => {
    const envA = createIsolatedEnv("clone-token-a");
    const envB = createIsolatedEnv("clone-token-b");
    try {
      // Machine A: init, login, claim, share
      const { cloneToken } = await initAndShare(envA);

      // Machine B: clone using the clone token
      const cloneResult = await runCli(
        ["clone", cloneToken, "--platform", "claude-code", "--relay", "http://localhost:4002"],
        envB,
      );
      assert.equal(cloneResult.exitCode, 0, `Clone failed.\nstdout: ${cloneResult.stdout}\nstderr: ${cloneResult.stderr}`);

      // Verify B has .teamrc.yaml
      assert.ok(fileExists(envB, ".teamrc.yaml"), ".teamrc.yaml should exist after clone");
      const yaml = readYaml(envB);

      // Should have cloneToken in YAML
      assert.ok(yaml.includes("cloneToken:"), "YAML should contain cloneToken");
      assert.ok(yaml.includes(cloneToken), "YAML should contain the actual clone token value");

      // Should NOT have teamId (clone is read-only, not a member)
      assert.ok(!yaml.includes("teamId:"), "YAML should NOT contain teamId for a clone");

      // Should have platform files
      const agentFiles = listFiles(envB, ".claude/agents");
      assert.ok(agentFiles.length > 0, "Should have agent files in .claude/agents/");
      const trcFiles = agentFiles.filter((f) => f.startsWith("trc-") && f.endsWith(".md"));
      assert.ok(trcFiles.length > 0, "Should have trc-*.md agent files");
    } finally {
      envA.cleanup();
      envB.cleanup();
    }
  });

  it("clone by invite code", async () => {
    const envA = createIsolatedEnv("clone-invite-a");
    const envB = createIsolatedEnv("clone-invite-b");
    try {
      // Machine A: init (relay-connected, get invite code)
      const initResult = await runCli(
        ["init", "--name", "invite-source", "--team", "fullstack", "--platform", "claude-code"],
        envA,
      );
      assert.equal(initResult.exitCode, 0, `Init failed.\nstdout: ${initResult.stdout}\nstderr: ${initResult.stderr}`);

      const initOutput = initResult.stdout + initResult.stderr;
      const inviteMatch = initOutput.match(/trc_inv_[A-Za-z0-9_-]+/);
      assert.ok(inviteMatch, `Init output should contain invite code. Output: ${initOutput}`);
      const inviteCode = inviteMatch[0];

      // Machine B: clone using the invite code
      const cloneResult = await runCli(
        ["clone", inviteCode, "--platform", "claude-code", "--relay", "http://localhost:4002"],
        envB,
      );
      assert.equal(cloneResult.exitCode, 0, `Clone failed.\nstdout: ${cloneResult.stdout}\nstderr: ${cloneResult.stderr}`);

      // Verify B has .teamrc.yaml with local data
      assert.ok(fileExists(envB, ".teamrc.yaml"), ".teamrc.yaml should exist after clone");
      const yaml = readYaml(envB);
      assert.ok(yaml.includes("members:"), "YAML should contain members");

      // Should have platform files
      const agentFiles = listFiles(envB, ".claude/agents");
      assert.ok(agentFiles.length > 0, "Should have agent files in .claude/agents/");
      const trcFiles = agentFiles.filter((f) => f.startsWith("trc-") && f.endsWith(".md"));
      assert.ok(trcFiles.length > 0, "Should have trc-*.md agent files");
    } finally {
      envA.cleanup();
      envB.cleanup();
    }
  });

  it("clone with --name override", async () => {
    const envA = createIsolatedEnv("clone-name-a");
    const envB = createIsolatedEnv("clone-name-b");
    try {
      // Machine A: init, login, claim, share
      const { cloneToken } = await initAndShare(envA);

      // Machine B: clone with custom name
      const cloneResult = await runCli(
        ["clone", cloneToken, "--platform", "claude-code", "--relay", "http://localhost:4002", "--name", "my-custom-clone"],
        envB,
      );
      assert.equal(cloneResult.exitCode, 0, `Clone failed.\nstdout: ${cloneResult.stdout}\nstderr: ${cloneResult.stderr}`);

      // Verify YAML has the custom name
      const yaml = readYaml(envB);
      assert.ok(yaml.includes("name: my-custom-clone"), "YAML should contain name: my-custom-clone");
    } finally {
      envA.cleanup();
      envB.cleanup();
    }
  });

  it("cloned team can pull", async () => {
    const envA = createIsolatedEnv("clone-pull-a");
    const envB = createIsolatedEnv("clone-pull-b");
    try {
      // Machine A: init, login, claim, share
      const { cloneToken } = await initAndShare(envA);

      // Machine B: clone
      const cloneResult = await runCli(
        ["clone", cloneToken, "--platform", "claude-code", "--relay", "http://localhost:4002"],
        envB,
      );
      assert.equal(cloneResult.exitCode, 0, `Clone failed.\nstdout: ${cloneResult.stdout}\nstderr: ${cloneResult.stderr}`);

      // Read original YAML to get current members
      const originalYaml = readYaml(envA);
      const memberMatches = [...originalYaml.matchAll(/- name: (.+)\n\s+role: (.+)/g)];
      const existingMembers = memberMatches.map((m) => ({ name: m[1].trim(), role: m[2].trim() }));

      // Update original team on relay (add a new member)
      const tokenA = getToken(envA);
      assert.ok(tokenA, "Token A should exist");
      const teamIdA = getTeamId(envA);
      assert.ok(teamIdA, "Team ID A should exist");

      await testSetup("update_team", {
        token: tokenA,
        team_id: teamIdA,
        team: {
          name: "clone-source",
          members: [
            ...existingMembers,
            { name: "new-pulled-agent", role: "Quality Assurance" },
          ],
        },
      });

      // Machine B: pull updates
      const pullResult = await runCli(["pull", "--platform", "claude-code"], envB);
      assert.equal(pullResult.exitCode, 0, `Pull failed.\nstdout: ${pullResult.stdout}\nstderr: ${pullResult.stderr}`);

      // Verify the cloned YAML now has the new agent
      const updatedYaml = readYaml(envB);
      assert.ok(
        updatedYaml.includes("new-pulled-agent"),
        `Cloned YAML should contain 'new-pulled-agent' after pull.\nYAML:\n${updatedYaml}`,
      );

      // Verify platform file was created
      assert.ok(
        fileExists(envB, ".claude/agents/trc-new-pulled-agent.md"),
        "Agent file trc-new-pulled-agent.md should exist after pull",
      );
    } finally {
      envA.cleanup();
      envB.cleanup();
    }
  });

  it("cloned team cannot push", async () => {
    const envA = createIsolatedEnv("clone-push-a");
    const envB = createIsolatedEnv("clone-push-b");
    try {
      // Machine A: init, login, claim, share
      const { cloneToken } = await initAndShare(envA);

      // Machine B: clone
      const cloneResult = await runCli(
        ["clone", cloneToken, "--platform", "claude-code", "--relay", "http://localhost:4002"],
        envB,
      );
      assert.equal(cloneResult.exitCode, 0, `Clone failed.\nstdout: ${cloneResult.stdout}\nstderr: ${cloneResult.stderr}`);

      // Machine B: try to push — should fail (no teamId, clone is read-only)
      const pushResult = await runCli(["push"], envB);
      const combined = pushResult.stdout + pushResult.stderr;

      // Push should either exit non-zero or show an error about not being connected
      const failed = pushResult.exitCode !== 0 ||
        combined.includes("not connected") ||
        combined.includes("No relay") ||
        combined.includes("No keypair") ||
        combined.includes("No team") ||
        combined.includes("error");

      assert.ok(
        failed,
        `Push from a clone should fail or show an error.\nexitCode: ${pushResult.exitCode}\nstdout: ${pushResult.stdout}\nstderr: ${pushResult.stderr}`,
      );
    } finally {
      envA.cleanup();
      envB.cleanup();
    }
  });
});
