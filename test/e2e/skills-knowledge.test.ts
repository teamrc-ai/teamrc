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

describe("Skills", () => {
  it("creates a team with skills and returns skills_hash", async () => {
    const result = await createTeamWithKeypair("skill-team", [
      { name: "Agent", role: "Dev", skills: ["code-review"] },
    ], {
      skills: [
        { id: "code-review", body: "Review code for bugs and style issues." },
        { id: "testing", body: "Write unit and integration tests.", alwaysApply: true },
      ],
    });

    assert.ok(result.team.skills_hash, "should have skills_hash");
    const skills = result.team.skills as Array<{ id: string; body: string; alwaysApply?: boolean }>;
    assert.equal(skills.length, 2);
    assert.equal(skills[0].id, "code-review");
    assert.equal(skills[0].body, "Review code for bugs and style issues.");
    assert.equal(skills[1].id, "testing");
    assert.equal(skills[1].alwaysApply, true);
  });

  it("pushes skill updates and hash changes", async () => {
    const owner = await createTeamWithKeypair("skill-update", [
      { name: "Agent", role: "Dev" },
    ], {
      skills: [{ id: "lint", body: "Run linter." }],
    });
    const originalHash = owner.team.skills_hash as string;

    // Push with updated skills
    const pushRes = await signedPost(
      "/api/teams",
      {
        token: owner.token,
        team_id: owner.teamId,
        base_hash: owner.team.hash as string,
        team: {
          name: "skill-update",
          members: [{ name: "Agent", role: "Dev" }],
          skills: [
            { id: "lint", body: "Run linter with strict mode." },
            { id: "format", body: "Format code with prettier." },
          ],
        },
      },
      owner,
    );
    assert.equal(pushRes.status, 200);
    const updated = (await pushRes.json()) as { team: Record<string, unknown> };
    const newSkills = updated.team.skills as Array<{ id: string; body: string }>;
    assert.equal(newSkills.length, 2);
    assert.notEqual(updated.team.skills_hash, originalHash, "skills_hash should change");
  });

  it("preserves member skill assignments through push/pull", async () => {
    const owner = await createTeamWithKeypair("skill-assign", [
      { name: "Frontend", role: "UI Dev", skills: ["css-review"] },
      { name: "Backend", role: "API Dev", skills: ["sql-review"] },
    ], {
      skills: [
        { id: "css-review", body: "Review CSS for consistency." },
        { id: "sql-review", body: "Review SQL queries for performance." },
      ],
    });

    // Pull and verify assignments
    const getRes = await signedGet(
      `/api/teams/${owner.token}?team_id=${owner.teamId}`,
      owner,
    );
    assert.equal(getRes.status, 200);
    const data = (await getRes.json()) as { team: Record<string, unknown> };
    const members = data.team.members as Array<{ name: string; skills?: string[] }>;
    // Find by name since order may vary
    const frontend = members.find((m) => m.name === "Frontend")!;
    const backend = members.find((m) => m.name === "Backend")!;
    assert.deepEqual(frontend.skills, ["css-review"]);
    assert.deepEqual(backend.skills, ["sql-review"]);
  });

  it("skills with globs are stored correctly", async () => {
    const owner = await createTeamWithKeypair("skill-globs", [
      { name: "Agent", role: "Dev" },
    ], {
      skills: [{
        id: "ts-lint",
        body: "Lint TypeScript files.",
        globs: ["**/*.ts", "**/*.tsx"],
        alwaysApply: true,
      }],
    });

    const getRes = await signedGet(
      `/api/teams/${owner.token}?team_id=${owner.teamId}`,
      owner,
    );
    const data = (await getRes.json()) as { team: Record<string, unknown> };
    const skills = data.team.skills as Array<{ id: string; globs?: string[] }>;
    assert.deepEqual(skills[0].globs, ["**/*.ts", "**/*.tsx"]);
  });
});

