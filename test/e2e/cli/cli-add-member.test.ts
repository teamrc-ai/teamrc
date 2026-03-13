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

describe("teamrc add-member", () => {
  it("add member by catalog name", async () => {
    const env = createIsolatedEnv("add-member-catalog");
    try {
      // Init a relay-connected team (add-member uses requireRelayContext)
      const initResult = await runCli(
        ["init", "--name", "add-mem", "--team", "backend", "--platform", "claude-code"],
        env,
      );
      assert.equal(initResult.exitCode, 0, `Init failed.\nstdout: ${initResult.stdout}\nstderr: ${initResult.stderr}`);

      const result = await runCli(["add-member", "architect"], env);
      assert.equal(result.exitCode, 0, `add-member failed.\nstdout: ${result.stdout}\nstderr: ${result.stderr}`);

      // YAML should contain the "architect" member
      const yaml = readYaml(env);
      assert.ok(
        yaml.includes("architect"),
        `YAML should contain "architect" member.\nYAML:\n${yaml}`,
      );

      // Platform agent file should exist
      assert.ok(
        fileExists(env, ".claude/agents/trc-architect.md"),
        "Agent file .claude/agents/trc-architect.md should exist after add-member",
      );
    } finally {
      env.cleanup();
    }
  });

  it("add member pushes to relay", async () => {
    const env = createIsolatedEnv("add-member-relay");
    try {
      const initResult = await runCli(
        ["init", "--name", "add-relay", "--team", "backend", "--platform", "claude-code"],
        env,
      );
      assert.equal(initResult.exitCode, 0, `Init failed.\nstdout: ${initResult.stdout}\nstderr: ${initResult.stderr}`);

      const teamId = getTeamId(env);
      assert.ok(teamId, "Team ID should exist after init");

      const result = await runCli(["add-member", "architect"], env);
      assert.equal(result.exitCode, 0, `add-member failed.\nstdout: ${result.stdout}\nstderr: ${result.stderr}`);

      // Verify via signed API request that the relay has "architect"
      const kp = loadKeypairFromEnv(env);
      assert.ok(kp, "Keypair should exist");

      const res = await signedGet(`/api/teams/${kp.token}?team_id=${teamId}`, kp);
      assert.equal(res.status, 200, "GET team should return 200");
      const data = (await res.json()) as { team: { members: Array<{ name: string }> } };
      const memberNames = data.team.members.map((m) => m.name);
      assert.ok(
        memberNames.includes("architect"),
        `Remote team should contain "architect".\nRemote members: ${memberNames.join(", ")}`,
      );
    } finally {
      env.cleanup();
    }
  });
});

describe("teamrc list-agents", () => {
  it("list-agents JSON output", async () => {
    const env = createIsolatedEnv("list-agents-json");
    try {
      const result = await runCli(["list-agents", "--json"], env);
      assert.equal(result.exitCode, 0, `list-agents --json failed.\nstdout: ${result.stdout}\nstderr: ${result.stderr}`);

      const parsed = JSON.parse(result.stdout);
      assert.ok(Array.isArray(parsed), "Output should be a JSON array");
      assert.ok(parsed.length > 0, "Should have at least one category");

      // Each category should have agents array
      for (const category of parsed) {
        assert.ok(category.category, "Each category should have a 'category' field");
        assert.ok(category.label, "Each category should have a 'label' field");
        assert.ok(Array.isArray(category.agents), "Each category should have an 'agents' array");
      }
    } finally {
      env.cleanup();
    }
  });
});

describe("teamrc list-templates", () => {
  it("list-templates JSON output", async () => {
    const env = createIsolatedEnv("list-templates-json");
    try {
      const result = await runCli(["list-templates", "--json"], env);
      assert.equal(result.exitCode, 0, `list-templates --json failed.\nstdout: ${result.stdout}\nstderr: ${result.stderr}`);

      const parsed = JSON.parse(result.stdout);
      assert.ok(Array.isArray(parsed), "Output should be a JSON array");
      assert.ok(parsed.length > 0, "Should have at least one template");

      // Each template should have id and label
      for (const tmpl of parsed) {
        assert.ok(tmpl.id, `Each template should have an 'id' field. Got: ${JSON.stringify(tmpl)}`);
        assert.ok(tmpl.label, `Each template should have a 'label' field. Got: ${JSON.stringify(tmpl)}`);
      }
    } finally {
      env.cleanup();
    }
  });
});
