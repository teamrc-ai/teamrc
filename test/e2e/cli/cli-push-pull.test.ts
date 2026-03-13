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
  writeYaml,
  type IsolatedEnv,
} from "./helpers.ts";

before(async () => {
  await waitForServer();
});

beforeEach(async () => {
  await testSetup("clear_rate_limits");
});

describe("teamrc push/pull", () => {
  it("push local-only team to relay", async () => {
    const env = createIsolatedEnv("push-local");
    try {
      // Create a local-only team
      const initResult = await runCli(
        ["init", "--name", "push-test", "--team", "backend", "--local", "--platform", "claude-code"],
        env,
      );
      assert.equal(initResult.exitCode, 0, `Init should succeed. stderr: ${initResult.stderr}`);

      // Verify no teamId in YAML
      const yamlBefore = readYaml(env);
      assert.ok(!yamlBefore.includes("teamId:"), "YAML should NOT contain teamId before push");

      // Push to relay
      const pushResult = await runCli(["push"], env);
      assert.equal(pushResult.exitCode, 0, `Push should succeed. stdout: ${pushResult.stdout}\nstderr: ${pushResult.stderr}`);

      // Verify YAML now has teamId and relay
      const yamlAfter = readYaml(env);
      assert.ok(yamlAfter.includes("teamId:"), "YAML should contain teamId after push");
      assert.ok(yamlAfter.includes("relay:"), "YAML should contain relay after push");

      // Verify stdout mentions team created
      const combined = pushResult.stdout + pushResult.stderr;
      assert.match(combined, /Team created on relay/i, "Output should mention 'Team created on relay'");
    } finally {
      env.cleanup();
    }
  });

  it("pull remote changes", async () => {
    const env = createIsolatedEnv("pull-remote");
    try {
      // Create a relay-connected team
      const initResult = await runCli(
        ["init", "--name", "pull-test", "--team", "backend", "--platform", "claude-code"],
        env,
      );
      assert.equal(initResult.exitCode, 0, `Init should succeed. stderr: ${initResult.stderr}`);

      // Get the token and teamId from the env
      const token = getToken(env);
      assert.ok(token, "Token should exist after init");
      const teamId = getTeamId(env);
      assert.ok(teamId, "teamId should exist after relay-connected init");

      // Read original YAML to find the existing members
      const originalYaml = readYaml(env);
      const memberMatches = [...originalYaml.matchAll(/- name: (.+)/g)];
      const originalMembers = memberMatches.map((m) => {
        const nameMatch = m[1].trim();
        // Find the role line that follows
        return { name: nameMatch };
      });

      // Build members array with original members + new one
      const membersForUpdate = [
        ...originalMembers.map((m) => ({ name: m.name, role: "Backend" })),
        { name: "new-agent", role: "QA" },
      ];

      // Add a member via API
      await testSetup("update_team", {
        token,
        team_id: teamId,
        team: {
          name: "pull-test",
          members: membersForUpdate,
        },
      });

      // Pull changes
      const pullResult = await runCli(["pull", "--platform", "claude-code"], env);
      assert.equal(pullResult.exitCode, 0, `Pull should succeed. stdout: ${pullResult.stdout}\nstderr: ${pullResult.stderr}`);

      // Verify YAML contains the new agent
      const yamlAfter = readYaml(env);
      assert.ok(yamlAfter.includes("new-agent"), "YAML should contain 'new-agent' after pull");

      // Verify platform file was created for the new agent
      assert.ok(
        fileExists(env, ".claude/agents/trc-new-agent.md"),
        "Agent file trc-new-agent.md should exist after pull",
      );
    } finally {
      env.cleanup();
    }
  });

  it("pull when already up-to-date", async () => {
    const env = createIsolatedEnv("pull-uptodate");
    try {
      // Create a relay-connected team
      const initResult = await runCli(
        ["init", "--name", "uptodate", "--team", "backend", "--platform", "claude-code"],
        env,
      );
      assert.equal(initResult.exitCode, 0, `Init should succeed. stderr: ${initResult.stderr}`);

      // First sync to establish sync state
      const syncResult = await runCli(["sync", "--platform", "claude-code"], env);
      assert.equal(syncResult.exitCode, 0, `Sync should succeed. stdout: ${syncResult.stdout}\nstderr: ${syncResult.stderr}`);

      // Pull again (no remote changes since sync)
      const pullResult = await runCli(["pull"], env);
      assert.equal(pullResult.exitCode, 0, `Pull should succeed. stdout: ${pullResult.stdout}\nstderr: ${pullResult.stderr}`);

      // Verify "Already up to date" message
      const combined = pullResult.stdout + pullResult.stderr;
      assert.match(combined, /Already up to date|up to date|Done/i, "Output should indicate no changes needed");
    } finally {
      env.cleanup();
    }
  });

  it("push YAML edits", async () => {
    const env = createIsolatedEnv("push-edit");
    try {
      // Create a relay-connected team
      const initResult = await runCli(
        ["init", "--name", "push-edit", "--team", "backend", "--platform", "claude-code"],
        env,
      );
      assert.equal(initResult.exitCode, 0, `Init should succeed. stderr: ${initResult.stderr}`);

      // Parse YAML, add a new member, and write back
      const yamlText = readYaml(env);
      const parsed = YAML.parse(yamlText);
      parsed.members.push({ name: "push-added", role: "Added via push" });
      writeYaml(env, YAML.stringify(parsed));

      // Push the edits
      const pushResult = await runCli(["push"], env);
      assert.equal(pushResult.exitCode, 0, `Push should succeed. stdout: ${pushResult.stdout}\nstderr: ${pushResult.stderr}`);

      // Verify via API that the remote team has the new member
      const kp = loadKeypairFromEnv(env);
      assert.ok(kp, "Keypair should exist");
      const teamId = getTeamId(env);
      assert.ok(teamId, "teamId should exist");

      const res = await signedGet(`/api/teams/${kp.token}?team_id=${teamId}`, kp);
      assert.equal(res.status, 200, "API GET should succeed");
      const data = (await res.json()) as { team: { members: Array<{ name: string }> } };
      const memberNames = data.team.members.map((m) => m.name);
      assert.ok(
        memberNames.includes("push-added"),
        `Remote team should contain 'push-added'. Got: ${memberNames.join(", ")}`,
      );
    } finally {
      env.cleanup();
    }
  });

  it("pull with knowledge merge", async () => {
    const env = createIsolatedEnv("pull-knowledge");
    try {
      // Create a relay-connected team (init creates default knowledge and pushes it)
      const initResult = await runCli(
        ["init", "--name", "know-merge", "--team", "backend", "--platform", "claude-code"],
        env,
      );
      assert.equal(initResult.exitCode, 0, `Init should succeed. stderr: ${initResult.stderr}`);

      const token = getToken(env);
      assert.ok(token, "Token should exist");
      const teamId = getTeamId(env);
      assert.ok(teamId, "teamId should exist");

      // Verify that init created a knowledge file with default content
      const knowledgePath = ".teamrc/knowledge-know-merge.md";
      assert.ok(fileExists(env, knowledgePath), "Knowledge file should exist after init");
      const localKnowledge = readFile(env, knowledgePath);
      assert.ok(localKnowledge.includes("Team Knowledge"), "Default knowledge should contain 'Team Knowledge'");

      // Update knowledge on the server with different content
      await testSetup("update_team", {
        token,
        team_id: teamId,
        team: {
          name: "know-merge",
          members: [{ name: "architect", role: "System architect" }],
          knowledge: "# Team Knowledge\n\nShared findings and decisions across team members.\n\n## Server Update\n\nThis line was added on the server.\n",
        },
      });

      // Pull changes
      const pullResult = await runCli(["pull", "--platform", "claude-code"], env);
      assert.equal(pullResult.exitCode, 0, `Pull should succeed. stdout: ${pullResult.stdout}\nstderr: ${pullResult.stderr}`);

      // Read knowledge file and verify it has merged content
      const mergedKnowledge = readFile(env, knowledgePath);
      assert.ok(
        mergedKnowledge.includes("Server Update"),
        `Knowledge should contain 'Server Update' after merge. Got: ${mergedKnowledge}`,
      );
      assert.ok(
        mergedKnowledge.includes("Team Knowledge"),
        "Knowledge should still contain original 'Team Knowledge' heading",
      );
    } finally {
      env.cleanup();
    }
  });

  it("export from relay", async () => {
    const env = createIsolatedEnv("export-relay");
    try {
      // Create a relay-connected team
      const initResult = await runCli(
        ["init", "--name", "export-test", "--team", "backend", "--platform", "claude-code"],
        env,
      );
      assert.equal(initResult.exitCode, 0, `Init should succeed. stderr: ${initResult.stderr}`);

      // Save the teamId and relay URL from the YAML before deleting it
      const yamlBefore = readYaml(env);
      const teamId = getTeamId(env);
      assert.ok(teamId, "teamId should exist");
      const relayMatch = yamlBefore.match(/relay:\s*(.+)/);
      assert.ok(relayMatch, "relay should exist in YAML");
      const relay = relayMatch[1].trim();

      // Delete the local YAML
      fs.unlinkSync(path.join(env.projectDir, ".teamrc.yaml"));
      assert.ok(!fileExists(env, ".teamrc.yaml"), "YAML should be deleted");

      // Write a minimal YAML with just the connection info so export can find the relay context
      const minimalYaml = [
        `name: export-test`,
        `teamId: ${teamId}`,
        `relay: ${relay}`,
        `platforms:`,
        `  - claude-code`,
        `members: []`,
        "",
      ].join("\n");
      writeYaml(env, minimalYaml);

      // Run export
      const exportResult = await runCli(["export"], env);
      assert.equal(exportResult.exitCode, 0, `Export should succeed. stdout: ${exportResult.stdout}\nstderr: ${exportResult.stderr}`);

      // Verify YAML was recreated with correct data
      assert.ok(fileExists(env, ".teamrc.yaml"), "YAML should be recreated after export");
      const yamlAfter = readYaml(env);
      assert.ok(yamlAfter.includes("export-test"), "Exported YAML should contain team name");
      assert.ok(yamlAfter.includes("members:"), "Exported YAML should contain members");
      // The export should have fetched full member data from relay
      assert.ok(yamlAfter.includes("architect"), "Exported YAML should contain 'architect' member from backend template");
    } finally {
      env.cleanup();
    }
  });

  it("push with logged-in machine → auto-owner", async () => {
    const env = createIsolatedEnv("push-auto-own");
    try {
      // Create a local-only team (generates keypair)
      const initResult = await runCli(
        ["init", "--local", "--name", "push-own", "--team", "backend", "--platform", "claude-code"],
        env,
      );
      assert.equal(initResult.exitCode, 0, `Init should succeed. stderr: ${initResult.stderr}`);

      // Get token, create user, link token (simulates being logged in)
      const token = getToken(env);
      assert.ok(token, "Token should exist after init");

      const { user_id } = (await testSetup("create_user")) as { user_id: string };
      await testSetup("link_token", { user_id, token });

      // Push to relay
      const pushResult = await runCli(["push"], env);
      assert.equal(pushResult.exitCode, 0, `Push should succeed. stdout: ${pushResult.stdout}\nstderr: ${pushResult.stderr}`);

      // Verify auto-ownership message
      const combined = pushResult.stdout + pushResult.stderr;
      assert.match(combined, /You own this team/i, "Output should confirm auto-ownership");
    } finally {
      env.cleanup();
    }
  });
});
