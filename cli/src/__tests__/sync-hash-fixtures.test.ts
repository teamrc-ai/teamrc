/**
 * Cross-language integration tests for canonical JSON hashing.
 *
 * These tests read shared fixture vectors from test-fixtures/canonical-hash-vectors.json
 * and verify that the TypeScript implementation produces identical results.
 * The same fixture file is tested by the Elixir implementation in
 * teamrc/test/teamrc/content_hash_fixture_test.exs.
 *
 * If either implementation changes its output, these tests catch the divergence.
 */
import { describe, it } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import {
  computeMembersHash,
  computeSkillsHash,
  computeKnowledgeHash,
  computeFullHash,
} from "../sync-hash.js";
import type { TeamMember, Skill } from "../adapters/base.js";

interface MemberVector {
  description: string;
  members: TeamMember[];
  expectedCanonicalJson: string;
  expectedHash: string;
}

interface SkillVector {
  description: string;
  skills: Skill[];
  expectedCanonicalJson: string;
  expectedHash: string;
}

interface KnowledgeVector {
  description: string;
  knowledge: string | null;
  expectedNormalizedInput: string;
  expectedHash: string;
}

interface FullHashVector {
  description: string;
  membersHash: string;
  skillsHash: string;
  knowledgeHash: string;
  expectedInput: string;
  expectedHash: string;
}

interface FixtureFile {
  _comment: string;
  memberVectors: MemberVector[];
  skillVectors: SkillVector[];
  knowledgeVectors: KnowledgeVector[];
  fullHashVectors: FullHashVector[];
}

// Load fixture file relative to the repo root (cli/src/__tests__ -> ../../../test-fixtures)
const fixtureDir = path.resolve(path.dirname(new URL(import.meta.url).pathname), "..", "..", "..", "test-fixtures");
const fixturePath = path.join(fixtureDir, "canonical-hash-vectors.json");
const fixtures: FixtureFile = JSON.parse(fs.readFileSync(fixturePath, "utf-8"));

describe("cross-language fixture: member vectors", () => {
  for (const vector of fixtures.memberVectors) {
    it(vector.description, () => {
      const hash = computeMembersHash(vector.members);
      assert.equal(
        hash,
        vector.expectedHash,
        `Members hash mismatch for "${vector.description}".\nExpected: ${vector.expectedHash}\nGot:      ${hash}`,
      );
    });
  }
});

describe("cross-language fixture: skill vectors", () => {
  for (const vector of fixtures.skillVectors) {
    it(vector.description, () => {
      const hash = computeSkillsHash(vector.skills);
      assert.equal(
        hash,
        vector.expectedHash,
        `Skills hash mismatch for "${vector.description}".\nExpected: ${vector.expectedHash}\nGot:      ${hash}`,
      );
    });
  }
});

describe("cross-language fixture: knowledge vectors", () => {
  for (const vector of fixtures.knowledgeVectors) {
    it(vector.description, () => {
      const knowledge = vector.knowledge === null ? undefined : vector.knowledge;
      const hash = computeKnowledgeHash(knowledge);
      assert.equal(
        hash,
        vector.expectedHash,
        `Knowledge hash mismatch for "${vector.description}".\nExpected: ${vector.expectedHash}\nGot:      ${hash}`,
      );
    });
  }
});

describe("cross-language fixture: full hash vectors", () => {
  for (const vector of fixtures.fullHashVectors) {
    it(vector.description, () => {
      const hash = computeFullHash(vector.membersHash, vector.skillsHash, vector.knowledgeHash);
      assert.equal(
        hash,
        vector.expectedHash,
        `Full hash mismatch for "${vector.description}".\nExpected: ${vector.expectedHash}\nGot:      ${hash}`,
      );
    });
  }
});
