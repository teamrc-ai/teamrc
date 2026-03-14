import { describe, it, before } from "node:test";
import assert from "node:assert/strict";
import {
  waitForServer,
  generateTestKeypair,
  signedPost,
  createTeamWithKeypair,
  testSetup,
} from "./helpers.ts";

before(async () => {
  await waitForServer();
});

describe("Ownership (claim)", () => {
  it("claims ownership with valid secret", async () => {
    const owner = await createTeamWithKeypair("claim-test", [
      { name: "Owner", role: "Lead" },
    ]);
    const claimSecret = owner.team.owner_claim_secret as string;

    // Must have a linked account to claim
    const { user_id } = await testSetup("create_user") as { user_id: string };
    await testSetup("link_token", { user_id, token: owner.token });

    const res = await signedPost(
      "/api/teams/claim",
      { token: owner.token, claim_secret: claimSecret, team_id: owner.teamId },
      owner,
    );
    assert.equal(res.status, 200);
    const data = (await res.json()) as { status: string };
    assert.equal(data.status, "claimed");
  });

  it("prevents double-claim (secret cleared after first use)", async () => {
    const owner = await createTeamWithKeypair("double-claim", [
      { name: "Owner", role: "Lead" },
    ]);
    const claimSecret = owner.team.owner_claim_secret as string;

    const { user_id } = await testSetup("create_user") as { user_id: string };
    await testSetup("link_token", { user_id, token: owner.token });

    // First claim
    const res1 = await signedPost(
      "/api/teams/claim",
      { token: owner.token, claim_secret: claimSecret, team_id: owner.teamId },
      owner,
    );
    assert.equal(res1.status, 200);

    // Second claim with same secret
    const res2 = await signedPost(
      "/api/teams/claim",
      { token: owner.token, claim_secret: claimSecret, team_id: owner.teamId },
      owner,
    );
    // Should fail  --  already claimed or secret consumed
    assert.ok(
      res2.status === 404 || res2.status === 409,
      `expected 404 or 409, got ${res2.status}`,
    );
  });

  it("rejects claim without linked account", async () => {
    const owner = await createTeamWithKeypair("no-account-claim", [
      { name: "Owner", role: "Lead" },
    ]);
    const claimSecret = owner.team.owner_claim_secret as string;

    // No account linked  --  claim should fail with 403
    const res = await signedPost(
      "/api/teams/claim",
      { token: owner.token, claim_secret: claimSecret, team_id: owner.teamId },
      owner,
    );
    assert.equal(res.status, 403);
  });
});
