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
  listFiles,
  readConfig,
  readKey,
  getToken,
  getTeamId,
  writeFile,
  type IsolatedEnv,
} from "./helpers.ts";

before(async () => {
  await waitForServer();
});

beforeEach(async () => {
  await testSetup("clear_rate_limits");
});

describe("teamrc init", () => {
  it("init with template, relay-connected", async () => {
    const env = createIsolatedEnv("init-relay");
    try {
      const result = await runCli(
        ["init", "--name", "test-init", "--team", "fullstack", "--platform", "claude-code"],
        env,
      );

      assert.equal(result.exitCode, 0, `Expected exit 0, got ${result.exitCode}.\nstdout: ${result.stdout}\nstderr: ${result.stderr}`);

      // .teamrc.yaml exists with expected fields
      assert.ok(fileExists(env, ".teamrc.yaml"), ".teamrc.yaml should exist");
      const yaml = readYaml(env);
      assert.ok(yaml.includes("name: test-init"), "YAML should contain name: test-init");
      assert.ok(yaml.includes("teamId:"), "YAML should contain teamId");
      assert.ok(yaml.includes("relay:"), "YAML should contain relay");
      assert.match(yaml, /members:/, "YAML should contain members");

      // Agent files created in .claude/agents/
      const agentFiles = listFiles(env, ".claude/agents");
      assert.ok(agentFiles.length > 0, "Should have agent files in .claude/agents/");
      const trcFiles = agentFiles.filter((f) => f.startsWith("trc-") && f.endsWith(".md"));
      assert.ok(trcFiles.length > 0, "Should have trc-*.md agent files");

      // .gitignore contains .teamrc/
      assert.ok(fileExists(env, ".gitignore"), ".gitignore should exist");
      const gitignore = readFile(env, ".gitignore");
      assert.ok(gitignore.includes(".teamrc/"), ".gitignore should contain .teamrc/");

      // stdout contains team created message
      const combined = result.stdout + result.stderr;
      assert.match(combined, /[Tt]eam created/i, "Output should mention team created");

      // stdout contains invite code
      assert.match(combined, /trc_inv_/, "Output should contain an invite code (trc_inv_)");
    } finally {
      env.cleanup();
    }
  });

  it("init local-only", async () => {
    const env = createIsolatedEnv("init-local");
    try {
      const result = await runCli(
        ["init", "--name", "local-team", "--team", "backend", "--local", "--platform", "claude-code"],
        env,
      );

      assert.equal(result.exitCode, 0, `Expected exit 0, got ${result.exitCode}.\nstdout: ${result.stdout}\nstderr: ${result.stderr}`);

      // .teamrc.yaml exists with name but NO teamId
      assert.ok(fileExists(env, ".teamrc.yaml"), ".teamrc.yaml should exist");
      const yaml = readYaml(env);
      assert.ok(yaml.includes("name: local-team"), "YAML should contain name: local-team");
      assert.ok(!yaml.includes("teamId:"), "YAML should NOT contain teamId for local-only init");

      // Agent files created
      const agentFiles = listFiles(env, ".claude/agents");
      assert.ok(agentFiles.length > 0, "Should have agent files in .claude/agents/");

      // stdout does NOT contain invite code
      const combined = result.stdout + result.stderr;
      assert.ok(!combined.includes("trc_inv_"), "Local-only init should not produce an invite code");
    } finally {
      env.cleanup();
    }
  });

  it("init refuses duplicate", async () => {
    const env = createIsolatedEnv("init-dup");
    try {
      // First init
      const first = await runCli(
        ["init", "--name", "dup-team", "--team", "backend", "--local", "--platform", "claude-code"],
        env,
      );
      assert.equal(first.exitCode, 0, `First init should succeed. stderr: ${first.stderr}`);

      // Second init in same directory
      const second = await runCli(
        ["init", "--name", "dup-team-2", "--team", "backend", "--local", "--platform", "claude-code"],
        env,
      );
      assert.equal(second.exitCode, 1, "Second init should fail with exit code 1");

      const combined = second.stdout + second.stderr;
      assert.match(combined, /[Aa]lready initialized/i, "Output should mention already initialized");
    } finally {
      env.cleanup();
    }
  });

  it("init with --no-knowledge", async () => {
    const env = createIsolatedEnv("init-no-knowledge");
    try {
      const result = await runCli(
        ["init", "--name", "no-know", "--team", "backend", "--local", "--platform", "claude-code", "--no-knowledge"],
        env,
      );

      assert.equal(result.exitCode, 0, `Expected exit 0, got ${result.exitCode}.\nstdout: ${result.stdout}\nstderr: ${result.stderr}`);

      // No knowledge file in .teamrc/ directory
      const stateFiles = listFiles(env, ".teamrc");
      const knowledgeFiles = stateFiles.filter((f) => f.startsWith("knowledge-") && f.endsWith(".md"));
      assert.equal(knowledgeFiles.length, 0, "Should have no knowledge-*.md files when --no-knowledge is used");
    } finally {
      env.cleanup();
    }
  });

  it("init creates state dir", async () => {
    const env = createIsolatedEnv("init-state-dir");
    try {
      const result = await runCli(
        ["init", "--name", "state-test", "--team", "backend", "--platform", "claude-code"],
        env,
      );

      assert.equal(result.exitCode, 0, `Expected exit 0, got ${result.exitCode}.\nstdout: ${result.stdout}\nstderr: ${result.stderr}`);

      // .teamrc/ directory exists in project dir (not HOME)
      const stateDir = path.join(env.projectDir, ".teamrc");
      assert.ok(fs.existsSync(stateDir), ".teamrc/ state directory should exist in the project dir");
      assert.ok(fs.statSync(stateDir).isDirectory(), ".teamrc/ should be a directory");
    } finally {
      env.cleanup();
    }
  });

  it("init with logged-in machine → auto-ownership", async () => {
    const env = createIsolatedEnv("init-auto-own");
    try {
      // Step 1: Run a local init to generate the keypair
      const setupResult = await runCli(
        ["init", "--local", "--name", "dummy", "--team", "backend", "--platform", "claude-code"],
        env,
      );
      assert.equal(setupResult.exitCode, 0, `Setup init should succeed. stderr: ${setupResult.stderr}`);

      // Step 2: Read the token from the generated keypair
      const token = getToken(env);
      assert.ok(token, "Token should exist after init");

      // Step 3: Create a user and link the token (simulates login)
      const { user_id } = (await testSetup("create_user")) as { user_id: string };
      await testSetup("link_token", { user_id, token });

      // Step 4: Create a fresh project dir for the second init
      const newProjectDir = path.join(path.dirname(env.projectDir), "project2");
      fs.mkdirSync(newProjectDir, { recursive: true });
      fs.writeFileSync(path.join(newProjectDir, ".gitignore"), "node_modules/\n");

      // Step 5: Run relay-connected init (uses existing keypair from HOME)
      const result = await runCli(
        ["init", "--name", "auto-own", "--team", "backend", "--platform", "claude-code"],
        env,
        { cwd: newProjectDir },
      );

      assert.equal(result.exitCode, 0, `Relay init should succeed. stderr: ${result.stderr}`);

      // Step 6: Verify auto-ownership message
      const combined = result.stdout + result.stderr;
      assert.match(combined, /[Yy]ou own this team/, "Output should confirm auto-ownership");
    } finally {
      env.cleanup();
    }
  });

  it("init without login → shows claim secret", async () => {
    const env = createIsolatedEnv("init-claim-secret");
    try {
      // Fresh env, no login  --  run relay-connected init
      const result = await runCli(
        ["init", "--name", "no-login", "--team", "backend", "--platform", "claude-code"],
        env,
      );

      assert.equal(result.exitCode, 0, `Expected exit 0, got ${result.exitCode}.\nstdout: ${result.stdout}\nstderr: ${result.stderr}`);

      // Verify claim secret is shown
      const combined = result.stdout + result.stderr;
      assert.match(combined, /trc_ocs_/, "Output should contain a claim secret (trc_ocs_)");
    } finally {
      env.cleanup();
    }
  });
});
