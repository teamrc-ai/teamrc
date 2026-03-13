import { describe, it, before, beforeEach } from "node:test";
import assert from "node:assert/strict";
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

describe("teamrc dashboard", () => {
  it("dashboard outputs URL with invite code", async () => {
    const env = createIsolatedEnv("dashboard-url");
    try {
      const initResult = await runCli(
        ["init", "--name", "dash-test", "--team", "backend", "--platform", "claude-code"],
        env,
      );
      assert.equal(initResult.exitCode, 0, `Init failed.\nstdout: ${initResult.stdout}\nstderr: ${initResult.stderr}`);

      const result = await runCli(["dashboard"], env);
      assert.equal(result.exitCode, 0, `Dashboard failed.\nstdout: ${result.stdout}\nstderr: ${result.stderr}`);

      const combined = result.stdout + result.stderr;
      // Should contain a URL pointing to the relay
      assert.ok(
        combined.includes("http://localhost:4002") || combined.includes("https://"),
        `Dashboard output should contain a URL.\nOutput: ${combined}`,
      );
      // Should contain an invite code
      assert.ok(
        combined.includes("trc_inv_"),
        `Dashboard output should contain an invite code (trc_inv_).\nOutput: ${combined}`,
      );
    } finally {
      env.cleanup();
    }
  });

  it("dashboard with custom TTL", async () => {
    const env = createIsolatedEnv("dashboard-ttl");
    try {
      const initResult = await runCli(
        ["init", "--name", "dash-ttl", "--team", "backend", "--platform", "claude-code"],
        env,
      );
      assert.equal(initResult.exitCode, 0, `Init failed.\nstdout: ${initResult.stdout}\nstderr: ${initResult.stderr}`);

      const result = await runCli(["dashboard", "--ttl", "48"], env);
      assert.equal(result.exitCode, 0, `Dashboard --ttl 48 failed.\nstdout: ${result.stdout}\nstderr: ${result.stderr}`);

      const combined = result.stdout + result.stderr;
      assert.ok(
        combined.includes("48"),
        `Dashboard output should mention TTL "48".\nOutput: ${combined}`,
      );
    } finally {
      env.cleanup();
    }
  });
});
