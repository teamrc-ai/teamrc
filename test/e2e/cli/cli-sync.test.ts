import { describe, it, before, beforeEach } from "node:test";
import assert from "node:assert/strict";
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
  getToken,
  getTeamId,
  loadKeypairFromEnv,
  signedGet,
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

describe("teamrc sync", () => {
  it("first sync after push", async () => {
    const env = createIsolatedEnv("sync-first");
    try {
      // Init creates the team on relay and pushes it
      const initResult = await runCli(
        ["init", "--name", "sync-first", "--team", "backend", "--platform", "claude-code"],
        env,
      );
      assert.equal(initResult.exitCode, 0, `Init failed.\nstdout: ${initResult.stdout}\nstderr: ${initResult.stderr}`);

      // Sync should find everything in sync (init already pushed)
      const syncResult = await runCli(
        ["sync", "--platform", "claude-code"],
        env,
      );
      assert.equal(syncResult.exitCode, 0, `Sync failed.\nstdout: ${syncResult.stdout}\nstderr: ${syncResult.stderr}`);

      const combined = syncResult.stdout + syncResult.stderr;
      assert.match(
        combined,
        /in sync|Already in sync/i,
        `Expected "in sync" or "Already in sync" in output.\nstdout: ${syncResult.stdout}\nstderr: ${syncResult.stderr}`,
      );
    } finally {
      env.cleanup();
    }
  });

  it("sync pulls remote changes", async () => {
    const env = createIsolatedEnv("sync-pull");
    try {
      // Init creates the team on relay
      const initResult = await runCli(
        ["init", "--name", "sync-pull", "--team", "backend", "--platform", "claude-code"],
        env,
      );
      assert.equal(initResult.exitCode, 0, `Init failed.\nstdout: ${initResult.stdout}\nstderr: ${initResult.stderr}`);

      // Establish sync state so subsequent sync detects remote changes
      const firstSync = await runCli(
        ["sync", "--platform", "claude-code"],
        env,
      );
      assert.equal(firstSync.exitCode, 0, `First sync failed.\nstdout: ${firstSync.stdout}\nstderr: ${firstSync.stderr}`);

      const token = getToken(env);
      assert.ok(token, "Token should exist after init");
      const teamId = getTeamId(env);
      assert.ok(teamId, "Team ID should exist after init");

      // Read existing YAML and parse properly to extract members
      const yamlBefore = readYaml(env);
      const parsed = YAML.parse(yamlBefore);
      const existingMembers = (parsed.members || []).map((m: { name: string; role: string }) => ({
        name: m.name,
        role: m.role,
      }));

      // Update team on server to add a new member
      await testSetup("update_team", {
        token,
        team_id: teamId,
        team: {
          name: "sync-pull",
          members: [
            ...existingMembers,
            { name: "qa-agent", role: "Quality Assurance" },
          ],
        },
      });

      // Sync should pull the remote changes
      const syncResult = await runCli(
        ["sync", "--platform", "claude-code"],
        env,
      );
      assert.equal(syncResult.exitCode, 0, `Sync failed.\nstdout: ${syncResult.stdout}\nstderr: ${syncResult.stderr}`);

      // YAML should contain the new member
      const yamlAfter = readYaml(env);
      assert.ok(
        yamlAfter.includes("qa-agent"),
        `YAML should contain "qa-agent" after sync.\nYAML:\n${yamlAfter}`,
      );

      // Agent file should be created for the new member
      assert.ok(
        fileExists(env, ".claude/agents/trc-qa-agent.md"),
        "Agent file .claude/agents/trc-qa-agent.md should exist after sync",
      );
    } finally {
      env.cleanup();
    }
  });

  it("sync pushes local changes", async () => {
    const env = createIsolatedEnv("sync-push");
    try {
      // Init creates the team on relay
      const initResult = await runCli(
        ["init", "--name", "sync-push", "--team", "backend", "--platform", "claude-code"],
        env,
      );
      assert.equal(initResult.exitCode, 0, `Init failed.\nstdout: ${initResult.stdout}\nstderr: ${initResult.stderr}`);

      const teamId = getTeamId(env);
      assert.ok(teamId, "Team ID should exist after init");

      // Edit YAML to add a new member
      const yaml = readYaml(env);
      const newMember = "  - name: new-local-agent\n    role: Local Developer\n";
      const updatedYaml = yaml.replace(
        /^(members:\n)/m,
        `$1${newMember}`,
      );
      writeYaml(env, updatedYaml);

      // Sync should push local changes
      const syncResult = await runCli(
        ["sync"],
        env,
      );
      assert.equal(syncResult.exitCode, 0, `Sync failed.\nstdout: ${syncResult.stdout}\nstderr: ${syncResult.stderr}`);

      // Verify remote has the new member
      const kp = loadKeypairFromEnv(env);
      assert.ok(kp, "Keypair should exist");
      const getRes = await signedGet(
        `/api/teams/${kp.token}?team_id=${teamId}`,
        kp,
      );
      assert.equal(getRes.status, 200, "GET team should return 200");
      const data = (await getRes.json()) as { team: { members: Array<{ name: string }> } };
      const memberNames = data.team.members.map((m) => m.name);
      assert.ok(
        memberNames.includes("new-local-agent"),
        `Remote should contain "new-local-agent".\nRemote members: ${memberNames.join(", ")}`,
      );
    } finally {
      env.cleanup();
    }
  });

  it("sync merges knowledge", async () => {
    const env = createIsolatedEnv("sync-know");
    try {
      // Init creates the team on relay
      const initResult = await runCli(
        ["init", "--name", "sync-know", "--team", "backend", "--platform", "claude-code"],
        env,
      );
      assert.equal(initResult.exitCode, 0, `Init failed.\nstdout: ${initResult.stdout}\nstderr: ${initResult.stderr}`);

      const token = getToken(env);
      assert.ok(token, "Token should exist after init");
      const teamId = getTeamId(env);
      assert.ok(teamId, "Team ID should exist after init");

      // Write local knowledge
      const knowledgePath = ".teamrc/knowledge-sync-know.md";
      writeFile(env, knowledgePath, "Local finding 1\n");

      // Push to upload local knowledge
      const pushResult = await runCli(
        ["push"],
        env,
      );
      assert.equal(pushResult.exitCode, 0, `Push failed.\nstdout: ${pushResult.stdout}\nstderr: ${pushResult.stderr}`);

      // Read current members from YAML for the server update
      const yamlContent = readYaml(env);
      const parsedContent = YAML.parse(yamlContent);
      const existingMembers = (parsedContent.members || []).map((m: { name: string; role: string }) => ({
        name: m.name,
        role: m.role,
      }));

      // Update team knowledge on server to include remote content
      await testSetup("update_team", {
        token,
        team_id: teamId,
        team: {
          name: "sync-know",
          members: existingMembers,
          knowledge: "Remote finding 1\nLocal finding 1\n",
        },
      });

      // Write local knowledge again (simulating local edit since last push)
      writeFile(env, knowledgePath, "Local finding 1\n");

      // Sync should merge knowledge from both sides
      const syncResult = await runCli(
        ["sync", "--platform", "claude-code"],
        env,
      );
      assert.equal(syncResult.exitCode, 0, `Sync failed.\nstdout: ${syncResult.stdout}\nstderr: ${syncResult.stderr}`);

      // Knowledge file should contain both findings
      const knowledge = readFile(env, knowledgePath);
      assert.ok(
        knowledge.includes("Local finding 1"),
        `Knowledge should contain "Local finding 1".\nKnowledge:\n${knowledge}`,
      );
      assert.ok(
        knowledge.includes("Remote finding 1"),
        `Knowledge should contain "Remote finding 1".\nKnowledge:\n${knowledge}`,
      );
    } finally {
      env.cleanup();
    }
  });

  it("sync with member divergence", async () => {
    const env = createIsolatedEnv("sync-div");
    try {
      // Init creates the team on relay
      const initResult = await runCli(
        ["init", "--name", "sync-div", "--team", "backend", "--platform", "claude-code"],
        env,
      );
      assert.equal(initResult.exitCode, 0, `Init failed.\nstdout: ${initResult.stdout}\nstderr: ${initResult.stderr}`);

      // Establish sync state so subsequent sync detects changes
      const firstSync = await runCli(
        ["sync", "--platform", "claude-code"],
        env,
      );
      assert.equal(firstSync.exitCode, 0, `First sync failed.\nstdout: ${firstSync.stdout}\nstderr: ${firstSync.stderr}`);

      const token = getToken(env);
      assert.ok(token, "Token should exist after init");
      const teamId = getTeamId(env);
      assert.ok(teamId, "Team ID should exist after init");

      // Read existing YAML and parse properly to extract members
      const yamlBefore = readYaml(env);
      const parsed = YAML.parse(yamlBefore);
      const existingMembers = (parsed.members || []).map((m: { name: string; role: string }) => ({
        name: m.name,
        role: m.role,
      }));

      // Edit YAML to add a local-only member using proper YAML parsing
      editTeamYaml(env, (doc) => {
        const members = doc.members as Array<{ name: string; role: string }>;
        members.unshift({ name: "local-agent", role: "Local Developer" });
      });

      // Also update remote to add a different member
      await testSetup("update_team", {
        token,
        team_id: teamId,
        team: {
          name: "sync-div",
          members: [
            ...existingMembers,
            { name: "remote-agent", role: "Remote Developer" },
          ],
        },
      });

      // Sync with both sides having changes  --  should pull remote first
      const syncResult = await runCli(
        ["sync", "--platform", "claude-code"],
        env,
      );
      assert.equal(syncResult.exitCode, 0, `Sync failed.\nstdout: ${syncResult.stdout}\nstderr: ${syncResult.stderr}`);

      // After sync, YAML should contain the remote-agent (pulled from server)
      const yamlAfter = readYaml(env);
      assert.ok(
        yamlAfter.includes("remote-agent"),
        `YAML should contain "remote-agent" after sync.\nYAML:\n${yamlAfter}`,
      );

      // Stdout may warn about needing to push local changes
      const combined = syncResult.stdout + syncResult.stderr;
      // The sync command in divergence mode pulls remote first and warns about push
      assert.ok(
        combined.includes("push") || combined.includes("Pull") || combined.includes("Sync"),
        `Output should mention pulling or pushing.\nOutput:\n${combined}`,
      );
    } finally {
      env.cleanup();
    }
  });
});
