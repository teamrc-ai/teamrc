import { describe, it } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";
import { createTeamTasksSkill, TEAM_TASKS_SKILL_ID, filterActiveMembers, type TeamDefinition } from "../adapters/base.js";
import { readLocalYaml, writeLocalYaml } from "../team-yaml.js";

describe("team tasks skill", () => {
  it("creates skill with correct ID", () => {
    const skill = createTeamTasksSkill();
    assert.equal(skill.id, TEAM_TASKS_SKILL_ID);
  });

  it("has alwaysApply set", () => {
    const skill = createTeamTasksSkill();
    assert.equal(skill.alwaysApply, true);
  });

  it("body contains task commands", () => {
    const skill = createTeamTasksSkill();
    assert.ok(typeof skill.body === "string");
    assert.ok(skill.body.includes("teamrc task list --mine"));
    assert.ok(skill.body.includes("teamrc task claim"));
    assert.ok(skill.body.includes("teamrc task done"));
    assert.ok(skill.body.includes("teamrc task create"));
  });
});

describe("filterActiveMembers", () => {
  const baseTeam: TeamDefinition = {
    name: "test",
    members: [
      { name: "frontend", role: "frontend dev" },
      { name: "backend", role: "backend dev" },
      { name: "devops", role: "devops engineer" },
    ],
  };

  it("returns team unchanged when activeMembers is not passed", () => {
    const result = filterActiveMembers(baseTeam);
    assert.equal(result.members.length, 3);
  });

  it("returns team unchanged when activeMembers is empty", () => {
    const result = filterActiveMembers(baseTeam, []);
    assert.equal(result.members.length, 3);
  });

  it("filters to only active members", () => {
    const result = filterActiveMembers(baseTeam, ["frontend", "devops"]);
    assert.equal(result.members.length, 2);
    assert.deepEqual(result.members.map((m) => m.name), ["frontend", "devops"]);
  });
});

describe("activeMembers local.yaml roundtrip", () => {
  it("writes and reads activeMembers from local.yaml", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "trc-test-"));
    const localPath = path.join(tmpDir, ".teamrc", "local.yaml");
    writeLocalYaml(localPath, { activeMembers: ["agent1"] });
    const read = readLocalYaml(localPath);
    assert.deepEqual(read.activeMembers, ["agent1"]);
    fs.rmSync(tmpDir, { recursive: true });
  });

  it("returns empty config when file does not exist", () => {
    const read = readLocalYaml("/tmp/nonexistent-trc-local.yaml");
    assert.equal(read.activeMembers, undefined);
  });
});
