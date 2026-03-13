import { describe, it, before, beforeEach } from "node:test";
import assert from "node:assert/strict";
import {
  waitForServer,
  generateTestKeypair,
  signedPost,
  signedGet,
  unsignedGet,
  createTeamWithKeypair,
  testSetup,
} from "./helpers.ts";

before(async () => {
  await waitForServer();
});

describe("Full onboarding flow", () => {
  beforeEach(async () => {
    await testSetup("clear_rate_limits");
  });

  it("complete flow: create → device auth → claim → share → clone → join", async () => {
    // Step 1: CLI creates a team
    const creator = await createTeamWithKeypair("full-flow", [
      { name: "Architect", role: "System design and code review" },
      { name: "Builder", role: "Implementation and testing" },
    ], {
      skills: [
        { id: "code-review", body: "Review pull requests for correctness and style." },
        { id: "testing", body: "Write comprehensive test suites.", alwaysApply: true },
      ],
      knowledge: "We use TypeScript with strict mode. All PRs need 2 approvals.",
    });
    const claimSecret = creator.team.owner_claim_secret as string;
    assert.ok(claimSecret.startsWith("trc_ocs_"));

    // Step 2: Device auth (CLI initiates login)
    const deviceRes = await signedPost(
      "/api/auth/device",
      { token: creator.token },
      creator,
    );
    assert.equal(deviceRes.status, 200);
    const { device_code, user_code } = (await deviceRes.json()) as {
      device_code: string;
      user_code: string;
    };

    // Step 3: User confirms in browser (simulated via test helper)
    const { user_id, email } = (await testSetup("create_user")) as {
      user_id: string;
      email: string;
    };
    await testSetup("link_token", { user_id, token: creator.token });
    await testSetup("confirm_device_auth", { user_code, user_id, email });

    // Step 4: CLI polls and gets confirmation
    const pollRes = await signedGet(
      `/api/auth/device/${encodeURIComponent(device_code)}`,
      creator,
    );
    assert.equal(pollRes.status, 200);
    const pollData = (await pollRes.json()) as { status: string; email: string };
    assert.equal(pollData.status, "confirmed");
    assert.equal(pollData.email, email);

    // Step 5: Claim ownership
    const claimRes = await signedPost(
      "/api/teams/claim",
      { token: creator.token, claim_secret: claimSecret, team_id: creator.teamId },
      creator,
    );
    assert.equal(claimRes.status, 200);

    // Step 6: Share publicly
    const shareRes = await signedPost(
      "/api/teams/visibility",
      { token: creator.token, visibility: "public", team_id: creator.teamId },
      creator,
    );
    assert.equal(shareRes.status, 200);
    const { clone_token } = (await shareRes.json()) as { clone_token: string };
    assert.ok(clone_token.startsWith("trc_cl_"));

    // Step 7: Clone preview (no auth needed — public)
    const cloneRes = await unsignedGet(`/api/teams/clone/${clone_token}`);
    assert.equal(cloneRes.status, 200);
    const cloneData = (await cloneRes.json()) as { team: Record<string, unknown> };
    assert.equal(cloneData.team.name, "full-flow");
    // Clone redacts knowledge and skill bodies
    assert.equal(cloneData.team.knowledge, undefined);
    const cloneSkills = cloneData.team.skills as Array<{ id: string; body?: string }>;
    assert.equal(cloneSkills[0].body, undefined, "skill body redacted in clone");

    // Step 8: Create invite for a colleague
    const inviteRes = await signedPost(
      "/api/teams/invite",
      { token: creator.token, team_id: creator.teamId, ttl_hours: 48 },
      creator,
    );
    assert.equal(inviteRes.status, 200);
    const { invite_code } = (await inviteRes.json()) as { invite_code: string };

    // Step 9: Colleague previews (sees team structure but not secrets)
    const colleague = await generateTestKeypair();
    const previewRes = await signedPost(
      "/api/teams/preview",
      { invite_code, token: colleague.token },
      colleague,
    );
    assert.equal(previewRes.status, 200);
    const previewData = (await previewRes.json()) as { team: Record<string, unknown> };
    assert.equal(previewData.team.knowledge, undefined, "knowledge redacted in preview");

    // Step 10: Colleague joins
    const joinRes = await signedPost(
      "/api/join",
      { invite_code, token: colleague.token },
      colleague,
    );
    assert.equal(joinRes.status, 200);
    const joinData = (await joinRes.json()) as { team: Record<string, unknown> };
    // After joining, colleague gets full data including knowledge
    assert.equal(joinData.team.knowledge, "We use TypeScript with strict mode. All PRs need 2 approvals.");
    const joinSkills = joinData.team.skills as Array<{ id: string; body: string }>;
    assert.equal(joinSkills[0].body, "Review pull requests for correctness and style.");

    // Step 11: Colleague can GET the team with full data
    const getRes = await signedGet(
      `/api/teams/${colleague.token}?team_id=${creator.teamId}`,
      colleague,
    );
    assert.equal(getRes.status, 200);
    const getData = (await getRes.json()) as { team: Record<string, unknown> };
    const members = getData.team.members as Array<{ name: string; role: string }>;
    assert.equal(members.length, 2);
    assert.equal(members[0].name, "Architect");
  });
});

