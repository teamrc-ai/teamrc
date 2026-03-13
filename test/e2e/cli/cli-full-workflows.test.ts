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
  type IsolatedEnv,
} from "./helpers.ts";

before(async () => {
  await waitForServer();
});

beforeEach(async () => {
  await testSetup("clear_rate_limits");
});

// ─── Helpers ───

const INVITE_RE = /trc_inv_[A-Za-z0-9_-]+/;

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

describe("full workflows", () => {
  it("quick start workflow: init → invite → join → sync", { timeout: 30_000 }, async () => {
    const envA = createIsolatedEnv("wf-quick-a");
    const envB = createIsolatedEnv("wf-quick-b");
    try {
      // A: init with fullstack template
      const initResult = await runCli(
        ["init", "--name", "quickstart", "--team", "fullstack", "--platform", "claude-code"],
        envA,
      );
      assert.equal(initResult.exitCode, 0, `A init failed.\nstdout: ${initResult.stdout}\nstderr: ${initResult.stderr}`);

      // A: invite → extract invite code
      const inviteResult = await runCli(["invite"], envA);
      assert.equal(inviteResult.exitCode, 0, `A invite failed.\nstdout: ${inviteResult.stdout}\nstderr: ${inviteResult.stderr}`);
      const inviteMatch = inviteResult.stdout.match(INVITE_RE);
      assert.ok(inviteMatch, `Invite output should contain invite code. stdout: ${inviteResult.stdout}`);
      const inviteCode = inviteMatch[0];

      // B: join using invite code
      const joinResult = await runCli(
        ["join", inviteCode, "--platform", "claude-code", "--relay", "http://localhost:4002"],
        envB,
      );
      assert.equal(joinResult.exitCode, 0, `B join failed.\nstdout: ${joinResult.stdout}\nstderr: ${joinResult.stderr}`);

      // B: sync to write platform files
      const syncResult = await runCli(
        ["sync", "--platform", "claude-code"],
        envB,
      );
      assert.equal(syncResult.exitCode, 0, `B sync failed.\nstdout: ${syncResult.stdout}\nstderr: ${syncResult.stderr}`);

      // Both should be in sync: B's teamId matches A's teamId
      const teamIdA = getTeamId(envA);
      const teamIdB = getTeamId(envB);
      assert.ok(teamIdA, "A should have a teamId");
      assert.equal(teamIdB, teamIdA, "B's teamId should match A's teamId after join");

      // B should have agent files
      const agentFilesB = listFiles(envB, ".claude/agents").filter((f) => f.startsWith("trc-"));
      assert.ok(agentFilesB.length > 0, `B should have trc-*.md agent files. Found: ${agentFilesB.join(", ")}`);
    } finally {
      envA.cleanup();
      envB.cleanup();
    }
  });

  it("web edit → local sync: update_team → pull", { timeout: 30_000 }, async () => {
    const env = createIsolatedEnv("wf-web-edit");
    try {
      const initResult = await runCli(
        ["init", "--name", "web-edit", "--team", "backend", "--platform", "claude-code"],
        env,
      );
      assert.equal(initResult.exitCode, 0, `Init failed.\nstdout: ${initResult.stdout}\nstderr: ${initResult.stderr}`);

      const token = getToken(env);
      assert.ok(token, "Token should exist after init");
      const teamId = getTeamId(env);
      assert.ok(teamId, "Team ID should exist after init");

      // Read existing members for the update
      const yamlBefore = readYaml(env);
      const memberMatches = [...yamlBefore.matchAll(/- name: (.+)\n\s+role: (.+)/g)];
      const existingMembers = memberMatches.map((m) => ({ name: m[1].trim(), role: m[2].trim() }));

      // Simulate web edit: add "web-added-agent" via server-side update
      await testSetup("update_team", {
        token,
        team_id: teamId,
        team: {
          name: "web-edit",
          members: [
            ...existingMembers,
            { name: "web-added-agent", role: "Web-Added Role" },
          ],
        },
      });

      // Pull to get the web edit
      const pullResult = await runCli(["pull", "--platform", "claude-code"], env);
      assert.equal(pullResult.exitCode, 0, `Pull failed.\nstdout: ${pullResult.stdout}\nstderr: ${pullResult.stderr}`);

      // Verify the web-added agent file exists
      assert.ok(
        fileExists(env, ".claude/agents/trc-web-added-agent.md"),
        "Agent file .claude/agents/trc-web-added-agent.md should exist after pull",
      );
    } finally {
      env.cleanup();
    }
  });

  it("YAML edit → push → apply", { timeout: 30_000 }, async () => {
    const env = createIsolatedEnv("wf-yaml-edit");
    try {
      const initResult = await runCli(
        ["init", "--name", "yaml-edit", "--team", "backend", "--platform", "claude-code"],
        env,
      );
      assert.equal(initResult.exitCode, 0, `Init failed.\nstdout: ${initResult.stdout}\nstderr: ${initResult.stderr}`);

      // Edit .teamrc.yaml to add "yaml-agent" member
      const yaml = readYaml(env);
      const newMember = "  - name: yaml-agent\n    role: YAML Test Agent\n";
      const updatedYaml = yaml.replace(/^(members:\n)/m, `$1${newMember}`);
      writeYaml(env, updatedYaml);

      // Push to relay
      const pushResult = await runCli(["push"], env);
      assert.equal(pushResult.exitCode, 0, `Push failed.\nstdout: ${pushResult.stdout}\nstderr: ${pushResult.stderr}`);

      // Delete .claude/agents/ directory to simulate clean state
      const agentsDir = path.join(env.projectDir, ".claude", "agents");
      if (fs.existsSync(agentsDir)) {
        fs.rmSync(agentsDir, { recursive: true, force: true });
      }
      assert.ok(!fileExists(env, ".claude/agents/trc-yaml-agent.md"), "Agent file should not exist after deletion");

      // Apply to regenerate platform files from YAML
      const applyResult = await runCli(["apply", "--platform", "claude-code"], env);
      assert.equal(applyResult.exitCode, 0, `Apply failed.\nstdout: ${applyResult.stdout}\nstderr: ${applyResult.stderr}`);

      // Verify yaml-agent file was recreated
      assert.ok(
        fileExists(env, ".claude/agents/trc-yaml-agent.md"),
        "Agent file .claude/agents/trc-yaml-agent.md should exist after apply",
      );
    } finally {
      env.cleanup();
    }
  });

  it("diff before sync: local + remote changes", { timeout: 30_000 }, async () => {
    const env = createIsolatedEnv("wf-diff-first");
    try {
      const initResult = await runCli(
        ["init", "--name", "diff-first", "--team", "backend", "--platform", "claude-code"],
        env,
      );
      assert.equal(initResult.exitCode, 0, `Init failed.\nstdout: ${initResult.stdout}\nstderr: ${initResult.stderr}`);

      // Establish sync state
      const firstSync = await runCli(["sync", "--platform", "claude-code"], env);
      assert.equal(firstSync.exitCode, 0, `First sync failed.\nstdout: ${firstSync.stdout}\nstderr: ${firstSync.stderr}`);

      const token = getToken(env);
      assert.ok(token, "Token should exist");
      const teamId = getTeamId(env);
      assert.ok(teamId, "Team ID should exist");

      // Read existing members
      const yamlBefore = readYaml(env);
      const memberMatches = [...yamlBefore.matchAll(/- name: (.+)\n\s+role: (.+)/g)];
      const existingMembers = memberMatches.map((m) => ({ name: m[1].trim(), role: m[2].trim() }));

      // Add local-only member
      const localMember = "  - name: local-diff-agent\n    role: Local Diff Tester\n";
      const updatedYaml = yamlBefore.replace(/^(members:\n)/m, `$1${localMember}`);
      writeYaml(env, updatedYaml);

      // Add remote-only member
      await testSetup("update_team", {
        token,
        team_id: teamId,
        team: {
          name: "diff-first",
          members: [
            ...existingMembers,
            { name: "remote-diff-agent", role: "Remote Diff Tester" },
          ],
        },
      });

      // Diff should show both changes
      const diffResult = await runCli(["diff"], env);
      assert.equal(diffResult.exitCode, 0, `Diff failed.\nstdout: ${diffResult.stdout}\nstderr: ${diffResult.stderr}`);

      const diffOutput = diffResult.stdout + diffResult.stderr;
      assert.ok(
        diffOutput.includes("local-diff-agent") || diffOutput.includes("remote-diff-agent"),
        `Diff should mention at least one of the divergent agents.\nOutput: ${diffOutput}`,
      );

      // Sync to resolve
      const syncResult = await runCli(["sync", "--platform", "claude-code"], env);
      assert.equal(syncResult.exitCode, 0, `Sync failed.\nstdout: ${syncResult.stdout}\nstderr: ${syncResult.stderr}`);

      // After sync, YAML should contain the remote agent at minimum
      const yamlAfter = readYaml(env);
      assert.ok(
        yamlAfter.includes("remote-diff-agent"),
        `YAML should contain "remote-diff-agent" after sync.\nYAML:\n${yamlAfter}`,
      );
    } finally {
      env.cleanup();
    }
  });

  it("local-only → connect later via push", { timeout: 30_000 }, async () => {
    const env = createIsolatedEnv("wf-local-connect");
    try {
      // Init local-only
      const initResult = await runCli(
        ["init", "--name", "local-connect", "--team", "backend", "--local", "--platform", "claude-code"],
        env,
      );
      assert.equal(initResult.exitCode, 0, `Init failed.\nstdout: ${initResult.stdout}\nstderr: ${initResult.stderr}`);

      // Verify no teamId
      const yamlBefore = readYaml(env);
      assert.ok(!yamlBefore.includes("teamId:"), "YAML should NOT contain teamId for local-only init");

      // Push to connect to relay
      const pushResult = await runCli(["push"], env);
      assert.equal(pushResult.exitCode, 0, `Push failed.\nstdout: ${pushResult.stdout}\nstderr: ${pushResult.stderr}`);

      // Verify teamId now exists in YAML
      const yamlAfter = readYaml(env);
      assert.ok(yamlAfter.includes("teamId:"), "YAML should contain teamId after push");

      // Pull should work (exits 0)
      const pullResult = await runCli(["pull"], env);
      assert.equal(pullResult.exitCode, 0, `Pull after push failed.\nstdout: ${pullResult.stdout}\nstderr: ${pullResult.stderr}`);
    } finally {
      env.cleanup();
    }
  });

  it("share → clone → pull", { timeout: 30_000 }, async () => {
    const envA = createIsolatedEnv("wf-share-a");
    const envB = createIsolatedEnv("wf-share-b");
    try {
      // A: init relay-connected
      const initResult = await runCli(
        ["init", "--name", "share-src", "--team", "backend", "--platform", "claude-code"],
        envA,
      );
      assert.equal(initResult.exitCode, 0, `A init failed.\nstdout: ${initResult.stdout}\nstderr: ${initResult.stderr}`);

      const initOutput = initResult.stdout + initResult.stderr;

      // Extract claim secret from init output
      const claimMatch = initOutput.match(/trc_ocs_[A-Za-z0-9_-]+/);
      assert.ok(claimMatch, `Init output should contain claim secret. Output: ${initOutput}`);
      const claimSecret = claimMatch[0];

      // Simulate login
      await setupLogin(envA);

      // Claim ownership
      const claimResult = await runCli(["claim", claimSecret], envA);
      assert.equal(claimResult.exitCode, 0, `Claim failed.\nstdout: ${claimResult.stdout}\nstderr: ${claimResult.stderr}`);

      // Share → get clone token
      const shareResult = await runCli(["share"], envA);
      assert.equal(shareResult.exitCode, 0, `Share failed.\nstdout: ${shareResult.stdout}\nstderr: ${shareResult.stderr}`);

      const shareOutput = shareResult.stdout + shareResult.stderr;
      const cloneTokenMatch = shareOutput.match(/trc_cl_[A-Za-z0-9_-]+/);
      assert.ok(cloneTokenMatch, `Share output should contain clone token. Output: ${shareOutput}`);
      const cloneToken = cloneTokenMatch[0];

      // B: clone using the clone token
      const cloneResult = await runCli(
        ["clone", cloneToken, "--platform", "claude-code", "--relay", "http://localhost:4002"],
        envB,
      );
      assert.equal(cloneResult.exitCode, 0, `B clone failed.\nstdout: ${cloneResult.stdout}\nstderr: ${cloneResult.stderr}`);

      // A: edit YAML to add "shared-agent" and push
      const yamlA = readYaml(envA);
      const newMember = "  - name: shared-agent\n    role: Shared Agent\n";
      const updatedYamlA = yamlA.replace(/^(members:\n)/m, `$1${newMember}`);
      writeYaml(envA, updatedYamlA);

      const pushResult = await runCli(["push"], envA);
      assert.equal(pushResult.exitCode, 0, `A push failed.\nstdout: ${pushResult.stdout}\nstderr: ${pushResult.stderr}`);

      // B: pull to get the update
      const pullResult = await runCli(["pull", "--platform", "claude-code"], envB);
      assert.equal(pullResult.exitCode, 0, `B pull failed.\nstdout: ${pullResult.stdout}\nstderr: ${pullResult.stderr}`);

      // B's YAML should contain "shared-agent"
      const yamlB = readYaml(envB);
      assert.ok(
        yamlB.includes("shared-agent"),
        `B's YAML should contain "shared-agent" after pull.\nYAML:\n${yamlB}`,
      );
    } finally {
      envA.cleanup();
      envB.cleanup();
    }
  });

  it("multi-machine sync: A and B exchange members", { timeout: 30_000 }, async () => {
    const envA = createIsolatedEnv("wf-multi-a");
    const envB = createIsolatedEnv("wf-multi-b");
    try {
      // A: init
      const initResult = await runCli(
        ["init", "--name", "multi-sync", "--team", "backend", "--platform", "claude-code"],
        envA,
      );
      assert.equal(initResult.exitCode, 0, `A init failed.\nstdout: ${initResult.stdout}\nstderr: ${initResult.stderr}`);

      // A: invite
      const inviteResult = await runCli(["invite"], envA);
      assert.equal(inviteResult.exitCode, 0, `A invite failed.\nstdout: ${inviteResult.stdout}\nstderr: ${inviteResult.stderr}`);
      const inviteMatch = inviteResult.stdout.match(INVITE_RE);
      assert.ok(inviteMatch, `Invite should contain code. stdout: ${inviteResult.stdout}`);

      // B: join
      const joinResult = await runCli(
        ["join", inviteMatch[0], "--platform", "claude-code", "--relay", "http://localhost:4002"],
        envB,
      );
      assert.equal(joinResult.exitCode, 0, `B join failed.\nstdout: ${joinResult.stdout}\nstderr: ${joinResult.stderr}`);

      // A: establish sync state
      const syncA1 = await runCli(["sync", "--platform", "claude-code"], envA);
      assert.equal(syncA1.exitCode, 0, `A first sync failed.\nstdout: ${syncA1.stdout}\nstderr: ${syncA1.stderr}`);

      // B: establish sync state
      const syncB1 = await runCli(["sync", "--platform", "claude-code"], envB);
      assert.equal(syncB1.exitCode, 0, `B first sync failed.\nstdout: ${syncB1.stdout}\nstderr: ${syncB1.stderr}`);

      // A: re-sync to pick up any changes B's sync might have pushed
      const syncA1b = await runCli(["sync", "--platform", "claude-code"], envA);
      assert.equal(syncA1b.exitCode, 0, `A re-sync failed.\nstdout: ${syncA1b.stdout}\nstderr: ${syncA1b.stderr}`);

      // A: edit YAML (add "a-agent") + sync to push
      const yamlA = readYaml(envA);
      const aMember = "  - name: a-agent\n    role: A's Agent\n";
      writeYaml(envA, yamlA.replace(/^(members:\n)/m, `$1${aMember}`));

      const syncA2 = await runCli(["sync", "--platform", "claude-code"], envA);
      assert.equal(syncA2.exitCode, 0, `A sync (push) failed.\nstdout: ${syncA2.stdout}\nstderr: ${syncA2.stderr}`);

      // B: sync → B should have "a-agent"
      const syncB2 = await runCli(["sync", "--platform", "claude-code"], envB);
      assert.equal(syncB2.exitCode, 0, `B sync failed.\nstdout: ${syncB2.stdout}\nstderr: ${syncB2.stderr}`);

      const yamlB1 = readYaml(envB);
      assert.ok(yamlB1.includes("a-agent"), `B's YAML should contain "a-agent" after sync.\nYAML:\n${yamlB1}`);

      // B: edit YAML (add "b-agent") + sync to push
      const bMember = "  - name: b-agent\n    role: B's Agent\n";
      writeYaml(envB, yamlB1.replace(/^(members:\n)/m, `$1${bMember}`));

      const syncB3 = await runCli(["sync", "--platform", "claude-code"], envB);
      assert.equal(syncB3.exitCode, 0, `B sync (push) failed.\nstdout: ${syncB3.stdout}\nstderr: ${syncB3.stderr}`);

      // A: sync → A should have "b-agent"
      const syncA3 = await runCli(["sync", "--platform", "claude-code"], envA);
      assert.equal(syncA3.exitCode, 0, `A sync failed.\nstdout: ${syncA3.stdout}\nstderr: ${syncA3.stderr}`);

      const yamlA2 = readYaml(envA);
      assert.ok(yamlA2.includes("b-agent"), `A's YAML should contain "b-agent" after sync.\nYAML:\n${yamlA2}`);
    } finally {
      envA.cleanup();
      envB.cleanup();
    }
  });

  it("knowledge round-trip: push local knowledge → pull on new machine", { timeout: 30_000 }, async () => {
    const envA = createIsolatedEnv("wf-know-a");
    const envB = createIsolatedEnv("wf-know-b");
    try {
      // A: init
      const initResult = await runCli(
        ["init", "--name", "know-round", "--team", "backend", "--platform", "claude-code"],
        envA,
      );
      assert.equal(initResult.exitCode, 0, `A init failed.\nstdout: ${initResult.stdout}\nstderr: ${initResult.stderr}`);

      // A: write local knowledge
      const knowledgePath = ".teamrc/knowledge-know-round.md";
      writeFile(envA, knowledgePath, "Local knowledge line 1\n");

      // A: push to upload knowledge
      const pushResult = await runCli(["push"], envA);
      assert.equal(pushResult.exitCode, 0, `A push failed.\nstdout: ${pushResult.stdout}\nstderr: ${pushResult.stderr}`);

      // A: invite
      const inviteResult = await runCli(["invite"], envA);
      assert.equal(inviteResult.exitCode, 0, `A invite failed.\nstdout: ${inviteResult.stdout}\nstderr: ${inviteResult.stderr}`);
      const inviteMatch = inviteResult.stdout.match(INVITE_RE);
      assert.ok(inviteMatch, `Invite should contain code. stdout: ${inviteResult.stdout}`);

      // B: join
      const joinResult = await runCli(
        ["join", inviteMatch[0], "--platform", "claude-code", "--relay", "http://localhost:4002"],
        envB,
      );
      assert.equal(joinResult.exitCode, 0, `B join failed.\nstdout: ${joinResult.stdout}\nstderr: ${joinResult.stderr}`);

      // B: pull to get knowledge
      const pullResult = await runCli(["pull", "--platform", "claude-code"], envB);
      assert.equal(pullResult.exitCode, 0, `B pull failed.\nstdout: ${pullResult.stdout}\nstderr: ${pullResult.stderr}`);

      // B's knowledge file should contain the line
      const knowledgeB = readFile(envB, knowledgePath);
      assert.ok(
        knowledgeB.includes("Local knowledge line 1"),
        `B's knowledge file should contain "Local knowledge line 1".\nContent:\n${knowledgeB}`,
      );
    } finally {
      envA.cleanup();
      envB.cleanup();
    }
  });
});
