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
  writeYaml,
  type IsolatedEnv,
} from "./helpers.ts";

before(async () => {
  await waitForServer();
});

beforeEach(async () => {
  await testSetup("clear_rate_limits");
});

describe("teamrc delete", () => {
  it("delete project scope", async () => {
    const env = createIsolatedEnv("delete-project");
    try {
      const initResult = await runCli(
        ["init", "--local", "--name", "del-proj", "--team", "backend", "--platform", "claude-code"],
        env,
      );
      assert.equal(initResult.exitCode, 0, `Init failed.\nstdout: ${initResult.stdout}\nstderr: ${initResult.stderr}`);

      // Verify files exist before delete
      assert.ok(fileExists(env, ".teamrc.yaml"), ".teamrc.yaml should exist before delete");
      const agentFiles = listFiles(env, ".claude/agents");
      const trcFiles = agentFiles.filter((f) => f.startsWith("trc-") && f.endsWith(".md"));
      assert.ok(trcFiles.length > 0, "Should have trc-*.md agent files before delete");

      const result = await runCli(["delete", "--yes", "--scope", "project"], env);
      assert.equal(result.exitCode, 0, `Delete failed.\nstdout: ${result.stdout}\nstderr: ${result.stderr}`);

      // .teamrc.yaml should be gone
      assert.ok(!fileExists(env, ".teamrc.yaml"), ".teamrc.yaml should be gone after delete --scope project");

      // trc-*.md agent files should be gone
      const agentFilesAfter = listFiles(env, ".claude/agents");
      const trcFilesAfter = agentFilesAfter.filter((f) => f.startsWith("trc-") && f.endsWith(".md"));
      assert.equal(trcFilesAfter.length, 0, "All trc-*.md agent files should be gone after delete --scope project");
    } finally {
      env.cleanup();
    }
  });

  it("delete all scope removes everything", async () => {
    const env = createIsolatedEnv("delete-all");
    try {
      // Init a project-scope team
      const initResult = await runCli(
        ["init", "--local", "--name", "del-all", "--team", "backend", "--platform", "claude-code"],
        env,
      );
      assert.equal(initResult.exitCode, 0, `Init failed.\nstdout: ${initResult.stdout}\nstderr: ${initResult.stderr}`);

      // Verify files exist
      assert.ok(fileExists(env, ".teamrc.yaml"), ".teamrc.yaml should exist before delete");
      const configDir = path.join(env.home, ".teamrc");
      assert.ok(fs.existsSync(configDir), "~/.teamrc/ should exist before delete");

      const result = await runCli(["delete", "--yes", "--scope", "all"], env);
      assert.equal(result.exitCode, 0, `Delete failed.\nstdout: ${result.stdout}\nstderr: ${result.stderr}`);

      // Both .teamrc.yaml and ~/.teamrc/ should be gone
      assert.ok(!fileExists(env, ".teamrc.yaml"), ".teamrc.yaml should be gone after delete --scope all");
      assert.ok(!fs.existsSync(configDir), "~/.teamrc/ should be gone after delete --scope all");
    } finally {
      env.cleanup();
    }
  });

  it("delete disconnects from relay", async () => {
    const env = createIsolatedEnv("delete-relay");
    try {
      // Init on relay
      const initResult = await runCli(
        ["init", "--name", "del-relay", "--team", "backend", "--platform", "claude-code"],
        env,
      );
      assert.equal(initResult.exitCode, 0, `Init failed.\nstdout: ${initResult.stdout}\nstderr: ${initResult.stderr}`);

      const teamId = getTeamId(env);
      assert.ok(teamId, "Team ID should exist after init");

      // Save keypair before delete wipes it
      const kp = loadKeypairFromEnv(env);
      assert.ok(kp, "Keypair should exist");

      const result = await runCli(["delete", "--yes", "--scope", "project"], env);
      assert.equal(result.exitCode, 0, `Delete failed.\nstdout: ${result.stdout}\nstderr: ${result.stderr}`);

      // Verify via signed API request that the team is no longer accessible
      const res = await signedGet(`/api/teams/${kp.token}?team_id=${teamId}`, kp);
      assert.ok(
        res.status === 404 || res.status === 401,
        `After delete, team should return 404 or 401, got ${res.status}`,
      );
    } finally {
      env.cleanup();
    }
  });
});
