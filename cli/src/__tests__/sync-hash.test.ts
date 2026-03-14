import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import {
  computeMembersHash,
  computeSkillsHash,
  computeKnowledgeHash,
  computeFullHash,
  computeTeamHashes,
  canonicalize,
} from "../sync-hash.js";
import type { TeamMember, Skill, TeamDefinition } from "../adapters/base.js";

function sha256(input: string): string {
  return createHash("sha256").update(input, "utf-8").digest("hex");
}

// Known test vectors
const HASH_EMPTY_ARRAY = "4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945";
const HASH_EMPTY_STRING = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855";

describe("canonicalize", () => {
  it("sorts object keys lexicographically", () => {
    const result = canonicalize({ b: 1, a: 2 });
    const keys = Object.keys(result as Record<string, unknown>);
    assert.deepEqual(keys, ["a", "b"]);
  });

  it("recursively sorts nested object keys", () => {
    const result = canonicalize({ z: { b: 1, a: 2 }, a: 3 });
    const outer = Object.keys(result as Record<string, unknown>);
    assert.deepEqual(outer, ["a", "z"]);
    const inner = Object.keys((result as Record<string, unknown>).z as Record<string, unknown>);
    assert.deepEqual(inner, ["a", "b"]);
  });

  it("removes null and undefined values", () => {
    const result = canonicalize({ a: 1, b: null, c: undefined }) as Record<string, unknown>;
    assert.deepEqual(Object.keys(result), ["a"]);
    assert.equal(result.a, 1);
  });

  it("preserves arrays", () => {
    const result = canonicalize({ items: [3, 1, 2] }) as Record<string, unknown>;
    assert.deepEqual(result.items, [3, 1, 2]);
  });

  it("removes null entries from arrays", () => {
    const result = canonicalize([1, null, 3]);
    assert.deepEqual(result, [1, 3]);
  });

  it("returns primitives as-is", () => {
    assert.equal(canonicalize("hello"), "hello");
    assert.equal(canonicalize(42), 42);
    assert.equal(canonicalize(true), true);
  });

  it("returns undefined for null/undefined input", () => {
    assert.equal(canonicalize(null), undefined);
    assert.equal(canonicalize(undefined), undefined);
  });
});

describe("computeMembersHash", () => {
  it("returns SHA-256 of empty array for no members", () => {
    const hash = computeMembersHash([]);
    assert.equal(hash, HASH_EMPTY_ARRAY);
    assert.equal(hash, sha256("[]"));
  });

  it("hashes a simple member", () => {
    const members: TeamMember[] = [{ name: "alice", role: "dev" }];
    const hash = computeMembersHash(members);
    assert.equal(hash, sha256('[{"name":"alice","role":"dev"}]'));
  });

  it("sorts members by name", () => {
    const members: TeamMember[] = [
      { name: "bob", role: "qa" },
      { name: "alice", role: "dev" },
    ];
    const hash = computeMembersHash(members);
    // alice comes first after sorting
    const expected = sha256('[{"name":"alice","role":"dev"},{"name":"bob","role":"qa"}]');
    assert.equal(hash, expected);
  });

  it("sorts member object keys lexicographically", () => {
    const members: TeamMember[] = [{ name: "alice", role: "dev" }];
    const hash = computeMembersHash(members);
    // name < role alphabetically
    assert.equal(hash, sha256('[{"name":"alice","role":"dev"}]'));
  });

  it("sorts skills array within a member", () => {
    const members: TeamMember[] = [
      { name: "alice", role: "dev", skills: ["b", "a"] },
    ];
    const hash = computeMembersHash(members);
    // skills sorted: ["a", "b"], keys sorted: name < role < skills
    assert.equal(hash, sha256('[{"name":"alice","role":"dev","skills":["a","b"]}]'));
  });

  it("omits undefined/null soul", () => {
    const members: TeamMember[] = [
      { name: "alice", role: "dev", soul: undefined },
    ];
    const hash = computeMembersHash(members);
    assert.equal(hash, sha256('[{"name":"alice","role":"dev"}]'));
  });

  it("omits empty string soul", () => {
    const members: TeamMember[] = [
      { name: "alice", role: "dev", soul: "" },
    ];
    const hash = computeMembersHash(members);
    assert.equal(hash, sha256('[{"name":"alice","role":"dev"}]'));
  });

  it("includes non-empty soul", () => {
    const members: TeamMember[] = [
      { name: "alice", role: "dev", soul: "careful coder" },
    ];
    const hash = computeMembersHash(members);
    assert.equal(hash, sha256('[{"name":"alice","role":"dev","soul":"careful coder"}]'));
  });

  it("includes non-empty description", () => {
    const members: TeamMember[] = [
      { name: "alice", role: "dev", description: "Builds features. Use for feature work." },
    ];
    const hash = computeMembersHash(members);
    // description < name alphabetically
    assert.equal(hash, sha256('[{"description":"Builds features. Use for feature work.","name":"alice","role":"dev"}]'));
  });

  it("omits undefined description", () => {
    const members: TeamMember[] = [
      { name: "alice", role: "dev", description: undefined },
    ];
    const hash = computeMembersHash(members);
    assert.equal(hash, sha256('[{"name":"alice","role":"dev"}]'));
  });

  it("omits empty string description", () => {
    const members: TeamMember[] = [
      { name: "alice", role: "dev", description: "" },
    ];
    const hash = computeMembersHash(members);
    assert.equal(hash, sha256('[{"name":"alice","role":"dev"}]'));
  });

  it("description changes the hash", () => {
    const without: TeamMember[] = [{ name: "alice", role: "dev" }];
    const withDesc: TeamMember[] = [{ name: "alice", role: "dev", description: "some desc" }];
    assert.notEqual(computeMembersHash(without), computeMembersHash(withDesc));
  });

  it("omits empty skills array", () => {
    const members: TeamMember[] = [
      { name: "alice", role: "dev", skills: [] },
    ];
    const hash = computeMembersHash(members);
    assert.equal(hash, sha256('[{"name":"alice","role":"dev"}]'));
  });

  it("is deterministic across multiple calls", () => {
    const members: TeamMember[] = [
      { name: "charlie", role: "ops" },
      { name: "alice", role: "dev" },
      { name: "bob", role: "qa" },
    ];
    const hash1 = computeMembersHash(members);
    const hash2 = computeMembersHash(members);
    assert.equal(hash1, hash2);
  });
});

