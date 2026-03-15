import { describe, it } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";
import { createTeamTasksSkill, TEAM_TASKS_SKILL_ID, filterActiveMembers, type TeamDefinition } from "../adapters/base.js";
import { readLocalYaml, writeLocalYaml, writeTeamYaml } from "../team-yaml.js";

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

describe("activeMembers local.yaml", () => {
  it("writes and reads activeMembers", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "trc-test-"));
    const localPath = path.join(tmpDir, ".teamrc", "local.yaml");
    writeLocalYaml(localPath, { activeMembers: ["agent1"] });
    const read = readLocalYaml(localPath);
    assert.deepEqual(read.activeMembers, ["agent1"]);
    fs.rmSync(tmpDir, { recursive: true });
  });

  it("roundtrips multiple members", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "trc-test-"));
    const localPath = path.join(tmpDir, ".teamrc", "local.yaml");
    writeLocalYaml(localPath, { activeMembers: ["frontend", "backend", "devops"] });
    const read = readLocalYaml(localPath);
    assert.deepEqual(read.activeMembers, ["frontend", "backend", "devops"]);
    fs.rmSync(tmpDir, { recursive: true });
  });

  it("returns empty config when file does not exist", () => {
    const read = readLocalYaml("/tmp/nonexistent-trc-local.yaml");
    assert.equal(read.activeMembers, undefined);
  });

  it("does not write file when activeMembers is empty", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "trc-test-"));
    const localPath = path.join(tmpDir, ".teamrc", "local.yaml");
    writeLocalYaml(localPath, { activeMembers: [] });
    assert.equal(fs.existsSync(localPath), false);
    fs.rmSync(tmpDir, { recursive: true });
  });

  it("does not write file when activeMembers is undefined", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "trc-test-"));
    const localPath = path.join(tmpDir, ".teamrc", "local.yaml");
    writeLocalYaml(localPath, {});
    assert.equal(fs.existsSync(localPath), false);
    fs.rmSync(tmpDir, { recursive: true });
  });

  it("handles corrupt YAML gracefully", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "trc-test-"));
    const localPath = path.join(tmpDir, "local.yaml");
    fs.writeFileSync(localPath, ": : : not valid yaml [[[");
    const read = readLocalYaml(localPath);
    assert.equal(read.activeMembers, undefined);
    fs.rmSync(tmpDir, { recursive: true });
  });

  it("is not included in .teamrc.yaml output", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "trc-test-"));
    const yamlPath = path.join(tmpDir, ".teamrc.yaml");
    const team: TeamDefinition = {
      name: "test-team",
      members: [{ name: "agent1", role: "dev" }],
    };
    writeTeamYaml(yamlPath, team);
    const content = fs.readFileSync(yamlPath, "utf-8");
    assert.ok(!content.includes("activeMembers"));
    fs.rmSync(tmpDir, { recursive: true });
  });
});
