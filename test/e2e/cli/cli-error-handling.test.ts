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

describe("teamrc error handling", () => {
  it("push without init fails", async () => {
    const env = createIsolatedEnv("err-push");
    try {
      const result = await runCli(["push"], env);
      assert.notEqual(result.exitCode, 0, `Push without init should fail.\nstdout: ${result.stdout}\nstderr: ${result.stderr}`);
    } finally {
      env.cleanup();
    }
  });

  it("pull without init fails", async () => {
    const env = createIsolatedEnv("err-pull");
    try {
      const result = await runCli(["pull"], env);
      assert.notEqual(result.exitCode, 0, `Pull without init should fail.\nstdout: ${result.stdout}\nstderr: ${result.stderr}`);
    } finally {
      env.cleanup();
    }
  });

  it("sync without init fails", async () => {
    const env = createIsolatedEnv("err-sync");
    try {
      const result = await runCli(["sync"], env);
      assert.notEqual(result.exitCode, 0, `Sync without init should fail.\nstdout: ${result.stdout}\nstderr: ${result.stderr}`);
    } finally {
      env.cleanup();
    }
  });

  it("diff without relay fails", async () => {
    const env = createIsolatedEnv("err-diff");
    try {
      // Init local-only  --  diff requires relay context
      const initResult = await runCli(
        ["init", "--local", "--name", "diff-err", "--team", "backend", "--platform", "claude-code"],
        env,
      );
      assert.equal(initResult.exitCode, 0, `Init failed.\nstdout: ${initResult.stdout}\nstderr: ${initResult.stderr}`);

      const result = await runCli(["diff"], env);
      assert.notEqual(result.exitCode, 0, `Diff on local-only team should fail.\nstdout: ${result.stdout}\nstderr: ${result.stderr}`);

      const combined = result.stdout + result.stderr;
      assert.ok(
        combined.includes("local-only") || combined.includes("relay") || combined.includes("push"),
        `Diff error should mention "local-only", "relay", or "push".\nOutput: ${combined}`,
      );
    } finally {
      env.cleanup();
    }
  });

  it("invite without relay fails", async () => {
    const env = createIsolatedEnv("err-invite");
    try {
      // Init local-only  --  invite requires relay context
      const initResult = await runCli(
        ["init", "--local", "--name", "invite-err", "--team", "backend", "--platform", "claude-code"],
        env,
      );
      assert.equal(initResult.exitCode, 0, `Init failed.\nstdout: ${initResult.stdout}\nstderr: ${initResult.stderr}`);

      const result = await runCli(["invite"], env);
      assert.notEqual(result.exitCode, 0, `Invite on local-only team should fail.\nstdout: ${result.stdout}\nstderr: ${result.stderr}`);
    } finally {
      env.cleanup();
    }
  });

  it("init with nonexistent template fails", async () => {
    const env = createIsolatedEnv("err-template");
    try {
      const result = await runCli(
        ["init", "--name", "test", "--team", "nonexistent-xyz-template", "--local", "--platform", "claude-code"],
        env,
      );
      assert.notEqual(result.exitCode, 0, `Init with nonexistent template should fail.\nstdout: ${result.stdout}\nstderr: ${result.stderr}`);
    } finally {
      env.cleanup();
    }
  });

  it("add nonexistent agent fails", async () => {
    const env = createIsolatedEnv("err-add-agent");
    try {
      // Init on relay (add-member requires relay context)
      const initResult = await runCli(
        ["init", "--name", "add-err", "--team", "backend", "--platform", "claude-code"],
        env,
      );
      assert.equal(initResult.exitCode, 0, `Init failed.\nstdout: ${initResult.stdout}\nstderr: ${initResult.stderr}`);

      const result = await runCli(["add-member", "nonexistent-xyz-999"], env);
      assert.notEqual(
        result.exitCode,
        0,
        `add-member with nonexistent agent should fail.\nstdout: ${result.stdout}\nstderr: ${result.stderr}`,
      );
    } finally {
      env.cleanup();
    }
  });
});
