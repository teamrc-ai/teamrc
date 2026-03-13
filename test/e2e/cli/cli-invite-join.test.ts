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
  listFiles,
  getToken,
  getTeamId,
  loadKeypairFromEnv,
  signedGet,
  type IsolatedEnv,
} from "./helpers.ts";

before(async () => {
  await waitForServer();
});

beforeEach(async () => {
  await testSetup("clear_rate_limits");
});

// ─── Helpers ───

const INVITE_RE = /trc_inv_[A-Za-z0-9_-]+/;

interface InitAndInviteResult {
  env: IsolatedEnv;
  inviteCode: string;
  teamId: string;
}

/**
 * Create a relay-connected team and generate an invite code.
 * Returns the isolated env, the invite code, and the teamId.
 */
async function initAndInvite(name: string): Promise<InitAndInviteResult> {
  const env = createIsolatedEnv(name);

  const initResult = await runCli(
    ["init", "--name", name, "--team", "backend", "--platform", "claude-code"],
    env,
  );
  assert.equal(initResult.exitCode, 0, `Init should succeed. stderr: ${initResult.stderr}`);

  const teamId = getTeamId(env);
  assert.ok(teamId, "teamId should exist after init");

  const inviteResult = await runCli(["invite"], env);
  assert.equal(inviteResult.exitCode, 0, `Invite should succeed. stderr: ${inviteResult.stderr}`);

  const match = inviteResult.stdout.match(INVITE_RE);
  assert.ok(match, `Invite output should contain invite code. stdout: ${inviteResult.stdout}`);
  const inviteCode = match[0];

  return { env, inviteCode, teamId };
}

// ─── Tests ───

