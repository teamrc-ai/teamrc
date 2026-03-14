import { describe, it, before } from "node:test";
import assert from "node:assert/strict";
import {
  waitForServer,
  signedPost,
  signedGet,
  createTeamWithKeypair,
  testSetup,
} from "./helpers.ts";

before(async () => {
  await waitForServer();
});

describe("Daemon polling behavior (hash-based change detection)", () => {
  it("head returns hashes that match full team response", async () => {
    const owner = await createTeamWithKeypair("daemon-hash-match", [
      { name: "Agent", role: "Dev" },
    ], {
      skills: [{ id: "test-skill", body: "Test content." }],
      knowledge: "Some knowledge.",
    });

    // Get full team
    const fullRes = await signedGet(
      `/api/teams/${owner.token}?team_id=${owner.teamId}`,
      owner,
    );
    const fullData = (await fullRes.json()) as { team: Record<string, unknown> };

    // Get head
    const headRes = await signedGet(
      `/api/teams/${owner.token}/head?team_id=${owner.teamId}`,
      owner,
    );
    const headData = (await headRes.json()) as Record<string, unknown>;

    // Hashes should match
    assert.equal(headData.hash, fullData.team.hash);
    assert.equal(headData.members_hash, fullData.team.members_hash);
    assert.equal(headData.skills_hash, fullData.team.skills_hash);
    assert.equal(headData.knowledge_hash, fullData.team.knowledge_hash);
  });

  it("hash stays the same when no changes are made", async () => {
    const owner = await createTeamWithKeypair("daemon-no-change", [
      { name: "Agent", role: "Dev" },
    ]);

    // Poll head twice
    const head1 = await signedGet(
      `/api/teams/${owner.token}/head?team_id=${owner.teamId}`,
      owner,
    );
    const data1 = (await head1.json()) as Record<string, unknown>;

    const head2 = await signedGet(
      `/api/teams/${owner.token}/head?team_id=${owner.teamId}`,
      owner,
    );
    const data2 = (await head2.json()) as Record<string, unknown>;

    assert.equal(data1.hash, data2.hash, "hash should not change without updates");
  });

  it("hash changes when team is updated (daemon detects change)", async () => {
    const owner = await createTeamWithKeypair("daemon-detect", [
      { name: "Agent", role: "Dev" },
    ]);

    // Get initial hash (daemon stores this)
    const head1 = await signedGet(
      `/api/teams/${owner.token}/head?team_id=${owner.teamId}`,
      owner,
    );
    const initialHash = ((await head1.json()) as Record<string, unknown>).hash;

    // Someone updates the team (simulates another client or web edit)
    await testSetup("update_team", {
      token: owner.token,
      team_id: owner.teamId,
      team: {
        name: "daemon-detect",
        members: [
          { name: "Agent", role: "Dev" },
          { name: "NewAgent", role: "QA" },
        ],
      },
    });

    // Daemon polls head again  --  should detect hash change
    const head2 = await signedGet(
      `/api/teams/${owner.token}/head?team_id=${owner.teamId}`,
      owner,
    );
    const newHash = ((await head2.json()) as Record<string, unknown>).hash;

    assert.notEqual(initialHash, newHash, "hash should change after update");

    // Daemon fetches full team since hash changed
    const fullRes = await signedGet(
      `/api/teams/${owner.token}?team_id=${owner.teamId}`,
      owner,
    );
    const fullData = (await fullRes.json()) as { team: Record<string, unknown> };
    const members = fullData.team.members as Array<{ name: string }>;
    assert.equal(members.length, 2, "full fetch should have updated data");
    assert.equal(members[1].name, "NewAgent");
  });

  it("individual hash fields change independently", async () => {
    const owner = await createTeamWithKeypair("daemon-indep", [
      { name: "Agent", role: "Dev" },
    ], {
      skills: [{ id: "test-skill", body: "Test." }],
      knowledge: "Some knowledge.",
    });

    const head1 = await signedGet(
      `/api/teams/${owner.token}/head?team_id=${owner.teamId}`,
      owner,
    );
    const initial = (await head1.json()) as Record<string, string>;

    // Update only knowledge
    await signedPost(
      "/api/teams",
      {
        token: owner.token,
        team_id: owner.teamId,
        base_hash: initial.hash,
        team: {
          name: "daemon-indep",
          members: [{ name: "Agent", role: "Dev" }],
          skills: [{ id: "test-skill", body: "Test." }],
          knowledge: "Updated knowledge content.",
        },
      },
      owner,
    );

    const head2 = await signedGet(
      `/api/teams/${owner.token}/head?team_id=${owner.teamId}`,
      owner,
    );
    const updated = (await head2.json()) as Record<string, string>;

    // Knowledge hash should change
    assert.notEqual(initial.knowledge_hash, updated.knowledge_hash, "knowledge_hash should change");
    // Members hash should stay the same (same members)
    assert.equal(initial.members_hash, updated.members_hash, "members_hash should not change");
    // Overall hash should change
    assert.notEqual(initial.hash, updated.hash, "overall hash should change");
  });

  it("deleted team returns 404 on head (daemon handles gracefully)", async () => {
    const owner = await createTeamWithKeypair("daemon-deleted", [
      { name: "Agent", role: "Dev" },
    ]);

    // Verify head works
    const head1 = await signedGet(
      `/api/teams/${owner.token}/head?team_id=${owner.teamId}`,
      owner,
    );
    assert.equal(head1.status, 200);

    // Erase the team
    const eraseRes = await (await import("./helpers.ts")).signedDelete(
      `/api/token/${encodeURIComponent(owner.token)}/erase`,
      owner,
    );
    assert.equal(eraseRes.status, 200);

    // Head should now 404
    const head2 = await signedGet(
      `/api/teams/${owner.token}/head?team_id=${owner.teamId}`,
      owner,
    );
    assert.equal(head2.status, 404);
  });
});
