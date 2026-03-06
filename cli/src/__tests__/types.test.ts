import { describe, it } from "node:test";
import assert from "node:assert/strict";
import type { Rule, Skill, TeamDefinition } from "../adapters/base.js";

describe("extended types", () => {
  it("TeamDefinition accepts rules and skills", () => {
    const team: TeamDefinition = {
      name: "test-team",
      members: [{ name: "agent-a", role: "coder" }],
      rules: [
        { id: "rule_style", body: "Use prettier." },
        { id: "rule_security", title: "Security", globs: ["*.ts"], alwaysApply: true, body: "Validate all inputs." },
      ],
      skills: [
        { id: "skill_search", description: "Search code" },
        { id: "skill_deploy", title: "Deploy", description: "Deploy to prod", body: "Run npm deploy." },
      ],
    };
    assert.equal(team.rules!.length, 2);
    assert.equal(team.skills!.length, 2);
    assert.equal(team.rules![1].globs![0], "*.ts");
  });

  it("TeamDefinition works without rules and skills (backward compat)", () => {
    const team: TeamDefinition = {
      name: "old-team",
      members: [{ name: "agent-b", role: "reviewer" }],
    };
    assert.equal(team.rules, undefined);
    assert.equal(team.skills, undefined);
  });

  it("agent members can reference rules and skills by id", () => {
    const team: TeamDefinition = {
      name: "ref-team",
      members: [{
        name: "arch",
        role: "architect",
        rules: ["rule_style"],
        skills: ["skill_search"],
      }],
    };
    assert.deepEqual(team.members[0].rules, ["rule_style"]);
    assert.deepEqual(team.members[0].skills, ["skill_search"]);
  });
});
