import { describe, it, before } from "node:test";
import assert from "node:assert/strict";
import {
  waitForServer,
  generateTestKeypair,
  signedPost,
} from "./helpers.ts";

before(async () => {
  await waitForServer();
});

describe("Input validation", () => {
  describe("Team name", () => {
    it("rejects name longer than 64 characters", async () => {
      const kp = await generateTestKeypair();
      const res = await signedPost(
        "/api/teams",
        {
          token: kp.token,
          team: { name: "a".repeat(65), members: [{ name: "A", role: "R" }] },
        },
        kp,
      );
      assert.equal(res.status, 400);
      const data = (await res.json()) as { error: string };
      assert.ok(data.error.includes("64"), `error should mention 64: ${data.error}`);
    });

    it("accepts name of exactly 64 characters", async () => {
      const kp = await generateTestKeypair();
      const res = await signedPost(
        "/api/teams",
        {
          token: kp.token,
          team: { name: "a".repeat(64), members: [{ name: "A", role: "R" }] },
        },
        kp,
      );
      assert.equal(res.status, 201);
    });

    it("rejects name with special characters", async () => {
      const kp = await generateTestKeypair();
      const res = await signedPost(
        "/api/teams",
        {
          token: kp.token,
          team: { name: "bad@name!", members: [{ name: "A", role: "R" }] },
        },
        kp,
      );
      assert.equal(res.status, 400);
      assert.ok(((await res.json()) as { error: string }).error.includes("alphanumeric"));
    });

    it("rejects empty name", async () => {
      const kp = await generateTestKeypair();
      const res = await signedPost(
        "/api/teams",
        {
          token: kp.token,
          team: { name: "", members: [{ name: "A", role: "R" }] },
        },
        kp,
      );
      assert.equal(res.status, 400);
    });
  });

  describe("Member limits", () => {
    it("rejects more than 20 members", async () => {
      const kp = await generateTestKeypair();
      const members = Array.from({ length: 21 }, (_, i) => ({
        name: `Agent-${i}`,
        role: "Role",
      }));
      const res = await signedPost(
        "/api/teams",
        { token: kp.token, team: { name: "too-many", members } },
        kp,
      );
      assert.equal(res.status, 400);
      assert.ok(((await res.json()) as { error: string }).error.includes("20"));
    });

    it("accepts exactly 20 members", async () => {
      const kp = await generateTestKeypair();
      const members = Array.from({ length: 20 }, (_, i) => ({
        name: `Agent-${i}`,
        role: "Role",
      }));
      const res = await signedPost(
        "/api/teams",
        { token: kp.token, team: { name: "max-members", members } },
        kp,
      );
      assert.equal(res.status, 201);
    });

    it("rejects member name over 64 bytes", async () => {
      const kp = await generateTestKeypair();
      const res = await signedPost(
        "/api/teams",
        {
          token: kp.token,
          team: {
            name: "big-name",
            members: [{ name: "x".repeat(65), role: "R" }],
          },
        },
        kp,
      );
      assert.equal(res.status, 400);
    });

    it("rejects member soul over 10KB", async () => {
      const kp = await generateTestKeypair();
      const res = await signedPost(
        "/api/teams",
        {
          token: kp.token,
          team: {
            name: "big-soul",
            members: [{ name: "A", role: "R", soul: "x".repeat(10_001) }],
          },
        },
        kp,
      );
      assert.equal(res.status, 400);
    });
  });

  describe("Skill limits", () => {
    it("rejects more than 50 skills", async () => {
      const kp = await generateTestKeypair();
      const skills = Array.from({ length: 51 }, (_, i) => ({
        id: `skill-${i}`,
        body: "content",
      }));
      const res = await signedPost(
        "/api/teams",
        {
          token: kp.token,
          team: { name: "too-many-skills", members: [{ name: "A", role: "R" }], skills },
        },
        kp,
      );
      assert.equal(res.status, 400);
      assert.ok(((await res.json()) as { error: string }).error.includes("50"));
    });

    it("rejects skill body over 10KB", async () => {
      const kp = await generateTestKeypair();
      const res = await signedPost(
        "/api/teams",
        {
          token: kp.token,
          team: {
            name: "big-skill",
            members: [{ name: "A", role: "R" }],
            skills: [{ id: "big", body: "x".repeat(10_001) }],
          },
        },
        kp,
      );
      assert.equal(res.status, 400);
    });

    it("rejects invalid skill ID format", async () => {
      const kp = await generateTestKeypair();
      const res = await signedPost(
        "/api/teams",
        {
          token: kp.token,
          team: {
            name: "bad-skill-id",
            members: [{ name: "A", role: "R" }],
            skills: [{ id: "../traversal", body: "hack" }],
          },
        },
        kp,
      );
      assert.equal(res.status, 400);
      assert.ok(((await res.json()) as { error: string }).error.includes("invalid id"));
    });

    it("rejects skill ID starting with non-alphanumeric", async () => {
      const kp = await generateTestKeypair();
      const res = await signedPost(
        "/api/teams",
        {
          token: kp.token,
          team: {
            name: "bad-start",
            members: [{ name: "A", role: "R" }],
            skills: [{ id: "-leading-dash", body: "content" }],
          },
        },
        kp,
      );
      assert.equal(res.status, 400);
    });
  });

  describe("Knowledge limits", () => {
    it("rejects knowledge over 100KB", async () => {
      const kp = await generateTestKeypair();
      const res = await signedPost(
        "/api/teams",
        {
          token: kp.token,
          team: {
            name: "big-knowledge",
            members: [{ name: "A", role: "R" }],
            knowledge: "x".repeat(100_001),
          },
        },
        kp,
      );
      assert.equal(res.status, 400);
      assert.ok(((await res.json()) as { error: string }).error.includes("100"));
    });
  });

  describe("Platform validation", () => {
    it("rejects unknown platform", async () => {
      const kp = await generateTestKeypair();
      const res = await signedPost(
        "/api/teams",
        {
          token: kp.token,
          team: {
            name: "bad-platform",
            members: [{ name: "A", role: "R" }],
            platforms: ["claude-code", "unknown-ai"],
          },
        },
        kp,
      );
      assert.equal(res.status, 400);
      assert.ok(((await res.json()) as { error: string }).error.includes("unknown-ai"));
    });

    it("accepts all valid platforms", async () => {
      const kp = await generateTestKeypair();
      const res = await signedPost(
        "/api/teams",
        {
          token: kp.token,
          team: {
            name: "all-platforms",
            members: [{ name: "A", role: "R" }],
            platforms: ["claude-code", "cursor", "codex", "gemini", "openclaw", "copilot", "amazon-q", "windsurf", "cline"],
          },
        },
        kp,
      );
      assert.equal(res.status, 201);
    });
  });
});
