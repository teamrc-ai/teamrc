import { describe, it, before } from "node:test";
import assert from "node:assert/strict";
import {
  waitForServer,
  generateTestKeypair,
  signedPost,
  signedGet,
  signedDelete,
  createTeamWithKeypair,
} from "./helpers.ts";

before(async () => {
  await waitForServer();
});

describe("Multi-token isolation", () => {
  /** Helper: create two teams for the same token by creating + joining via invite */
  async function createTwoTeamsForToken() {
    const kp = await generateTestKeypair();

    // Create team1 directly
    const res1 = await signedPost(
      "/api/teams",
      { token: kp.token, team: { name: "iso-a", members: [{ name: "A", role: "R" }] } },
      kp,
    );
    const team1 = ((await res1.json()) as { team: Record<string, unknown> }).team;

    // Create team2 with another token, invite kp
    const other = await createTeamWithKeypair("iso-b", [{ name: "B", role: "R" }]);
    const invRes = await signedPost(
      "/api/teams/invite",
      { token: other.token, team_id: other.teamId, ttl_hours: 24 },
      other,
    );
    const { invite_code } = (await invRes.json()) as { invite_code: string };
    await signedPost("/api/join", { invite_code, token: kp.token }, kp);

    return { kp, team1, team2Id: other.teamId, other };
  }

  it("push to one team does not affect another", async () => {
    const { kp, team1, team2Id, other } = await createTwoTeamsForToken();
    const team1Id = team1.id as string;
    const team1Hash = team1.hash as string;

    // Update team2 (using the other token which owns it)
    await signedPost(
      "/api/teams",
      {
        token: other.token,
        team_id: team2Id,
        team: {
          name: "iso-b",
          members: [
            { name: "B", role: "R" },
            { name: "C", role: "R2" },
          ],
        },
      },
      other,
    );

    // team1 should be unchanged
    const getRes = await signedGet(`/api/teams/${kp.token}?team_id=${team1Id}`, kp);
    const getData = (await getRes.json()) as { team: Record<string, unknown> };
    assert.equal(getData.team.hash, team1Hash, "team1 hash should not change");
    const members = getData.team.members as Array<{ name: string }>;
    assert.equal(members.length, 1);
  });

  it("each team has independent knowledge", async () => {
    const kp = await generateTestKeypair();

    // Create team1 with knowledge
    const res1 = await signedPost(
      "/api/teams",
      {
        token: kp.token,
        team: {
          name: "know-a",
          members: [{ name: "A", role: "R" }],
          knowledge: "Knowledge for A",
        },
      },
      kp,
    );
    const team1 = ((await res1.json()) as { team: Record<string, unknown> }).team;

    // Create team2 with different knowledge via another token + invite
    const other = await generateTestKeypair();
    const res2 = await signedPost(
      "/api/teams",
      {
        token: other.token,
        team: {
          name: "know-b",
          members: [{ name: "B", role: "R" }],
          knowledge: "Knowledge for B",
        },
      },
      other,
    );
    const team2 = ((await res2.json()) as { team: Record<string, unknown> }).team;
    const invRes = await signedPost(
      "/api/teams/invite",
      { token: other.token, team_id: team2.id, ttl_hours: 24 },
      other,
    );
    const { invite_code } = (await invRes.json()) as { invite_code: string };
    await signedPost("/api/join", { invite_code, token: kp.token }, kp);

    // Each team should have its own knowledge
    const get1 = await signedGet(`/api/teams/${kp.token}?team_id=${team1.id}`, kp);
    const data1 = (await get1.json()) as { team: Record<string, unknown> };
    assert.equal(data1.team.knowledge, "Knowledge for A");

    const get2 = await signedGet(`/api/teams/${kp.token}?team_id=${team2.id}`, kp);
    const data2 = (await get2.json()) as { team: Record<string, unknown> };
    assert.equal(data2.team.knowledge, "Knowledge for B");
  });

  it("scoped erase preserves other teams", async () => {
    const { kp, team1, team2Id } = await createTwoTeamsForToken();

    // Scoped erase of team2
    const eraseRes = await signedDelete(
      `/api/token/${encodeURIComponent(kp.token)}/erase?team_id=${team2Id}`,
      kp,
    );
    assert.equal(eraseRes.status, 200);

    // team1 still accessible
    const check = await signedGet(`/api/teams/${kp.token}?team_id=${team1.id}`, kp);
    assert.equal(check.status, 200);

    // All teams should show only 1
    const allRes = await signedGet(`/api/teams/all/${kp.token}`, kp);
    const allData = (await allRes.json()) as { teams: Array<Record<string, unknown>> };
    assert.equal(allData.teams.length, 1);
    assert.equal(allData.teams[0].name, "iso-a");
  });
});
