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

describe("Preview redaction (invite)", () => {
  it("redacts knowledge from invite preview", async () => {
    const owner = await createTeamWithKeypair("redact-knowledge", [
      { name: "Agent", role: "Dev" },
    ], {
      knowledge: "Secret internal API docs that should not leak.",
    });

    // Create invite
    const invRes = await signedPost(
      "/api/teams/invite",
      { token: owner.token, team_id: owner.teamId, ttl_hours: 24 },
      owner,
    );
    const { invite_code } = (await invRes.json()) as { invite_code: string };

    // Preview with different keypair
    const viewer = await generateTestKeypair();
    const previewRes = await signedPost(
      "/api/teams/preview",
      { invite_code, token: viewer.token },
      viewer,
    );
    assert.equal(previewRes.status, 200);
    const data = (await previewRes.json()) as { team: Record<string, unknown> };
    assert.equal(data.team.knowledge, undefined, "knowledge should be redacted in preview");
  });

  it("redacts member souls from invite preview", async () => {
    const owner = await createTeamWithKeypair("redact-soul", [
      { name: "Agent", role: "Dev" },
    ]);

    // Push member with soul
    await signedPost(
      "/api/teams",
      {
        token: owner.token,
        team_id: owner.teamId,
        base_hash: owner.team.hash as string,
        team: {
          name: "redact-soul",
          members: [{
            name: "Agent",
            role: "Dev",
            soul: "You are a careful, thorough developer.",
          }],
        },
      },
      owner,
    );

    // Create invite
    const invRes = await signedPost(
      "/api/teams/invite",
      { token: owner.token, team_id: owner.teamId, ttl_hours: 24 },
      owner,
    );
    const { invite_code } = (await invRes.json()) as { invite_code: string };

    // Preview
    const viewer = await generateTestKeypair();
    const previewRes = await signedPost(
      "/api/teams/preview",
      { invite_code, token: viewer.token },
      viewer,
    );
    const data = (await previewRes.json()) as { team: Record<string, unknown> };
    const members = data.team.members as Array<{ name: string; soul?: string }>;
    assert.equal(members[0].soul, undefined, "soul should be redacted in preview");
    // But name and role should still be visible
    assert.equal(members[0].name, "Agent");
  });

  it("includes team name and member names in preview", async () => {
    const owner = await createTeamWithKeypair("redact-visible", [
      { name: "Alice", role: "Frontend" },
      { name: "Bob", role: "Backend" },
    ]);

    const invRes = await signedPost(
      "/api/teams/invite",
      { token: owner.token, team_id: owner.teamId, ttl_hours: 24 },
      owner,
    );
    const { invite_code } = (await invRes.json()) as { invite_code: string };

    const viewer = await generateTestKeypair();
    const previewRes = await signedPost(
      "/api/teams/preview",
      { invite_code, token: viewer.token },
      viewer,
    );
    const data = (await previewRes.json()) as { team: Record<string, unknown> };
    assert.equal(data.team.name, "redact-visible");
    const members = data.team.members as Array<{ name: string; role: string }>;
    assert.equal(members.length, 2);
    assert.equal(members[0].name, "Alice");
    assert.equal(members[1].name, "Bob");
  });
});

describe("Clone preview redaction", () => {
  // Clear rate limits to avoid IP-based limits from other suites
  beforeEach(async () => {
    await testSetup("clear_rate_limits");
  });

  it("redacts knowledge from clone preview", async () => {
    const owner = await createTeamWithKeypair("clone-redact-k", [
      { name: "Agent", role: "Dev" },
    ], {
      knowledge: "Secret knowledge for clone test.",
    });
    const claimSecret = owner.team.owner_claim_secret as string;

    // Claim + set public
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

    // Clone preview
    const cloneRes = await unsignedGet(`/api/teams/clone/${clone_token}`);
    assert.equal(cloneRes.status, 200);
    const data = (await cloneRes.json()) as { team: Record<string, unknown> };
    assert.equal(data.team.knowledge, undefined, "knowledge should be redacted in clone preview");
  });

  it("redacts skill bodies from clone preview", async () => {
    const owner = await createTeamWithKeypair("clone-redact-s", [
      { name: "Agent", role: "Dev" },
    ], {
      skills: [{ id: "secret-skill", body: "This body should be redacted." }],
    });
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

    const cloneRes = await unsignedGet(`/api/teams/clone/${clone_token}`);
    const data = (await cloneRes.json()) as { team: Record<string, unknown> };
    const skills = data.team.skills as Array<{ id: string; body?: string }>;
    assert.equal(skills.length, 1);
    assert.equal(skills[0].id, "secret-skill");
    assert.equal(skills[0].body, undefined, "skill body should be redacted in clone preview");
  });
});
