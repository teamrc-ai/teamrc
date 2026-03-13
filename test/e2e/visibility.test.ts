import { describe, it, before, beforeEach } from "node:test";
import assert from "node:assert/strict";
import {
  waitForServer,
  generateTestKeypair,
  signedPost,
  unsignedGet,
  createTeamWithKeypair,
  testSetup,
} from "./helpers.ts";

before(async () => {
  await waitForServer();
});

describe("Visibility (share/clone)", () => {
  // Clear rate limits before each test to avoid IP-based rate limit accumulation
  beforeEach(async () => {
    await testSetup("clear_rate_limits");
  });

  it("owner sets public and gets clone_token", async () => {
    const owner = await createTeamWithKeypair("vis-public", [
      { name: "Owner", role: "Lead" },
    ]);
    const claimSecret = owner.team.owner_claim_secret as string;

    // Link account and claim ownership
    const { user_id } = await testSetup("create_user") as { user_id: string };
    await testSetup("link_token", { user_id, token: owner.token });
    await signedPost(
      "/api/teams/claim",
      { token: owner.token, claim_secret: claimSecret, team_id: owner.teamId },
      owner,
    );

    // Set public
    const res = await signedPost(
      "/api/teams/visibility",
      { token: owner.token, visibility: "public", team_id: owner.teamId },
      owner,
    );
    assert.equal(res.status, 200);
    const data = (await res.json()) as { visibility: string; clone_token: string | null };
    assert.equal(data.visibility, "public");
    assert.ok(data.clone_token, "should return clone_token");
    assert.ok((data.clone_token as string).startsWith("trc_cl_"));
  });

  it("clone preview works without auth", async () => {
    const owner = await createTeamWithKeypair("vis-clone", [
      { name: "Owner", role: "Lead" },
    ]);
    const claimSecret = owner.team.owner_claim_secret as string;

    const { user_id } = await testSetup("create_user") as { user_id: string };
    await testSetup("link_token", { user_id, token: owner.token });
    await signedPost(
      "/api/teams/claim",
      { token: owner.token, claim_secret: claimSecret, team_id: owner.teamId },
      owner,
    );

    const visRes = await signedPost(
      "/api/teams/visibility",
      { token: owner.token, visibility: "public", team_id: owner.teamId },
      owner,
    );
    const { clone_token } = (await visRes.json()) as { clone_token: string };

    // Clone without any auth
    const cloneRes = await unsignedGet(`/api/teams/clone/${clone_token}`);
    assert.equal(cloneRes.status, 200);
    const data = (await cloneRes.json()) as { team: Record<string, unknown> };
    assert.equal(data.team.name, "vis-clone");
  });

  it("non-owner cannot set visibility", async () => {
    const owner = await createTeamWithKeypair("vis-non-owner", [
      { name: "Owner", role: "Lead" },
    ]);

    // Invite a joiner
    const invRes = await signedPost(
      "/api/teams/invite",
      { token: owner.token, team_id: owner.teamId, ttl_hours: 24 },
      owner,
    );
    const { invite_code } = (await invRes.json()) as { invite_code: string };

    const joiner = await generateTestKeypair();
    await signedPost("/api/join", { invite_code, token: joiner.token }, joiner);

    // Joiner tries to set visibility
    const res = await signedPost(
      "/api/teams/visibility",
      { token: joiner.token, visibility: "public", team_id: owner.teamId },
      joiner,
    );
    assert.equal(res.status, 403);
  });

  it("setting private revokes clone access", async () => {
    const owner = await createTeamWithKeypair("vis-revoke", [
      { name: "Owner", role: "Lead" },
    ]);
    const claimSecret = owner.team.owner_claim_secret as string;

    const { user_id } = await testSetup("create_user") as { user_id: string };
    await testSetup("link_token", { user_id, token: owner.token });
    await signedPost(
      "/api/teams/claim",
      { token: owner.token, claim_secret: claimSecret, team_id: owner.teamId },
      owner,
    );

    // Set public
    const pubRes = await signedPost(
      "/api/teams/visibility",
      { token: owner.token, visibility: "public", team_id: owner.teamId },
      owner,
    );
    const { clone_token } = (await pubRes.json()) as { clone_token: string };

    // Verify clone works
    const cloneOk = await unsignedGet(`/api/teams/clone/${clone_token}`);
    assert.equal(cloneOk.status, 200);

    // Set private
    await signedPost(
      "/api/teams/visibility",
      { token: owner.token, visibility: "private", team_id: owner.teamId },
      owner,
    );

    // Clone should now fail
    const cloneFail = await unsignedGet(`/api/teams/clone/${clone_token}`);
    assert.equal(cloneFail.status, 404);
  });
});
