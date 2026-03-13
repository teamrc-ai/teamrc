/**
 * CLI E2E: Verify that linked machines show up correctly in the system.
 *
 * When a user logs in and creates/joins teams, their machine should be
 * visible in the dashboard (via get_user_machines test helper).
 */

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
  getToken,
  getTeamId,
  readConfig,
  type IsolatedEnv,
} from "./helpers.ts";

before(async () => {
  await waitForServer();
});

/**
 * Simulate login by:
 * 1. Running init --local to generate keypair
 * 2. Creating a user and linking the token
 * 3. Writing config with account info
 */
async function setupLoggedInMachine(
  env: IsolatedEnv,
  machineName: string = "e2e-machine",
): Promise<{ userId: string; email: string; token: string }> {
  // Init local to generate keypair
  await runCli(
    ["init", "--name", "temp-setup", "--team", "backend", "--local", "--platform", "claude-code"],
    env,
  );

  const token = getToken(env)!;
  assert.ok(token, "token should exist after init");

  // Create user and link token
  const { user_id, email } = (await testSetup("create_user")) as {
    user_id: string;
    email: string;
  };
  await testSetup("link_token", { user_id, token });

  // Write config with account info (simulates successful login)
  const configPath = path.join(env.home, ".teamrc", "config.json");
  const config = JSON.parse(fs.readFileSync(configPath, "utf-8"));
  config.account = { email };
  config.machineName = machineName;
  fs.writeFileSync(configPath, JSON.stringify(config, null, 2));

  // Clean up the temp team so we can init a real one
  fs.unlinkSync(path.join(env.projectDir, ".teamrc.yaml"));

  return { userId: user_id, email, token };
}

