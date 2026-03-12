import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { resolveAgentSkills, type TeamDefinition } from "../adapters/base.js";

const team: TeamDefinition = {
  name: "test-team",
  members: [
    { name: "arch", role: "architect", skills: ["skill_search", "skill_style"] },
    { name: "coder", role: "coder" },
  ],
  skills: [
    { id: "skill_style", title: "Code Style", alwaysApply: true, body: "Use prettier." },
    { id: "skill_search", description: "Search code", body: "Use grep." },
  ],
};

describe("resolveAgentSkills", () => {
  it("resolves referenced skills for an agent", () => {
    const skills = resolveAgentSkills(team.members[0], team);
    assert.equal(skills.length, 2);
    assert.equal(skills[0].id, "skill_search");
    assert.equal(skills[0].body, "Use grep.");
    assert.equal(skills[1].id, "skill_style");
  });

  it("returns empty when agent has no skills assigned", () => {
    const skills = resolveAgentSkills(team.members[1], team);
    assert.deepEqual(skills, []);
  });

  it("skips unknown skill ids", () => {
    const agent = { name: "x", role: "y", skills: ["skill_search", "nonexistent"] };
    const skills = resolveAgentSkills(agent, team);
    assert.equal(skills.length, 1);
    assert.equal(skills[0].id, "skill_search");
  });
});