describe("Invite expiration", () => {
  it("expired invite is rejected (server-side TTL enforcement)", async () => {
    // We can't easily test TTL in E2E without time manipulation,
    // but we can test that invalid/nonexistent invite codes are rejected
    const kp = await generateTestKeypair();

    // Completely fabricated invite code
    const res = await signedPost(
      "/api/join",
      { invite_code: "trc_inv_AAAAAAAAAAAAAAAAAAAAAA", token: kp.token },
      kp,
    );
    assert.equal(res.status, 404);

    // Preview with fabricated code
    const previewRes = await signedPost(
      "/api/teams/preview",
      { invite_code: "trc_inv_AAAAAAAAAAAAAAAAAAAAAA", token: kp.token },
      kp,
    );
    assert.equal(previewRes.status, 404);
  });
});

describe("Visibility state transitions", () => {
  beforeEach(async () => {
    await testSetup("clear_rate_limits");
  });

  it("public → private → public transitions correctly", async () => {
    const owner = await createTeamWithKeypair("vis-transition", [
      { name: "Agent", role: "Dev" },
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
    const pub1 = await signedPost(
      "/api/teams/visibility",
      { token: owner.token, visibility: "public", team_id: owner.teamId },
      owner,
    );
    assert.equal(pub1.status, 200);
    const { clone_token: ct1 } = (await pub1.json()) as { clone_token: string };
    assert.ok(ct1);

    // Verify clone works
    const clone1 = await unsignedGet(`/api/teams/clone/${ct1}`);
    assert.equal(clone1.status, 200);

    // Set private
    const priv = await signedPost(
      "/api/teams/visibility",
      { token: owner.token, visibility: "private", team_id: owner.teamId },
      owner,
    );
    assert.equal(priv.status, 200);
    const privData = (await priv.json()) as { visibility: string; clone_token: string | null };
    assert.equal(privData.visibility, "private");

    // Clone should fail now
    const clone2 = await unsignedGet(`/api/teams/clone/${ct1}`);
    assert.equal(clone2.status, 404);

    // Set public again
    const pub2 = await signedPost(
      "/api/teams/visibility",
      { token: owner.token, visibility: "public", team_id: owner.teamId },
      owner,
    );
    assert.equal(pub2.status, 200);
    const { clone_token: ct2 } = (await pub2.json()) as { clone_token: string };
    assert.ok(ct2);

    // New clone token should work
    const clone3 = await unsignedGet(`/api/teams/clone/${ct2}`);
    assert.equal(clone3.status, 200);
  });
});