describe("Linked machines", () => {
  beforeEach(async () => {
    await testSetup("clear_rate_limits");
  });

  it("machine appears in user's team list after init", { timeout: 30_000 }, async () => {
    const env = createIsolatedEnv("machines-init");
    try {
      const { userId, token } = await setupLoggedInMachine(env, "init-machine");

      // Init a relay-connected team (auto-owns because logged in)
      const initRes = await runCli(
        ["init", "--name", "machine-visible", "--team", "backend", "--platform", "claude-code"],
        env,
      );
      assert.equal(initRes.exitCode, 0, `init failed: ${initRes.stdout}\n${initRes.stderr}`);

      const teamId = getTeamId(env);
      assert.ok(teamId, "should have teamId after relay init");

      // Query machines via test helper
      const machineData = (await testSetup("get_user_machines", { user_id: userId })) as {
        teams: Array<{
          team_id: string;
          team_name: string;
          machines: Array<{ token: string; machine_name: string }>;
          participants: string[];
        }>;
      };

      // Find our team in the results
      const teamEntry = machineData.teams.find((t) => t.team_id === teamId);
      assert.ok(teamEntry, `team ${teamId} should appear in user's machines`);
      assert.equal(teamEntry.team_name, "machine-visible");

      // Machine should be listed
      assert.ok(teamEntry.machines.length >= 1, "should have at least 1 machine");
      const machine = teamEntry.machines.find((m) => m.token === token);
      assert.ok(machine, "machine token should appear in team's machines list");
    } finally {
      env.cleanup();
    }
  });

  it("joined machine appears in team participants", { timeout: 30_000 }, async () => {
    // Machine A creates team
    const envA = createIsolatedEnv("machines-join-a");
    const envB = createIsolatedEnv("machines-join-b");
    try {
      const ownerInfo = await setupLoggedInMachine(envA, "owner-machine");

      const initRes = await runCli(
        ["init", "--name", "join-machines", "--team", "backend", "--platform", "claude-code"],
        envA,
      );
      assert.equal(initRes.exitCode, 0);

      // Create invite
      const inviteRes = await runCli(["invite"], envA);
      assert.equal(inviteRes.exitCode, 0);
      const inviteMatch = inviteRes.stdout.match(/trc_inv_[A-Za-z0-9_-]+/);
      assert.ok(inviteMatch, "should have invite code");
      const inviteCode = inviteMatch[0];

      // Machine B: set up as different logged-in user
      const joinerInfo = await setupLoggedInMachine(envB, "joiner-machine");

      // B joins
      const joinRes = await runCli(
        ["join", inviteCode, "--platform", "claude-code", "--relay", "http://localhost:4002"],
        envB,
      );
      assert.equal(joinRes.exitCode, 0, `join failed: ${joinRes.stdout}\n${joinRes.stderr}`);

      const teamId = getTeamId(envA);

      // Check owner's view: should see both machines
      const ownerMachines = (await testSetup("get_user_machines", {
        user_id: ownerInfo.userId,
      })) as { teams: Array<{ team_id: string; machines: Array<{ token: string }>; participants: string[] }> };

      const ownerTeam = ownerMachines.teams.find((t) => t.team_id === teamId);
      assert.ok(ownerTeam, "owner should see the team");

      // Participants should include both users' emails
      assert.ok(
        ownerTeam.participants.length >= 2,
        `should have at least 2 participants, got ${ownerTeam.participants.length}: ${JSON.stringify(ownerTeam.participants)}`,
      );

      // Check joiner's view
      const joinerMachines = (await testSetup("get_user_machines", {
        user_id: joinerInfo.userId,
      })) as { teams: Array<{ team_id: string; machines: Array<{ token: string }> }> };

      const joinerTeam = joinerMachines.teams.find((t) => t.team_id === teamId);
      assert.ok(joinerTeam, "joiner should see the team in their machines");
      assert.ok(joinerTeam.machines.length >= 1, "joiner should have at least 1 machine");
    } finally {
      envA.cleanup();
      envB.cleanup();
    }
  });

  it("revoked machine disappears from user's team list", { timeout: 30_000 }, async () => {
    const env = createIsolatedEnv("machines-revoke");
    try {
      const { userId, token } = await setupLoggedInMachine(env, "revoke-machine");

      // Init team
      await runCli(
        ["init", "--name", "revoke-test", "--team", "backend", "--platform", "claude-code"],
        env,
      );
      const teamId = getTeamId(env);

      // Verify machine is visible
      const before = (await testSetup("get_user_machines", { user_id: userId })) as {
        teams: Array<{ team_id: string; machines: Array<{ token: string }> }>;
      };
      const teamBefore = before.teams.find((t) => t.team_id === teamId);
      assert.ok(teamBefore, "team should be visible before revocation");
      assert.ok(teamBefore.machines.length >= 1, "machine should be listed before revocation");

      // Revoke the token
      await testSetup("revoke_token", { user_id: userId, token });

      // Machine should no longer appear (revoked tokens are filtered)
      const after = (await testSetup("get_user_machines", { user_id: userId })) as {
        teams: Array<{ team_id: string; machines: Array<{ token: string }> }>;
      };
      const teamAfter = after.teams.find((t) => t.team_id === teamId);
      // Either the team is gone entirely or has 0 machines
      if (teamAfter) {
        const machineStillThere = teamAfter.machines.find((m) => m.token === token);
        assert.ok(!machineStillThere, "revoked machine should not appear in machines list");
      }
    } finally {
      env.cleanup();
    }
  });

  it("multiple machines for same user on same team", { timeout: 30_000 }, async () => {
    const env1 = createIsolatedEnv("machines-multi-1");
    const env2 = createIsolatedEnv("machines-multi-2");
    try {
      // Machine 1: create user and init team
      const info = await setupLoggedInMachine(env1, "machine-1");

      const initRes = await runCli(
        ["init", "--name", "multi-machine", "--team", "backend", "--platform", "claude-code"],
        env1,
      );
      assert.equal(initRes.exitCode, 0);

      // Get invite code
      const invRes = await runCli(["invite"], env1);
      const inviteMatch = invRes.stdout.match(/trc_inv_[A-Za-z0-9_-]+/);
      assert.ok(inviteMatch);
      const inviteCode = inviteMatch![0];

      // Machine 2: generate a different keypair but link to same user
      await runCli(
        ["init", "--name", "temp2", "--team", "backend", "--local", "--platform", "claude-code"],
        env2,
      );
      const token2 = getToken(env2)!;
      await testSetup("link_token", { user_id: info.userId, token: token2 });

      // Write config for machine 2
      const configPath2 = path.join(env2.home, ".teamrc", "config.json");
      const config2 = JSON.parse(fs.readFileSync(configPath2, "utf-8"));
      config2.account = { email: info.email };
      config2.machineName = "machine-2";
      fs.writeFileSync(configPath2, JSON.stringify(config2, null, 2));

      // Machine 2 joins the team
      fs.unlinkSync(path.join(env2.projectDir, ".teamrc.yaml"));
      const joinRes = await runCli(
        ["join", inviteCode, "--platform", "claude-code", "--relay", "http://localhost:4002"],
        env2,
      );
      assert.equal(joinRes.exitCode, 0, `join failed: ${joinRes.stdout}\n${joinRes.stderr}`);

      const teamId = getTeamId(env1);

      // Check: user should have 2 machines for this team
      const machineData = (await testSetup("get_user_machines", { user_id: info.userId })) as {
        teams: Array<{ team_id: string; machines: Array<{ token: string; machine_name: string }> }>;
      };

      const teamEntry = machineData.teams.find((t) => t.team_id === teamId);
      assert.ok(teamEntry, "team should appear");
      assert.ok(
        teamEntry.machines.length >= 2,
        `should have at least 2 machines, got ${teamEntry.machines.length}`,
      );

      // Both tokens should be present
      const tokens = teamEntry.machines.map((m) => m.token);
      assert.ok(tokens.includes(info.token), "machine 1 token should be in list");
      assert.ok(tokens.includes(token2), "machine 2 token should be in list");
    } finally {
      env1.cleanup();
      env2.cleanup();
    }
  });
});