describe("Member souls (instructions)", () => {
  it("creates members with soul and retrieves them", async () => {
    const owner = await createTeamWithKeypair("soul-test", [
      { name: "Agent", role: "Dev" },
    ]);

    // Push with soul
    const pushRes = await signedPost(
      "/api/teams",
      {
        token: owner.token,
        team_id: owner.teamId,
        base_hash: owner.team.hash as string,
        team: {
          name: "soul-test",
          members: [{
            name: "Agent",
            role: "Dev",
            soul: "You are a careful, methodical developer who values code quality.",
          }],
        },
      },
      owner,
    );
    assert.equal(pushRes.status, 200);

    // Pull and verify
    const getRes = await signedGet(
      `/api/teams/${owner.token}?team_id=${owner.teamId}`,
      owner,
    );
    const data = (await getRes.json()) as { team: Record<string, unknown> };
    const members = data.team.members as Array<{ name: string; soul?: string }>;
    assert.equal(members[0].soul, "You are a careful, methodical developer who values code quality.");
  });

  it("updates member soul via push", async () => {
    const owner = await createTeamWithKeypair("soul-update", [
      { name: "Agent", role: "Dev" },
    ]);

    // Push initial soul
    const push1 = await signedPost(
      "/api/teams",
      {
        token: owner.token,
        team_id: owner.teamId,
        base_hash: owner.team.hash as string,
        team: {
          name: "soul-update",
          members: [{ name: "Agent", role: "Dev", soul: "Original instructions." }],
        },
      },
      owner,
    );
    const hash1 = ((await push1.json()) as { team: Record<string, unknown> }).team.hash as string;

    // Push updated soul
    const push2 = await signedPost(
      "/api/teams",
      {
        token: owner.token,
        team_id: owner.teamId,
        base_hash: hash1,
        team: {
          name: "soul-update",
          members: [{ name: "Agent", role: "Dev", soul: "Updated instructions with more detail." }],
        },
      },
      owner,
    );
    assert.equal(push2.status, 200);

    const getRes = await signedGet(
      `/api/teams/${owner.token}?team_id=${owner.teamId}`,
      owner,
    );
    const data = (await getRes.json()) as { team: Record<string, unknown> };
    const members = data.team.members as Array<{ soul?: string }>;
    assert.equal(members[0].soul, "Updated instructions with more detail.");
  });
});

describe("Knowledge", () => {
  it("creates a team with knowledge and returns knowledge_hash", async () => {
    const owner = await createTeamWithKeypair("know-create", [
      { name: "Agent", role: "Dev" },
    ], {
      knowledge: "Our API uses REST with JSON. Auth is via JWT tokens.",
    });

    assert.ok(owner.team.knowledge_hash, "should have knowledge_hash");
    assert.equal(owner.team.knowledge, "Our API uses REST with JSON. Auth is via JWT tokens.");
  });

  it("updates knowledge and hash changes (append-only merge)", async () => {
    const owner = await createTeamWithKeypair("know-update", [
      { name: "Agent", role: "Dev" },
    ], {
      knowledge: "Initial knowledge.",
    });
    const originalKnowledgeHash = owner.team.knowledge_hash as string;

    const pushRes = await signedPost(
      "/api/teams",
      {
        token: owner.token,
        team_id: owner.teamId,
        base_hash: owner.team.hash as string,
        team: {
          name: "know-update",
          members: [{ name: "Agent", role: "Dev" }],
          knowledge: "Initial knowledge.\nNew line of knowledge.",
        },
      },
      owner,
    );
    assert.equal(pushRes.status, 200);
    const updated = (await pushRes.json()) as { team: Record<string, unknown> };
    assert.notEqual(updated.team.knowledge_hash, originalKnowledgeHash, "knowledge_hash should change");
    // Knowledge is stored as-sent (server doesn't merge  --  that's the CLI's job)
    const knowledge = updated.team.knowledge as string;
    assert.ok(knowledge.includes("Initial knowledge."), "should contain original");
    assert.ok(knowledge.includes("New line of knowledge."), "should contain new line");
  });

  it("knowledge persists through pull", async () => {
    const owner = await createTeamWithKeypair("know-pull", [
      { name: "Agent", role: "Dev" },
    ], {
      knowledge: "Persistent knowledge content.",
    });

    const getRes = await signedGet(
      `/api/teams/${owner.token}?team_id=${owner.teamId}`,
      owner,
    );
    const data = (await getRes.json()) as { team: Record<string, unknown> };
    assert.equal(data.team.knowledge, "Persistent knowledge content.");
  });
});

describe("Platforms field", () => {
  it("creates a team with platforms array", async () => {
    const owner = await createTeamWithKeypair("plat-test", [
      { name: "Agent", role: "Dev" },
    ]);

    const pushRes = await signedPost(
      "/api/teams",
      {
        token: owner.token,
        team_id: owner.teamId,
        base_hash: owner.team.hash as string,
        team: {
          name: "plat-test",
          members: [{ name: "Agent", role: "Dev" }],
          platforms: ["claude-code", "cursor"],
        },
      },
      owner,
    );
    assert.equal(pushRes.status, 200);

    // Verify via server-side context
    const serverData = (await testSetup("get_team", {
      token: owner.token,
      team_id: owner.teamId,
    })) as { team: Record<string, unknown> };
    const platforms = serverData.team.platforms as string[];
    assert.ok(platforms.includes("claude-code"));
    assert.ok(platforms.includes("cursor"));
  });
});
