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

describe("teamrc whoami", () => {
  it("whoami shows token", async () => {
    const env = createIsolatedEnv("whoami-token");
    try {
      const initResult = await runCli(
        ["init", "--local", "--name", "whoami-test", "--team", "backend", "--platform", "claude-code"],
        env,
      );
      assert.equal(initResult.exitCode, 0, `Init failed.\nstdout: ${initResult.stdout}\nstderr: ${initResult.stderr}`);

      const result = await runCli(["whoami"], env);
      assert.equal(result.exitCode, 0, `Whoami failed.\nstdout: ${result.stdout}\nstderr: ${result.stderr}`);

      const combined = result.stdout + result.stderr;
      assert.ok(combined.includes("trc_ak_"), `Whoami output should contain token prefix trc_ak_.\nOutput: ${combined}`);
    } finally {
      env.cleanup();
    }
  });

  it("whoami JSON output", async () => {
    const env = createIsolatedEnv("whoami-json");
    try {
      const initResult = await runCli(
        ["init", "--local", "--name", "whoami-json", "--team", "backend", "--platform", "claude-code"],
        env,
      );
      assert.equal(initResult.exitCode, 0, `Init failed.\nstdout: ${initResult.stdout}\nstderr: ${initResult.stderr}`);

      const result = await runCli(["whoami", "--json"], env);
      assert.equal(result.exitCode, 0, `Whoami --json failed.\nstdout: ${result.stdout}\nstderr: ${result.stderr}`);

      const parsed = JSON.parse(result.stdout);
      assert.ok(parsed.token, "JSON output should have a 'token' field");
      assert.ok(
        parsed.token.startsWith("trc_ak_"),
        `Token should start with trc_ak_, got: ${parsed.token}`,
      );
    } finally {
      env.cleanup();
    }
  });

  it("whoami shows email after login", async () => {
    const env = createIsolatedEnv("whoami-email");
    try {
      const initResult = await runCli(
        ["init", "--local", "--name", "whoami-email", "--team", "backend", "--platform", "claude-code"],
        env,
      );
      assert.equal(initResult.exitCode, 0, `Init failed.\nstdout: ${initResult.stdout}\nstderr: ${initResult.stderr}`);

      // Simulate login by writing account email into config.json
      const configPath = path.join(env.home, ".teamrc", "config.json");
      const config = JSON.parse(fs.readFileSync(configPath, "utf-8"));
      config.account = { email: "test@e2e.com" };
      fs.writeFileSync(configPath, JSON.stringify(config, null, 2));

      const result = await runCli(["whoami"], env);
      assert.equal(result.exitCode, 0, `Whoami failed.\nstdout: ${result.stdout}\nstderr: ${result.stderr}`);

      const combined = result.stdout + result.stderr;
      assert.ok(
        combined.includes("test@e2e.com"),
        `Whoami output should contain email "test@e2e.com".\nOutput: ${combined}`,
      );
    } finally {
      env.cleanup();
    }
  });
});

describe("teamrc doctor", () => {
  it("doctor passes on relay-connected team", async () => {
    const env = createIsolatedEnv("doctor-pass");
    try {
      const initResult = await runCli(
        ["init", "--name", "doctor-test", "--team", "backend", "--platform", "claude-code"],
        env,
      );
      assert.equal(initResult.exitCode, 0, `Init failed.\nstdout: ${initResult.stdout}\nstderr: ${initResult.stderr}`);

      const result = await runCli(["doctor"], env);
      assert.equal(result.exitCode, 0, `Doctor failed.\nstdout: ${result.stdout}\nstderr: ${result.stderr}`);

      const combined = result.stdout + result.stderr;
      assert.ok(
        combined.includes("passed"),
        `Doctor output should mention "passed".\nOutput: ${combined}`,
      );
    } finally {
      env.cleanup();
    }
  });

  it("doctor warns on missing YAML", async () => {
    const env = createIsolatedEnv("doctor-warn");
    try {
      // Init to set up keypair and config, then delete the YAML
      const initResult = await runCli(
        ["init", "--local", "--name", "doctor-warn", "--team", "backend", "--platform", "claude-code"],
        env,
      );
      assert.equal(initResult.exitCode, 0, `Init failed.\nstdout: ${initResult.stdout}\nstderr: ${initResult.stderr}`);

      // Delete .teamrc.yaml to trigger the warning
      const yamlPath = path.join(env.projectDir, ".teamrc.yaml");
      fs.unlinkSync(yamlPath);
      assert.ok(!fs.existsSync(yamlPath), ".teamrc.yaml should be deleted");

      const result = await runCli(["doctor"], env);

      const combined = result.stdout + result.stderr;
      assert.ok(
        combined.includes("No .teamrc.yaml") || combined.includes("warn"),
        `Doctor output should warn about missing YAML.\nOutput: ${combined}`,
      );
    } finally {
      env.cleanup();
    }
  });
});
