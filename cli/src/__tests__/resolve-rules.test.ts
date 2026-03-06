import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { resolveAgentRules, resolveAgentSkills } from "../resolve-rules.js";
import type { TeamDefinition } from "../adapters/base.js";

const team: TeamDefinition = {
  name: "test-team",
  members: [
    { name: "arch", role: "architect", rules: ["rule_style", "rule_security"], skills: ["skill_search"] },
    { name: "coder", role: "coder" },
  ],
  rules: [
    { id: "rule_style", title: "Code Style", body: "Use prettier." },
    { id: "rule_security", body: "Validate all inputs." },
  ],
  skills: [
    { id: "skill_search", description: "Search code", body: "Use grep." },
  ],
};

describe("resolveAgentRules", () => {
  it("resolves referenced rules for an agent", () => {
    const rules = resolveAgentRules(team.members[0], team);
    assert.equal(rules.length, 2);
    assert.equal(rules[0].id, "rule_style");
    assert.equal(rules[0].body, "Use prettier.");
    assert.equal(rules[1].id, "rule_security");
  });

  it("returns empty array when agent has no rules", () => {
    const rules = resolveAgentRules(team.members[1], team);
    assert.deepEqual(rules, []);
  });

  it("skips unknown rule ids", () => {
    const agent = { name: "x", role: "y", rules: ["rule_style", "nonexistent"] };
    const rules = resolveAgentRules(agent, team);
    assert.equal(rules.length, 1);
    assert.equal(rules[0].id, "rule_style");
  });
});

describe("resolveAgentSkills", () => {
  it("resolves referenced skills for an agent", () => {
    const skills = resolveAgentSkills(team.members[0], team);
    assert.equal(skills.length, 1);
    assert.equal(skills[0].id, "skill_search");
    assert.equal(skills[0].body, "Use grep.");
  });

  it("returns empty array when agent has no skills", () => {
    const skills = resolveAgentSkills(team.members[1], team);
    assert.deepEqual(skills, []);
  });
});