describe("teamrc invite & join", () => {
  it("generate invite", async () => {
    const envA = createIsolatedEnv("gen-invite");
    try {
      const initResult = await runCli(
        ["init", "--name", "inv-team", "--team", "backend", "--platform", "claude-code"],
        envA,
      );
      assert.equal(initResult.exitCode, 0, `Init should succeed. stderr: ${initResult.stderr}`);

      const inviteResult = await runCli(["invite"], envA);
      assert.equal(inviteResult.exitCode, 0, `Invite should succeed. stderr: ${inviteResult.stderr}`);

      // stdout contains trc_inv_ invite code
      assert.match(
        inviteResult.stdout,
        INVITE_RE,
        `Invite stdout should contain an invite code. stdout: ${inviteResult.stdout}`,
      );

      // Extract the invite code
      const match = inviteResult.stdout.match(INVITE_RE);
      assert.ok(match, "Should be able to extract invite code from stdout");
      assert.ok(match[0].startsWith("trc_inv_"), "Invite code should start with trc_inv_");
    } finally {
      envA.cleanup();
    }
  });

  it("join with invite code", async () => {
    const { env: envA, inviteCode, teamId: teamIdA } = await initAndInvite("join-a");
    const envB = createIsolatedEnv("join-b");
    try {
      const joinResult = await runCli(
        ["join", inviteCode, "--platform", "claude-code", "--relay", "http://localhost:4002"],
        envB,
      );
      assert.equal(
        joinResult.exitCode, 0,
        `Join should succeed. stdout: ${joinResult.stdout}\nstderr: ${joinResult.stderr}`,
      );

      // B's .teamrc.yaml exists
      assert.ok(fileExists(envB, ".teamrc.yaml"), "B should have .teamrc.yaml after join");

      // B's teamId matches A's teamId
      const teamIdB = getTeamId(envB);
      assert.equal(teamIdB, teamIdA, "B's teamId should match A's teamId");

      // B has .claude/agents/trc-*.md files
      const agentFiles = listFiles(envB, ".claude/agents").filter((f) => f.startsWith("trc-") && f.endsWith(".md"));
      assert.ok(agentFiles.length > 0, `B should have trc-*.md agent files. Found: ${agentFiles.join(", ")}`);
    } finally {
      envA.cleanup();
      envB.cleanup();
    }
  });

  it("custom TTL invite", async () => {
    const envA = createIsolatedEnv("ttl-invite");
    try {
      const initResult = await runCli(
        ["init", "--name", "ttl-team", "--team", "backend", "--platform", "claude-code"],
        envA,
      );
      assert.equal(initResult.exitCode, 0, `Init should succeed. stderr: ${initResult.stderr}`);

      const inviteResult = await runCli(["invite", "--ttl", "48"], envA);
      assert.equal(inviteResult.exitCode, 0, `Invite should succeed. stderr: ${inviteResult.stderr}`);

      // stdout mentions "48" hours
      assert.ok(
        inviteResult.stdout.includes("48"),
        `Invite stdout should mention 48 hours. stdout: ${inviteResult.stdout}`,
      );
    } finally {
      envA.cleanup();
    }
  });

  it("join invalid invite", async () => {
    const env = createIsolatedEnv("join-invalid");
    try {
      const joinResult = await runCli(
        ["join", "trc_inv_AAAAAAAAAAAAAAAAAAAAAA", "--relay", "http://localhost:4002", "--platform", "claude-code"],
        env,
      );

      assert.equal(
        joinResult.exitCode, 1,
        `Join with invalid invite should fail with exit code 1. stdout: ${joinResult.stdout}\nstderr: ${joinResult.stderr}`,
      );
    } finally {
      env.cleanup();
    }
  });

  it("joined member can push", async () => {
    const { env: envA, inviteCode, teamId } = await initAndInvite("push-a");
    const envB = createIsolatedEnv("push-b");
    try {
      // B joins the team
      const joinResult = await runCli(
        ["join", inviteCode, "--platform", "claude-code", "--relay", "http://localhost:4002"],
        envB,
      );
      assert.equal(joinResult.exitCode, 0, `Join should succeed. stderr: ${joinResult.stderr}`);

      // B edits YAML to add a new member
      const yaml = readYaml(envB);
      const newMember = "  - name: b-added-agent\n    role: B's custom agent\n";
      const updatedYaml = yaml.replace(/^(members:\n)/m, `$1${newMember}`);
      const yamlPath = envB.projectDir + "/.teamrc.yaml";
      const fs = await import("node:fs");
      fs.writeFileSync(yamlPath, updatedYaml);

      // B pushes
      const pushResult = await runCli(["push"], envB);
      assert.equal(
        pushResult.exitCode, 0,
        `Push should succeed. stdout: ${pushResult.stdout}\nstderr: ${pushResult.stderr}`,
      );

      // Verify via signedGet with A's keypair that the remote team has "b-added-agent"
      const kpA = loadKeypairFromEnv(envA);
      assert.ok(kpA, "A's keypair should exist");

      const res = await signedGet(`/api/teams/${kpA.token}?team_id=${teamId}`, kpA);
      assert.equal(res.status, 200, "API GET should succeed");
      const data = (await res.json()) as { team: { members: Array<{ name: string }> } };
      const memberNames = data.team.members.map((m) => m.name);
      assert.ok(
        memberNames.includes("b-added-agent"),
        `Remote team should contain "b-added-agent". Got: ${memberNames.join(", ")}`,
      );
    } finally {
      envA.cleanup();
      envB.cleanup();
    }
  });

  it("joined member can pull", async () => {
    const { env: envA, inviteCode, teamId } = await initAndInvite("pull-a");
    const envB = createIsolatedEnv("pull-b");
    try {
      // B joins the team
      const joinResult = await runCli(
        ["join", inviteCode, "--platform", "claude-code", "--relay", "http://localhost:4002"],
        envB,
      );
      assert.equal(joinResult.exitCode, 0, `Join should succeed. stderr: ${joinResult.stderr}`);

      // A edits YAML to add a new member
      const yaml = readYaml(envA);
      const newMember = "  - name: a-added-agent\n    role: A's custom agent\n";
      const updatedYaml = yaml.replace(/^(members:\n)/m, `$1${newMember}`);
      const yamlPath = envA.projectDir + "/.teamrc.yaml";
      const fs = await import("node:fs");
      fs.writeFileSync(yamlPath, updatedYaml);

      // A pushes the edit
      const pushResult = await runCli(["push"], envA);
      assert.equal(
        pushResult.exitCode, 0,
        `A's push should succeed. stdout: ${pushResult.stdout}\nstderr: ${pushResult.stderr}`,
      );

      // B pulls
      const pullResult = await runCli(["pull", "--platform", "claude-code"], envB);
      assert.equal(
        pullResult.exitCode, 0,
        `B's pull should succeed. stdout: ${pullResult.stdout}\nstderr: ${pullResult.stderr}`,
      );

      // B's YAML contains "a-added-agent"
      const yamlB = readYaml(envB);
      assert.ok(
        yamlB.includes("a-added-agent"),
        `B's YAML should contain "a-added-agent" after pull. YAML:\n${yamlB}`,
      );
    } finally {
      envA.cleanup();
      envB.cleanup();
    }
  });
});
