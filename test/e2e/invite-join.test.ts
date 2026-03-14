import { describe, it, before } from "node:test";
import assert from "node:assert/strict";
import {
  waitForServer,
  generateTestKeypair,
  signedPost,
  signedGet,
  createTeamWithKeypair,
} from "./helpers.ts";

before(async () => {
  await waitForServer();
});

describe("Invite and join", () => {
  it("creates an invite with trc_inv_ prefix and expires_at", async () => {
    const owner = await createTeamWithKeypair("invite-test", [
      { name: "Owner", role: "Lead" },
    ]);

    const res = await signedPost(
      "/api/teams/invite",
      { token: owner.token, team_id: owner.teamId, ttl_hours: 24 },
      owner,
    );
    assert.equal(res.status, 200);
    const data = (await res.json()) as { invite_code: string; expires_at: string };
    assert.ok(data.invite_code.startsWith("trc_inv_"), "invite should have trc_inv_ prefix");
    assert.ok(data.expires_at, "should include expires_at");
  });

  it("previews a team by invite (redacted  --  no knowledge/souls)", async () => {
    const owner = await createTeamWithKeypair("preview-test", [
      { name: "Owner", role: "Lead" },
    ]);

    // Create invite
    const invRes = await signedPost(
      "/api/teams/invite",
      { token: owner.token, team_id: owner.teamId, ttl_hours: 24 },
      owner,
    );
    const { invite_code } = (await invRes.json()) as { invite_code: string };

    // Preview with a different keypair
    const viewer = await generateTestKeypair();
    const previewRes = await signedPost(
      "/api/teams/preview",
      { invite_code, token: viewer.token },
      viewer,
    );
    assert.equal(previewRes.status, 200);
    const data = (await previewRes.json()) as { team: Record<string, unknown> };
    assert.equal(data.team.name, "preview-test");
    // Preview should be redacted  --  no knowledge or member souls
    assert.equal(data.team.knowledge, undefined);
  });

  it("joins a team by invite and can then access full data", async () => {
    const owner = await createTeamWithKeypair("join-test", [
      { name: "Owner", role: "Lead" },
    ]);

    // Create invite
    const invRes = await signedPost(
      "/api/teams/invite",
      { token: owner.token, team_id: owner.teamId, ttl_hours: 24 },
      owner,
    );
    const { invite_code } = (await invRes.json()) as { invite_code: string };

    // Join with new keypair
    const joiner = await generateTestKeypair();
    const joinRes = await signedPost(
      "/api/join",
      { invite_code, token: joiner.token },
      joiner,
    );
    assert.equal(joinRes.status, 200);
    const joinData = (await joinRes.json()) as { team: Record<string, unknown> };
    assert.equal(joinData.team.name, "join-test");

    // Joiner can now GET the team
    const teamId = joinData.team.id as string;
    const getRes = await signedGet(`/api/teams/${joiner.token}?team_id=${teamId}`, joiner);
    assert.equal(getRes.status, 200);
  });

  it("rejects invite creation from non-member", async () => {
    const owner = await createTeamWithKeypair("invite-reject", [
      { name: "Owner", role: "Lead" },
    ]);

    // Different keypair that is not a member
    const stranger = await generateTestKeypair();
    const res = await signedPost(
      "/api/teams/invite",
      { token: stranger.token, team_id: owner.teamId, ttl_hours: 24 },
      stranger,
    );
    assert.equal(res.status, 403);
  });

  it("rejects invalid invite code", async () => {
    const kp = await generateTestKeypair();
    const res = await signedPost(
      "/api/join",
      { invite_code: "trc_inv_totally-bogus-code", token: kp.token },
      kp,
    );
    assert.equal(res.status, 404);
  });
});
