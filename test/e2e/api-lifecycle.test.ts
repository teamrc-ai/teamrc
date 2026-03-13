import { describe, it, before } from "node:test";
import assert from "node:assert/strict";
import {
  waitForServer,
  generateTestKeypair,
  signedPost,
  signedGet,
  signedDelete,
  createTeamWithKeypair,
  RELAY_URL,
} from "./helpers.ts";

before(async () => {
  await waitForServer();
});

describe("API lifecycle", () => {
  it("creates a team with real auth and returns claim_secret", async () => {
    const kp = await generateTestKeypair();
    const res = await signedPost(
      "/api/teams",
      {
        token: kp.token,
        team: {
          name: "lifecycle-test",
          members: [{ name: "Alice", role: "Engineer" }],
        },
      },
      kp,
    );
    assert.equal(res.status, 201);
    const data = (await res.json()) as { team: Record<string, unknown> };
    assert.ok(data.team.id);
    assert.equal(data.team.name, "lifecycle-test");
    assert.ok(
      (data.team.owner_claim_secret as string).startsWith("trc_ocs_"),
      "claim secret should start with trc_ocs_",
    );
    assert.ok(data.team.hash, "should include hash");
    assert.ok(data.team.members_hash, "should include members_hash");
  });

  it("gets team with full data and hashes", async () => {
    const { token, privateKey, teamId } = await createTeamWithKeypair("get-test", [
      { name: "Bob", role: "Designer" },
    ]);
    const res = await signedGet(`/api/teams/${token}?team_id=${teamId}`, {
      privateKey,
      token,
    });
    assert.equal(res.status, 200);
    const data = (await res.json()) as { team: Record<string, unknown> };
    assert.equal(data.team.name, "get-test");
    assert.ok(data.team.hash);
  });

  it("gets team head (hashes only)", async () => {
    const { token, privateKey, teamId } = await createTeamWithKeypair("head-test", [
      { name: "Carol", role: "PM" },
    ]);
    const res = await signedGet(`/api/teams/${token}/head?team_id=${teamId}`, {
      privateKey,
      token,
    });
    assert.equal(res.status, 200);
    const data = (await res.json()) as Record<string, unknown>;
    assert.ok(data.hash);
    assert.ok(data.members_hash);
    assert.ok(data.skills_hash !== undefined);
    assert.ok(data.knowledge_hash !== undefined);
    // head should NOT include full team data
    assert.equal(data.name, undefined);
    assert.equal(data.members, undefined);
  });

  it("pushes an update with base_hash", async () => {
    const kp = await generateTestKeypair();
    // Create
    const createRes = await signedPost(
      "/api/teams",
      {
        token: kp.token,
        team: {
          name: "push-test",
          members: [{ name: "Dan", role: "Dev" }],
        },
      },
      kp,
    );
    assert.equal(createRes.status, 201);
    const created = (await createRes.json()) as { team: Record<string, unknown> };
    const teamId = created.team.id as string;
    const baseHash = created.team.hash as string;

    // Push update
    const pushRes = await signedPost(
      "/api/teams",
      {
        token: kp.token,
        team_id: teamId,
        base_hash: baseHash,
        team: {
          name: "push-test",
          members: [
            { name: "Dan", role: "Dev" },
            { name: "Eve", role: "QA" },
          ],
        },
      },
      kp,
    );
    assert.equal(pushRes.status, 200);
    const updated = (await pushRes.json()) as { team: Record<string, unknown> };
    const members = updated.team.members as Array<{ name: string }>;
    assert.equal(members.length, 2);
    assert.notEqual(updated.team.hash, baseHash, "hash should change after update");
  });

  it("gets all teams for a token (via create + invite/join)", async () => {
    const kp = await generateTestKeypair();

    // Create team A with kp
    await signedPost(
      "/api/teams",
      { token: kp.token, team: { name: "multi-a", members: [{ name: "A", role: "R" }] } },
      kp,
    );

    // Create team B with a different token, then invite kp to join
    const other = await createTeamWithKeypair("multi-b", [{ name: "B", role: "R" }]);
    const invRes = await signedPost(
      "/api/teams/invite",
      { token: other.token, team_id: other.teamId, ttl_hours: 24 },
      other,
    );
    const { invite_code } = (await invRes.json()) as { invite_code: string };
    await signedPost("/api/join", { invite_code, token: kp.token }, kp);

    const res = await signedGet(`/api/teams/all/${kp.token}`, kp);
    assert.equal(res.status, 200);
    const data = (await res.json()) as { teams: Array<Record<string, unknown>> };
    assert.equal(data.teams.length, 2);
    const names = data.teams.map((t) => t.name).sort();
    assert.deepEqual(names, ["multi-a", "multi-b"]);
  });

  it("returns 404 for nonexistent team", async () => {
    const kp = await generateTestKeypair();
    const res = await signedGet(`/api/teams/${kp.token}`, kp);
    assert.equal(res.status, 404);
  });

  it("erases all teams for a token", async () => {
    const { token, privateKey, teamId } = await createTeamWithKeypair("erase-all", [
      { name: "F", role: "R" },
    ]);
    // Verify it exists
    const before = await signedGet(`/api/teams/${token}?team_id=${teamId}`, { privateKey, token });
    assert.equal(before.status, 200);

    // Erase
    const eraseRes = await signedDelete(`/api/token/${encodeURIComponent(token)}/erase`, {
      privateKey,
      token,
    });
    assert.equal(eraseRes.status, 200);
    const eraseData = (await eraseRes.json()) as { teams_removed: number };
    assert.equal(eraseData.teams_removed, 1);

    // Verify gone
    const after = await signedGet(`/api/teams/${token}?team_id=${teamId}`, { privateKey, token });
    assert.equal(after.status, 404);
  });

  it("scoped erase removes one team, keeps another", async () => {
    const kp = await generateTestKeypair();

    // Create team1 with kp
    const res1 = await signedPost(
      "/api/teams",
      { token: kp.token, team: { name: "keep-me", members: [{ name: "A", role: "R" }] } },
      kp,
    );
    const team1 = ((await res1.json()) as { team: Record<string, unknown> }).team;

    // Create team2 with a different token, invite kp to join
    const other = await createTeamWithKeypair("remove-me", [{ name: "B", role: "R" }]);
    const invRes = await signedPost(
      "/api/teams/invite",
      { token: other.token, team_id: other.teamId, ttl_hours: 24 },
      other,
    );
    const { invite_code } = (await invRes.json()) as { invite_code: string };
    await signedPost("/api/join", { invite_code, token: kp.token }, kp);

    // Scoped erase of team2
    const eraseRes = await signedDelete(
      `/api/token/${encodeURIComponent(kp.token)}/erase?team_id=${other.teamId}`,
      kp,
    );
    assert.equal(eraseRes.status, 200);
    const eraseData = (await eraseRes.json()) as { teams_removed: number };
    assert.equal(eraseData.teams_removed, 1);

    // team1 still exists
    const check = await signedGet(`/api/teams/${kp.token}?team_id=${team1.id}`, kp);
    assert.equal(check.status, 200);

    // team2 gone for kp
    const check2 = await signedGet(`/api/teams/${kp.token}?team_id=${other.teamId}`, kp);
    assert.equal(check2.status, 404);
  });
});
