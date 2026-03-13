import { describe, it, before } from "node:test";
import assert from "node:assert/strict";
import {
  waitForServer,
  generateTestKeypair,
  signedPost,
  createTeamWithKeypair,
} from "./helpers.ts";

before(async () => {
  await waitForServer();
});

describe("Push conflicts", () => {
  it("rejects push with stale base_hash (409)", async () => {
    const kp = await generateTestKeypair();

    // Create team
    const createRes = await signedPost(
      "/api/teams",
      {
        token: kp.token,
        team: { name: "conflict-test", members: [{ name: "A", role: "R" }] },
      },
      kp,
    );
    assert.equal(createRes.status, 201);
    const created = (await createRes.json()) as { team: Record<string, unknown> };
    const teamId = created.team.id as string;
    const originalHash = created.team.hash as string;

    // Push an update (advances the hash)
    const pushRes = await signedPost(
      "/api/teams",
      {
        token: kp.token,
        team_id: teamId,
        base_hash: originalHash,
        team: {
          name: "conflict-test",
          members: [
            { name: "A", role: "R" },
            { name: "B", role: "R2" },
          ],
        },
      },
      kp,
    );
    assert.equal(pushRes.status, 200);

    // Push again with the ORIGINAL (now stale) hash
    const conflictRes = await signedPost(
      "/api/teams",
      {
        token: kp.token,
        team_id: teamId,
        base_hash: originalHash, // stale!
        team: {
          name: "conflict-test",
          members: [{ name: "A", role: "changed" }],
        },
      },
      kp,
    );
    assert.equal(conflictRes.status, 409);
    const conflictData = (await conflictRes.json()) as { error: string; server_hash?: string };
    assert.equal(conflictData.error, "conflict");
    assert.ok(conflictData.server_hash, "should return server_hash");
  });

  it("accepts push with correct base_hash after conflict resolution", async () => {
    const kp = await generateTestKeypair();

    // Create
    const createRes = await signedPost(
      "/api/teams",
      {
        token: kp.token,
        team: { name: "resolve-test", members: [{ name: "A", role: "R" }] },
      },
      kp,
    );
    const created = (await createRes.json()) as { team: Record<string, unknown> };
    const teamId = created.team.id as string;
    const hash1 = created.team.hash as string;

    // Update 1
    const push1 = await signedPost(
      "/api/teams",
      {
        token: kp.token,
        team_id: teamId,
        base_hash: hash1,
        team: { name: "resolve-test", members: [{ name: "A", role: "updated" }] },
      },
      kp,
    );
    assert.equal(push1.status, 200);
    const updated = (await push1.json()) as { team: Record<string, unknown> };
    const hash2 = updated.team.hash as string;

    // Update 2 with correct hash
    const push2 = await signedPost(
      "/api/teams",
      {
        token: kp.token,
        team_id: teamId,
        base_hash: hash2,
        team: { name: "resolve-test", members: [{ name: "A", role: "final" }] },
      },
      kp,
    );
    assert.equal(push2.status, 200);
  });
});
