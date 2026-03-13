import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { generateTeamSuffix, generateTeamName } from "../names.js";
import { validateTeamName } from "../team-yaml.js";
import { slugify } from "../adapters/base.js";

// ---------------------------------------------------------------------------
// generateTeamSuffix
// ---------------------------------------------------------------------------

describe("generateTeamSuffix", () => {
  it("returns format <word>-<4hex>", () => {
    const suffix = generateTeamSuffix();
    assert.match(suffix, /^[a-z]+-[0-9a-f]{4}$/);
  });

  it("generates different suffixes on successive calls", () => {
    const suffixes = new Set<string>();
    for (let i = 0; i < 20; i++) {
      suffixes.add(generateTeamSuffix());
    }
    // With 2 bytes of hex entropy, collisions in 20 tries are extremely unlikely
    assert.ok(suffixes.size > 1, "expected multiple unique suffixes");
  });
});

// ---------------------------------------------------------------------------
// generateTeamName
// ---------------------------------------------------------------------------

describe("generateTeamName", () => {
  it("returns format <base>-<word>-<4hex>", () => {
    const name = generateTeamName("my-team");
    assert.match(name, /^my-team-[a-z]+-[0-9a-f]{4}$/);
  });

  it("works with various base names", () => {
    const name = generateTeamName("fullstack");
    assert.match(name, /^fullstack-[a-z]+-[0-9a-f]{4}$/);
  });

  it("generated names pass validateTeamName", () => {
    for (let i = 0; i < 50; i++) {
      const name = generateTeamName("my-team");
      // Should not throw
      validateTeamName(name);
    }
  });

  it("generated names are within 64-char limit", () => {
    // Worst case: long base name + longest word (7 chars "crimson") + 4 hex + 2 hyphens = 13 extra chars
    for (let i = 0; i < 100; i++) {
      const name = generateTeamName("my-team");
      assert.ok(name.length <= 64, `name too long: "${name}" (${name.length} chars)`);
    }
  });

  it("generated names slugify cleanly (no change after slugify)", () => {
    for (let i = 0; i < 50; i++) {
      const name = generateTeamName("my-team");
      assert.equal(slugify(name), name, `slugify changed "${name}" to "${slugify(name)}"`);
    }
  });

  it("100 generated names are all unique", () => {
    const names = new Set<string>();
    for (let i = 0; i < 100; i++) {
      names.add(generateTeamName("my-team"));
    }
    assert.equal(names.size, 100, `expected 100 unique names, got ${names.size}`);
  });
});
