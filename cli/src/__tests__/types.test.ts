import { describe, it } from "node:test";
import assert from "node:assert/strict";
import type { Skill, TeamDefinition } from "../adapters/base.js";

describe("extended types", () => {
  it("TeamDefinition accepts skills with alwaysApply and globs", () => {
    const team: TeamDefinition = {
      name: "test-team",
      members: [{ name: "agent-a", role: "coder" }],
      skills: [
        { id: "skill_style", alwaysApply: true, body: "Use prettier." },
        { id: "skill_security", title: "Security", globs: ["*.ts"], alwaysApply: true, body: "Validate all inputs." },
        { id: "skill_search", description: "Search code", body: "Use grep." },
        { id: "skill_deploy", title: "Deploy", description: "Deploy to prod", body: "Run npm deploy." },
      ],
    };
    assert.equal(team.skills!.length, 4);
    assert.equal(team.skills![1].globs![0], "*.ts");
    assert.equal(team.skills![1].alwaysApply, true);
  });

  it("TeamDefinition works without skills", () => {
    const team: TeamDefinition = {
      name: "old-team",
      members: [{ name: "agent-b", role: "reviewer" }],
    };
    assert.equal(team.skills, undefined);
  });

  it("agent members can reference skills by id", () => {
    const team: TeamDefinition = {
      name: "ref-team",
      members: [{
        name: "arch",
        role: "architect",
        skills: ["skill_search"],
      }],
    };
    assert.deepEqual(team.members[0].skills, ["skill_search"]);
  });
});
