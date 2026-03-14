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
  readYaml,
  fileExists,
  readFile,
  listFiles,
  getToken,
  getTeamId,
  type IsolatedEnv,
} from "./helpers.ts";

before(async () => {
  await waitForServer();
});

beforeEach(async () => {
  await testSetup("clear_rate_limits");
});

// Daemon command is disabled (coming soon)  --  skip these tests
describe.skip("teamrc daemon", () => {
  it("daemon detects remote change and applies new agent file", { timeout: 45000 }, async () => {
    const env = createIsolatedEnv("daemon-detect");
    try {
      // Init creates the team on relay and pushes it
      const initResult = await runCli(
        ["init", "--name", "daemon-test", "--team", "backend", "--platform", "claude-code"],
        env,
      );
      assert.equal(initResult.exitCode, 0, `Init failed.\nstdout: ${initResult.stdout}\nstderr: ${initResult.stderr}`);

      const token = getToken(env);
      assert.ok(token, "Token should exist after init");
      const teamId = getTeamId(env);
      assert.ok(teamId, "Team ID should exist after init");

      // Read existing YAML to get current members for the update
      const yamlBefore = readYaml(env);
      const memberMatches = [...yamlBefore.matchAll(/- name: (.+)\n\s+role: (.+)/g)];
      const existingMembers = memberMatches.map((m) => ({ name: m[1].trim(), role: m[2].trim() }));

      // Spawn daemon with fast polling
      const daemon = spawnCli(["daemon", "--poll-interval", "5000"], env);

      // Wait for daemon to indicate it's running
      await daemon.waitForOutput(/Daemon started|Watching|Poll interval/i, 15_000);

      // Update team on server to add a new member
      await testSetup("update_team", {
        token,
        team_id: teamId,
        team: {
          name: "daemon-test",
          members: [
            ...existingMembers,
            { name: "daemon-added", role: "QA" },
          ],
        },
      });

      // Wait for two poll cycles to detect and apply the change
      await new Promise((r) => setTimeout(r, 15000));

      // Check daemon process is still alive
      const daemonAlive = daemon.process.exitCode === null;

      // Verify the new agent file was created
      assert.ok(
        fileExists(env, ".claude/agents/trc-daemon-added.md"),
        `Agent file .claude/agents/trc-daemon-added.md should exist after daemon poll.\n` +
        `Current files: ${listFiles(env, ".claude/agents").join(", ")}\n` +
        `Daemon alive: ${daemonAlive}\n` +
        `Daemon stdout: ${daemon.stdout.substring(0, 500)}\n` +
        `Daemon stderr: ${(daemon as any).process.stderr ? "check below" : "none"}`,
      );

      // Clean shutdown
      daemon.kill("SIGINT");
      try { await daemon.waitForExit(10_000); } catch { /* best effort */ }
    } finally {
      env.cleanup();
    }
  });

  it("daemon exits cleanly on SIGTERM", { timeout: 20000 }, async () => {
    const env = createIsolatedEnv("daemon-exit");
    try {
      // Init creates the team on relay
      const initResult = await runCli(
        ["init", "--name", "daemon-exit", "--team", "backend", "--platform", "claude-code"],
        env,
      );
      assert.equal(initResult.exitCode, 0, `Init failed.\nstdout: ${initResult.stdout}\nstderr: ${initResult.stderr}`);

      // Spawn daemon
      const daemon = spawnCli(["daemon", "--poll-interval", "5000"], env);

      // Wait for daemon to indicate it's running
      await daemon.waitForOutput(/Daemon started|Watching|Poll interval/i, 15_000);

      // Kill with SIGINT (daemon handles SIGINT for clean shutdown)
      daemon.kill("SIGINT");

      // Process should exit within 10 seconds
      const result = await daemon.waitForExit(10_000);

      // Verify clean exit (0 = clean shutdown)
      assert.equal(result.exitCode, 0, `Daemon should exit with code 0, got ${result.exitCode}.\nstdout: ${result.stdout}\nstderr: ${result.stderr}`);
    } finally {
      env.cleanup();
    }
  });

  it("daemon does not rewrite files when no remote change", { timeout: 30000 }, async () => {
    const env = createIsolatedEnv("daemon-noop");
    try {
      // Init creates the team on relay
      const initResult = await runCli(
        ["init", "--name", "daemon-noop", "--team", "backend", "--platform", "claude-code"],
        env,
      );
      assert.equal(initResult.exitCode, 0, `Init failed.\nstdout: ${initResult.stdout}\nstderr: ${initResult.stderr}`);

      // Read an agent file and its contents before daemon runs
      const agentFiles = listFiles(env, ".claude/agents").filter((f) => f.startsWith("trc-"));
      assert.ok(agentFiles.length > 0, "Should have at least one agent file after init");

      const sampleFile = agentFiles[0];
      const samplePath = path.join(env.projectDir, ".claude/agents", sampleFile);
      const contentBefore = fs.readFileSync(samplePath, "utf-8");

      // Spawn daemon
      const daemon = spawnCli(["daemon", "--poll-interval", "5000"], env);

      // Wait for daemon to indicate it's running
      await daemon.waitForOutput(/Daemon started|Watching|Poll interval/i, 15_000);

      // Wait for at least one poll cycle with no changes
      await new Promise((r) => setTimeout(r, 8000));

      // Kill daemon
      daemon.kill("SIGINT");
      try { await daemon.waitForExit(10_000); } catch { /* best effort */ }

      // Verify agent file was NOT modified (same content)
      const contentAfter = fs.readFileSync(samplePath, "utf-8");
      assert.equal(
        contentAfter,
        contentBefore,
        `Agent file content should not change when no remote update.`,
      );
    } finally {
      env.cleanup();
    }
  });
});
