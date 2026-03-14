import { describe, it, before, beforeEach } from "node:test";
import assert from "node:assert/strict";
import YAML from "yaml";
import {
  createIsolatedEnv,
  runCli,
  testSetup,
  waitForServer,
  readYaml,
  getToken,
  getTeamId,
  loadKeypairFromEnv,
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

describe("teamrc diff", () => {
  it("diff shows no changes", async () => {
    const env = createIsolatedEnv("diff-none");
    try {
      // Init creates the team on relay and pushes  --  local and remote should match
      const initResult = await runCli(
        ["init", "--name", "diff-none", "--team", "backend", "--platform", "claude-code"],
        env,
      );
      assert.equal(initResult.exitCode, 0, `Init failed.\nstdout: ${initResult.stdout}\nstderr: ${initResult.stderr}`);

      const diffResult = await runCli(["diff"], env);
      assert.equal(diffResult.exitCode, 0, `Diff failed.\nstdout: ${diffResult.stdout}\nstderr: ${diffResult.stderr}`);

      const combined = diffResult.stdout + diffResult.stderr;
      assert.match(
        combined,
        /in sync|Everything in sync/i,
        `Expected "in sync" or "Everything in sync" in output.\nstdout: ${diffResult.stdout}\nstderr: ${diffResult.stderr}`,
      );
    } finally {
      env.cleanup();
    }
  });

  it("diff shows local additions", async () => {
    const env = createIsolatedEnv("diff-local");
    try {
      const initResult = await runCli(
        ["init", "--name", "diff-local", "--team", "backend", "--platform", "claude-code"],
        env,
      );
      assert.equal(initResult.exitCode, 0, `Init failed.\nstdout: ${initResult.stdout}\nstderr: ${initResult.stderr}`);

      // Edit YAML to add a local-only member
      editTeamYaml(env, (doc) => {
        const members = doc.members as Array<{ name: string; role: string }>;
        members.unshift({ name: "local-only-agent", role: "Local Specialist" });
      });

      const diffResult = await runCli(["diff"], env);
      assert.equal(diffResult.exitCode, 0, `Diff failed.\nstdout: ${diffResult.stdout}\nstderr: ${diffResult.stderr}`);

      const combined = diffResult.stdout + diffResult.stderr;
      assert.ok(
        combined.includes("local-only-agent"),
        `Output should contain "local-only-agent".\nstdout: ${diffResult.stdout}\nstderr: ${diffResult.stderr}`,
      );
      assert.ok(
        combined.toLowerCase().includes("local only"),
        `Output should contain "local only".\nstdout: ${diffResult.stdout}\nstderr: ${diffResult.stderr}`,
      );
    } finally {
      env.cleanup();
    }
  });

  it("diff shows remote additions", async () => {
    const env = createIsolatedEnv("diff-remote");
    try {
      const initResult = await runCli(
        ["init", "--name", "diff-remote", "--team", "backend", "--platform", "claude-code"],
        env,
      );
      assert.equal(initResult.exitCode, 0, `Init failed.\nstdout: ${initResult.stdout}\nstderr: ${initResult.stderr}`);

      const token = getToken(env);
      assert.ok(token, "Token should exist after init");
      const teamId = getTeamId(env);
      assert.ok(teamId, "Team ID should exist after init");

      // Read existing members so update_team includes them
      const yamlBefore = readYaml(env);
      const parsed = YAML.parse(yamlBefore);
      const existingMembers = (parsed.members || []).map((m: { name: string; role: string }) => ({
        name: m.name,
        role: m.role,
      }));

      // Add a remote-only member via the test setup endpoint
      await testSetup("update_team", {
        token,
        team_id: teamId,
        team: {
          name: "diff-remote",
          members: [
            ...existingMembers,
            { name: "remote-only-agent", role: "Remote Specialist" },
          ],
        },
      });

      const diffResult = await runCli(["diff"], env);
      assert.equal(diffResult.exitCode, 0, `Diff failed.\nstdout: ${diffResult.stdout}\nstderr: ${diffResult.stderr}`);

      const combined = diffResult.stdout + diffResult.stderr;
      assert.ok(
        combined.includes("remote-only-agent"),
        `Output should contain "remote-only-agent".\nstdout: ${diffResult.stdout}\nstderr: ${diffResult.stderr}`,
      );
      assert.ok(
        combined.toLowerCase().includes("relay only"),
        `Output should contain "relay only".\nstdout: ${diffResult.stdout}\nstderr: ${diffResult.stderr}`,
      );
    } finally {
      env.cleanup();
    }
  });

  it("diff JSON output", async () => {
    const env = createIsolatedEnv("diff-json");
    try {
      const initResult = await runCli(
        ["init", "--name", "diff-json", "--team", "backend", "--platform", "claude-code"],
        env,
      );
      assert.equal(initResult.exitCode, 0, `Init failed.\nstdout: ${initResult.stdout}\nstderr: ${initResult.stderr}`);

      // Edit YAML to add a local member
      editTeamYaml(env, (doc) => {
        const members = doc.members as Array<{ name: string; role: string }>;
        members.unshift({ name: "json-diff-agent", role: "JSON Tester" });
      });

      const diffResult = await runCli(["diff", "--json"], env);
      assert.equal(diffResult.exitCode, 0, `Diff --json failed.\nstdout: ${diffResult.stdout}\nstderr: ${diffResult.stderr}`);

      const parsed = JSON.parse(diffResult.stdout.trim());
      assert.ok(Array.isArray(parsed.added), `JSON should have "added" array. Got: ${JSON.stringify(parsed)}`);
      assert.ok(
        parsed.added.includes("json-diff-agent"),
        `"added" array should include "json-diff-agent". Got: ${JSON.stringify(parsed.added)}`,
      );
    } finally {
      env.cleanup();
    }
  });
});

describe("teamrc status", () => {
  it("status shows identity", async () => {
    const env = createIsolatedEnv("status-id");
    try {
      const initResult = await runCli(
        ["init", "--name", "status-id", "--team", "backend", "--platform", "claude-code"],
        env,
      );
      assert.equal(initResult.exitCode, 0, `Init failed.\nstdout: ${initResult.stdout}\nstderr: ${initResult.stderr}`);

      const statusResult = await runCli(["status"], env);
      assert.equal(statusResult.exitCode, 0, `Status failed.\nstdout: ${statusResult.stdout}\nstderr: ${statusResult.stderr}`);

      const combined = statusResult.stdout + statusResult.stderr;
      assert.ok(
        combined.includes("trc_ak_"),
        `Output should contain token prefix "trc_ak_".\nstdout: ${statusResult.stdout}\nstderr: ${statusResult.stderr}`,
      );
      assert.ok(
        combined.includes("localhost") || combined.includes("4002"),
        `Output should contain the relay URL.\nstdout: ${statusResult.stdout}\nstderr: ${statusResult.stderr}`,
      );
      assert.ok(
        combined.includes("status-id"),
        `Output should contain team name "status-id".\nstdout: ${statusResult.stdout}\nstderr: ${statusResult.stderr}`,
      );
      assert.ok(
        combined.includes("claude-code"),
        `Output should contain platform "claude-code".\nstdout: ${statusResult.stdout}\nstderr: ${statusResult.stderr}`,
      );
    } finally {
      env.cleanup();
    }
  });

  it("status JSON output", async () => {
    const env = createIsolatedEnv("status-json");
    try {
      const initResult = await runCli(
        ["init", "--name", "status-json", "--team", "backend", "--platform", "claude-code"],
        env,
      );
      assert.equal(initResult.exitCode, 0, `Init failed.\nstdout: ${initResult.stdout}\nstderr: ${initResult.stderr}`);

      const statusResult = await runCli(["status", "--json"], env);
      assert.equal(statusResult.exitCode, 0, `Status --json failed.\nstdout: ${statusResult.stdout}\nstderr: ${statusResult.stderr}`);

      const parsed = JSON.parse(statusResult.stdout.trim());
      assert.ok(
        typeof parsed.token === "string" && parsed.token.length > 0,
        `JSON should have a "token" field. Got: ${JSON.stringify(parsed)}`,
      );
      assert.ok(
        parsed.relay !== undefined && parsed.relay !== null,
        `JSON should have a "relay" field. Got: ${JSON.stringify(parsed)}`,
      );
      assert.ok(
        typeof parsed.teamId === "string" && parsed.teamId.length > 0,
        `JSON should have a "teamId" field. Got: ${JSON.stringify(parsed)}`,
      );
    } finally {
      env.cleanup();
    }
  });

  it("status shows in sync", async () => {
    const env = createIsolatedEnv("status-sync");
    try {
      // Init creates and pushes  --  should be in sync immediately
      const initResult = await runCli(
        ["init", "--name", "status-sync", "--team", "backend", "--platform", "claude-code"],
        env,
      );
      assert.equal(initResult.exitCode, 0, `Init failed.\nstdout: ${initResult.stdout}\nstderr: ${initResult.stderr}`);

      const statusResult = await runCli(["status"], env);
      assert.equal(statusResult.exitCode, 0, `Status failed.\nstdout: ${statusResult.stdout}\nstderr: ${statusResult.stderr}`);

      const combined = statusResult.stdout + statusResult.stderr;
      assert.ok(
        combined.toLowerCase().includes("in sync"),
        `Output should contain "in sync".\nstdout: ${statusResult.stdout}\nstderr: ${statusResult.stderr}`,
      );
    } finally {
      env.cleanup();
    }
  });

  it("status shows local changes", async () => {
    const env = createIsolatedEnv("status-local");
    try {
      const initResult = await runCli(
        ["init", "--name", "status-local", "--team", "backend", "--platform", "claude-code"],
        env,
      );
      assert.equal(initResult.exitCode, 0, `Init failed.\nstdout: ${initResult.stdout}\nstderr: ${initResult.stderr}`);

      // Establish sync state so status can detect local changes
      const syncResult = await runCli(
        ["sync", "--platform", "claude-code"],
        env,
      );
      assert.equal(syncResult.exitCode, 0, `Sync failed.\nstdout: ${syncResult.stdout}\nstderr: ${syncResult.stderr}`);

      // Edit YAML to create a local change using proper YAML parsing
      editTeamYaml(env, (doc) => {
        const members = doc.members as Array<{ name: string; role: string }>;
        members.unshift({ name: "status-change-agent", role: "Change Detector" });
      });

      const statusResult = await runCli(["status"], env);
      assert.equal(statusResult.exitCode, 0, `Status failed.\nstdout: ${statusResult.stdout}\nstderr: ${statusResult.stderr}`);

      const combined = statusResult.stdout + statusResult.stderr;
      assert.ok(
        combined.toLowerCase().includes("local changes") ||
        combined.toLowerCase().includes("changed") ||
        combined.toLowerCase().includes("never synced"),
        `Output should contain "local changes", "changed", or "never synced".\nstdout: ${statusResult.stdout}\nstderr: ${statusResult.stderr}`,
      );
    } finally {
      env.cleanup();
    }
  });
});
