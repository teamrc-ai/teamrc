import { describe, it, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";
import { readTeamYaml, writeTeamYaml } from "../team-yaml.js";

describe("readTeamYaml", () => {
  let tmpDir: string;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "trc-yaml-"));
  });

  afterEach(() => {
    fs.rmSync(tmpDir, { recursive: true });
  });

  it("returns null when file does not exist", () => {
    const result = readTeamYaml(path.join(tmpDir, ".teamrc.yaml"));
    assert.equal(result, null);
  });

  it("reads a valid YAML file into TeamDefinition", () => {
    const yaml = `name: my-team
members:
  - name: architect
    role: design architecture
  - name: implementer
    role: write code
    soul: "You are a meticulous coder."
`;
    const filePath = path.join(tmpDir, ".teamrc.yaml");
    fs.writeFileSync(filePath, yaml);

    const result = readTeamYaml(filePath);
    assert.ok(result);
    assert.equal(result.name, "my-team");
    assert.equal(result.members.length, 2);
    assert.equal(result.members[0].name, "architect");
    assert.equal(result.members[0].role, "design architecture");
    assert.equal(result.members[1].soul, "You are a meticulous coder.");
  });

  it("handles YAML with no members gracefully", () => {
    const yaml = `name: solo-team\n`;
    const filePath = path.join(tmpDir, ".teamrc.yaml");
    fs.writeFileSync(filePath, yaml);

    const result = readTeamYaml(filePath);
    assert.ok(result);
    assert.equal(result.name, "solo-team");
    assert.deepEqual(result.members, []);
  });
});

describe("writeTeamYaml", () => {
  let tmpDir: string;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "trc-yaml-"));
  });

  afterEach(() => {
    fs.rmSync(tmpDir, { recursive: true });
  });

  it("writes a TeamDefinition to YAML", () => {
    const filePath = path.join(tmpDir, ".teamrc.yaml");
    writeTeamYaml(filePath, {
      name: "my-team",
      members: [
        { name: "architect", role: "design architecture" },
        { name: "implementer", role: "write code", soul: "focused coder" },
      ],
    });

    const content = fs.readFileSync(filePath, "utf-8");
    assert.ok(content.includes("name: my-team"));
    assert.ok(content.includes("architect"));
    assert.ok(content.includes("design architecture"));
    assert.ok(content.includes("focused coder"));
  });

  it("roundtrips correctly", () => {
    const filePath = path.join(tmpDir, ".teamrc.yaml");
    const team = {
      name: "roundtrip-team",
      members: [
        { name: "agent-a", role: "role-a" },
        { name: "agent-b", role: "role-b", soul: "soul text" },
      ],
    };

    writeTeamYaml(filePath, team);
    const result = readTeamYaml(filePath);

    assert.ok(result);
    assert.equal(result.name, team.name);
    assert.equal(result.members.length, 2);
    assert.equal(result.members[0].name, "agent-a");
    assert.equal(result.members[0].role, "role-a");
    assert.equal(result.members[0].soul, undefined);
    assert.equal(result.members[1].soul, "soul text");
  });
});

describe("readTeamYaml with rules and skills", () => {
  let tmpDir: string;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "trc-yaml-"));
  });

  afterEach(() => {
    fs.rmSync(tmpDir, { recursive: true });
  });

  it("parses rules from YAML", () => {
    const yaml = `name: my-team
members:
  - name: architect
    role: design
rules:
  - id: rule_style
    title: Code Style
    body: "Use prettier."
  - id: rule_security
    globs:
      - "*.ts"
    alwaysApply: true
    body: "Validate all inputs."
`;
    const filePath = path.join(tmpDir, ".teamrc.yaml");
    fs.writeFileSync(filePath, yaml);

    const result = readTeamYaml(filePath);
    assert.ok(result);
    assert.equal(result.rules!.length, 2);
    assert.equal(result.rules![0].id, "rule_style");
    assert.equal(result.rules![0].title, "Code Style");
    assert.equal(result.rules![0].body, "Use prettier.");
    assert.deepEqual(result.rules![1].globs, ["*.ts"]);
    assert.equal(result.rules![1].alwaysApply, true);
  });

  it("parses skills from YAML", () => {
    const yaml = `name: my-team
members:
  - name: coder
    role: write code
skills:
  - id: skill_search
    description: Search the codebase
  - id: skill_deploy
    title: Deploy
    description: Deploy to production
    body: "Run npm deploy."
`;
    const filePath = path.join(tmpDir, ".teamrc.yaml");
    fs.writeFileSync(filePath, yaml);

    const result = readTeamYaml(filePath);
    assert.ok(result);
    assert.equal(result.skills!.length, 2);
    assert.equal(result.skills![0].id, "skill_search");
    assert.equal(result.skills![0].description, "Search the codebase");
    assert.equal(result.skills![1].body, "Run npm deploy.");
  });

  it("parses agent rule/skill references", () => {
    const yaml = `name: my-team
members:
  - name: architect
    role: design
    rules:
      - rule_style
    skills:
      - skill_search
rules:
  - id: rule_style
    body: "Use prettier."
skills:
  - id: skill_search
    description: Search code
`;
    const filePath = path.join(tmpDir, ".teamrc.yaml");
    fs.writeFileSync(filePath, yaml);

    const result = readTeamYaml(filePath);
    assert.ok(result);
    assert.deepEqual(result.members[0].rules, ["rule_style"]);
    assert.deepEqual(result.members[0].skills, ["skill_search"]);
  });

  it("works without rules or skills (backward compat)", () => {
    const yaml = `name: old-team
members:
  - name: agent
    role: helper
`;
    const filePath = path.join(tmpDir, ".teamrc.yaml");
    fs.writeFileSync(filePath, yaml);

    const result = readTeamYaml(filePath);
    assert.ok(result);
    assert.deepEqual(result.rules, []);
    assert.deepEqual(result.skills, []);
  });

  it("roundtrips rules and skills through write/read", () => {
    const filePath = path.join(tmpDir, ".teamrc.yaml");
    const team = {
      name: "roundtrip-team",
      members: [{ name: "agent-a", role: "role-a", rules: ["rule_x"], skills: ["skill_y"] }],
      rules: [{ id: "rule_x", body: "Do X." }],
      skills: [{ id: "skill_y", description: "Does Y" }],
    };

    writeTeamYaml(filePath, team);
    const result = readTeamYaml(filePath);

    assert.ok(result);
    assert.equal(result.rules!.length, 1);
    assert.equal(result.rules![0].id, "rule_x");
    assert.equal(result.skills!.length, 1);
    assert.equal(result.skills![0].id, "skill_y");
    assert.deepEqual(result.members[0].rules, ["rule_x"]);
  });
});