describe("computeSkillsHash", () => {
  it("returns SHA-256 of empty array for no skills", () => {
    const hash = computeSkillsHash([]);
    assert.equal(hash, HASH_EMPTY_ARRAY);
  });

  it("hashes a simple skill", () => {
    const skills: Skill[] = [
      { id: "lint", body: "Use eslint." },
    ];
    const hash = computeSkillsHash(skills);
    assert.equal(hash, sha256('[{"body":"Use eslint.","id":"lint"}]'));
  });

  it("sorts skills by id", () => {
    const skills: Skill[] = [
      { id: "deploy", body: "Run deploy." },
      { id: "build", body: "Run build." },
    ];
    const hash = computeSkillsHash(skills);
    const expected = sha256('[{"body":"Run build.","id":"build"},{"body":"Run deploy.","id":"deploy"}]');
    assert.equal(hash, expected);
  });

  it("sorts globs within a skill", () => {
    const skills: Skill[] = [
      { id: "style", body: "Format.", globs: ["*.ts", "*.js"] },
    ];
    const hash = computeSkillsHash(skills);
    // globs sorted: ["*.js", "*.ts"]
    assert.equal(hash, sha256('[{"body":"Format.","globs":["*.js","*.ts"],"id":"style"}]'));
  });

  it("omits empty/undefined optional fields", () => {
    const skills: Skill[] = [
      { id: "test", body: "Test.", title: undefined, description: "" },
    ];
    const hash = computeSkillsHash(skills);
    assert.equal(hash, sha256('[{"body":"Test.","id":"test"}]'));
  });

  it("includes alwaysApply when set", () => {
    const skills: Skill[] = [
      { id: "format", body: "Format code.", alwaysApply: true },
    ];
    const hash = computeSkillsHash(skills);
    assert.equal(hash, sha256('[{"alwaysApply":true,"body":"Format code.","id":"format"}]'));
  });

  it("includes userInvocable when set", () => {
    const skills: Skill[] = [
      { id: "search", body: "Search code.", userInvocable: true },
    ];
    const hash = computeSkillsHash(skills);
    assert.equal(hash, sha256('[{"body":"Search code.","id":"search","userInvocable":true}]'));
  });

  it("skips source-referenced bodies", () => {
    const skills: Skill[] = [
      { id: "external", body: { source: "./rules.md" } },
    ];
    const hash = computeSkillsHash(skills);
    // body is an object (source ref), so it's omitted; only id remains
    assert.equal(hash, sha256('[{"id":"external"}]'));
  });

  it("omits empty globs array", () => {
    const skills: Skill[] = [
      { id: "test", body: "Test.", globs: [] },
    ];
    const hash = computeSkillsHash(skills);
    assert.equal(hash, sha256('[{"body":"Test.","id":"test"}]'));
  });
});

