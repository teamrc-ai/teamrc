import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { remoteTeamToDefinition, type TeamrcTeam } from "../client.js";

describe("remoteTeamToDefinition", () => {
  it("converts a basic remote team to a TeamDefinition", () => {
    const remote: TeamrcTeam = {
      id: "team-1",
      name: "my-team",
      members: [
        { name: "architect", role: "design systems" },
        { name: "coder", role: "write code" },
      ],
    };

    const def = remoteTeamToDefinition(remote);
    assert.equal(def.name, "my-team");
    assert.equal(def.members.length, 2);
    assert.equal(def.members[0].name, "architect");
    assert.equal(def.members[0].role, "design systems");
    assert.equal(def.members[1].name, "coder");
    assert.equal(def.members[1].role, "write code");
  });

  it("includes member skills when present", () => {
    const remote: TeamrcTeam = {
      id: "team-2",
      name: "skills-team",
      members: [
        { name: "agent", role: "helper", skills: ["skill_search", "skill_deploy"] },
      ],
    };

    const def = remoteTeamToDefinition(remote);
    assert.deepEqual(def.members[0].skills, ["skill_search", "skill_deploy"]);
  });

  it("omits skills property when member has no skills", () => {
    const remote: TeamrcTeam = {
      id: "team-3",
      name: "no-skills",
      members: [
        { name: "agent", role: "helper" },
      ],
    };

    const def = remoteTeamToDefinition(remote);
    assert.equal(def.members[0].skills, undefined);
  });

  it("omits skills property when member has empty skills array", () => {
    const remote: TeamrcTeam = {
      id: "team-4",
      name: "empty-skills",
      members: [
        { name: "agent", role: "helper", skills: [] },
      ],
    };

    const def = remoteTeamToDefinition(remote);
    assert.equal(def.members[0].skills, undefined);
  });

  it("filters invalid skill IDs from team skills array", () => {
    const remote: TeamrcTeam = {
      id: "team-5",
      name: "filter-skills",
      members: [{ name: "agent", role: "helper" }],
      skills: [
        { id: "valid_skill", body: "Do valid things." },
        { id: "../path-traversal", body: "Bad skill." },
        { id: "also-valid", body: "Good skill." },
        { id: "has.dots", body: "Bad dots." },
        { id: "", body: "Empty id." },
      ],
    };

    const def = remoteTeamToDefinition(remote);
    assert.ok(def.skills);
    assert.equal(def.skills!.length, 2);
    assert.equal(def.skills![0].id, "valid_skill");
    assert.equal(def.skills![1].id, "also-valid");
  });

  it("omits skills from definition when all team skills are invalid", () => {
    const remote: TeamrcTeam = {
      id: "team-6",
      name: "all-invalid",
      members: [{ name: "agent", role: "helper" }],
      skills: [
        { id: "../bad", body: "Bad." },
        { id: "has/slash", body: "Bad." },
      ],
    };

    const def = remoteTeamToDefinition(remote);
    assert.equal(def.skills, undefined);
  });

  it("omits skills from definition when team has no skills", () => {
    const remote: TeamrcTeam = {
      id: "team-7",
      name: "no-team-skills",
      members: [{ name: "agent", role: "helper" }],
    };

    const def = remoteTeamToDefinition(remote);
    assert.equal(def.skills, undefined);
  });

  it("handles team with empty members array", () => {
    const remote: TeamrcTeam = {
      id: "team-8",
      name: "empty-team",
      members: [],
    };

    const def = remoteTeamToDefinition(remote);
    assert.equal(def.name, "empty-team");
    assert.deepEqual(def.members, []);
  });

  it("preserves valid skill metadata", () => {
    const remote: TeamrcTeam = {
      id: "team-9",
      name: "skill-meta",
      members: [{ name: "agent", role: "helper" }],
      skills: [
        {
          id: "search",
          title: "Code Search",
          description: "Search the codebase",
          alwaysApply: true,
          globs: ["*.ts", "*.js"],
          body: "Use grep to search.",
        },
      ],
    };

    const def = remoteTeamToDefinition(remote);
    assert.ok(def.skills);
    assert.equal(def.skills![0].id, "search");
    assert.equal(def.skills![0].title, "Code Search");
    assert.equal(def.skills![0].description, "Search the codebase");
    assert.equal(def.skills![0].alwaysApply, true);
    assert.deepEqual(def.skills![0].globs, ["*.ts", "*.js"]);
    assert.equal(def.skills![0].body, "Use grep to search.");
  });

  it("ignores platform field on members (not part of TeamDefinition)", () => {
    const remote: TeamrcTeam = {
      id: "team-10",
      name: "platform-team",
      members: [
        { name: "agent", role: "helper", platform: "claude-code" },
      ],
    };

    const def = remoteTeamToDefinition(remote);
    // The converted definition should not have platform on members
    assert.equal((def.members[0] as Record<string, unknown>)["platform"], undefined);
  });
});