describe("computeKnowledgeHash", () => {
  it("returns SHA-256 of empty string for undefined knowledge", () => {
    const hash = computeKnowledgeHash(undefined);
    assert.equal(hash, HASH_EMPTY_STRING);
    assert.equal(hash, sha256(""));
  });

  it("returns SHA-256 of empty string for empty string knowledge", () => {
    const hash = computeKnowledgeHash("");
    assert.equal(hash, HASH_EMPTY_STRING);
  });

  it("normalizes trailing newline", () => {
    const hash1 = computeKnowledgeHash("hello");
    const hash2 = computeKnowledgeHash("hello\n");
    const hash3 = computeKnowledgeHash("hello\n\n");
    assert.equal(hash1, hash2);
    assert.equal(hash1, hash3);
    assert.equal(hash1, sha256("hello\n"));
  });

  it("preserves content differences", () => {
    const hash1 = computeKnowledgeHash("fact one");
    const hash2 = computeKnowledgeHash("fact two");
    assert.notEqual(hash1, hash2);
  });

  it("is deterministic", () => {
    const hash1 = computeKnowledgeHash("# Knowledge\n\n- item 1\n- item 2\n");
    const hash2 = computeKnowledgeHash("# Knowledge\n\n- item 1\n- item 2\n");
    assert.equal(hash1, hash2);
  });
});

describe("computeFullHash", () => {
  it("hashes the concatenation of three hashes", () => {
    const mh = "aaa";
    const sh = "bbb";
    const kh = "ccc";
    const expected = sha256("aaa:bbb:ccc");
    assert.equal(computeFullHash(mh, sh, kh), expected);
  });

  it("uses actual component hashes correctly", () => {
    const membersHash = computeMembersHash([]);
    const skillsHash = computeSkillsHash([]);
    const knowledgeHash = computeKnowledgeHash(undefined);
    const fullHash = computeFullHash(membersHash, skillsHash, knowledgeHash);
    const expected = sha256(`${HASH_EMPTY_ARRAY}:${HASH_EMPTY_ARRAY}:${HASH_EMPTY_STRING}`);
    assert.equal(fullHash, expected);
  });
});

describe("computeTeamHashes", () => {
  it("computes all hashes for an empty team", () => {
    const team: TeamDefinition = { name: "empty", members: [] };
    const state = computeTeamHashes(team);
    assert.equal(state.membersHash, HASH_EMPTY_ARRAY);
    assert.equal(state.skillsHash, HASH_EMPTY_ARRAY);
    assert.equal(state.knowledgeHash, HASH_EMPTY_STRING);
    assert.equal(state.hash, sha256(`${HASH_EMPTY_ARRAY}:${HASH_EMPTY_ARRAY}:${HASH_EMPTY_STRING}`));
  });

  it("computes hashes for a team with members, skills, and knowledge", () => {
    const team: TeamDefinition = {
      name: "test-team",
      members: [
        { name: "alice", role: "dev" },
        { name: "bob", role: "qa" },
      ],
      skills: [
        { id: "lint", body: "Use eslint.", alwaysApply: true },
      ],
    };
    const state = computeTeamHashes(team, "shared knowledge\n");

    assert.equal(state.membersHash, computeMembersHash(team.members));
    assert.equal(state.skillsHash, computeSkillsHash(team.skills!));
    assert.equal(state.knowledgeHash, computeKnowledgeHash("shared knowledge\n"));
    assert.equal(state.hash, computeFullHash(state.membersHash, state.skillsHash, state.knowledgeHash));
  });

  it("ignores non-hashable TeamDefinition fields", () => {
    const team1: TeamDefinition = {
      name: "team-a",
      members: [{ name: "alice", role: "dev" }],
      teamId: "id-1",
      relay: "http://example.com",
    };
    const team2: TeamDefinition = {
      name: "team-b",
      members: [{ name: "alice", role: "dev" }],
      teamId: "id-2",
      relay: "http://other.com",
    };
    // Same members, skills, knowledge => same hash, despite different name/teamId/relay
    const state1 = computeTeamHashes(team1);
    const state2 = computeTeamHashes(team2);
    assert.equal(state1.hash, state2.hash);
  });

  it("produces different hashes for different content", () => {
    const team1: TeamDefinition = {
      name: "team",
      members: [{ name: "alice", role: "dev" }],
    };
    const team2: TeamDefinition = {
      name: "team",
      members: [{ name: "alice", role: "qa" }],
    };
    const state1 = computeTeamHashes(team1);
    const state2 = computeTeamHashes(team2);
    assert.notEqual(state1.membersHash, state2.membersHash);
    assert.notEqual(state1.hash, state2.hash);
  });
});

describe("known test vectors", () => {
  it("SHA-256 of [] matches expected", () => {
    assert.equal(sha256("[]"), HASH_EMPTY_ARRAY);
  });

  it("SHA-256 of empty string matches expected", () => {
    assert.equal(sha256(""), HASH_EMPTY_STRING);
  });

  it("computeMembersHash([]) matches SHA-256 of '[]'", () => {
    assert.equal(computeMembersHash([]), sha256("[]"));
  });

  it("computeSkillsHash([]) matches SHA-256 of '[]'", () => {
    assert.equal(computeSkillsHash([]), sha256("[]"));
  });

  it("computeKnowledgeHash(undefined) matches SHA-256 of ''", () => {
    assert.equal(computeKnowledgeHash(undefined), sha256(""));
  });
});
