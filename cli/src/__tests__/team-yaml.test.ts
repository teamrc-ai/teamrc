import { describe, it, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";
import { readTeamYaml, writeTeamYaml, GLOBAL_TEAM_YAML, resolveBody } from "../team-yaml.js";
import type { TeamDefinition } from "../adapters/base.js";

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

  it("does not write syncHash fields to YAML", () => {
    const filePath = path.join(tmpDir, ".teamrc.yaml");
    writeTeamYaml(filePath, {
      name: "no-hash-team",
      members: [{ name: "agent", role: "helper" }],
    });

    const content = fs.readFileSync(filePath, "utf-8");
    assert.ok(!content.includes("syncHash"), "YAML should not contain syncHash");
    assert.ok(!content.includes("syncHashMembers"), "YAML should not contain syncHashMembers");
    assert.ok(!content.includes("syncHashSkills"), "YAML should not contain syncHashSkills");
    assert.ok(!content.includes("syncHashKnowledge"), "YAML should not contain syncHashKnowledge");
  });

  it("ignores legacy syncHash fields in YAML when reading", () => {
    const filePath = path.join(tmpDir, ".teamrc.yaml");
    fs.writeFileSync(filePath, `name: legacy-team
syncHash: old-hash
syncHashMembers: old-m
syncHashSkills: old-s
syncHashKnowledge: old-k
members:
  - name: agent
    role: helper
`);

    const result = readTeamYaml(filePath);
    assert.ok(result);
    assert.equal(result.name, "legacy-team");
    // syncHash fields should not be on the TeamDefinition
    assert.equal((result as Record<string, unknown>).syncHash, undefined);
    assert.equal((result as Record<string, unknown>).syncHashMembers, undefined);
  });
});

describe("readTeamYaml with skills", () => {
  let tmpDir: string;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "trc-yaml-"));
  });

  afterEach(() => {
    fs.rmSync(tmpDir, { recursive: true });
  });

  it("parses skills from YAML", () => {
    const yaml = `name: my-team
members:
  - name: coder
    role: write code
skills:
  - id: skill_search
    description: Search the codebase
    body: "Search it."
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

  it("parses skills with alwaysApply and globs", () => {
    const yaml = `name: my-team
members:
  - name: architect
    role: design
skills:
  - id: skill_style
    title: Code Style
    alwaysApply: true
    body: "Use prettier."
  - id: skill_security
    globs:
      - "*.ts"
    body: "Validate all inputs."
`;
    const filePath = path.join(tmpDir, ".teamrc.yaml");
    fs.writeFileSync(filePath, yaml);

    const result = readTeamYaml(filePath);
    assert.ok(result);
    assert.equal(result.skills!.length, 2);
    assert.equal(result.skills![0].id, "skill_style");
    assert.equal(result.skills![0].alwaysApply, true);
    assert.equal(result.skills![0].body, "Use prettier.");
    assert.deepEqual(result.skills![1].globs, ["*.ts"]);
  });

  it("parses agent skill references", () => {
    const yaml = `name: my-team
members:
  - name: architect
    role: design
    skills:
      - skill_search
skills:
  - id: skill_search
    description: Search code
    body: "Search it."
`;
    const filePath = path.join(tmpDir, ".teamrc.yaml");
    fs.writeFileSync(filePath, yaml);

    const result = readTeamYaml(filePath);
    assert.ok(result);
    assert.deepEqual(result.members[0].skills, ["skill_search"]);
  });

  it("works without skills", () => {
    const yaml = `name: old-team
members:
  - name: agent
    role: helper
`;
    const filePath = path.join(tmpDir, ".teamrc.yaml");
    fs.writeFileSync(filePath, yaml);

    const result = readTeamYaml(filePath);
    assert.ok(result);
    assert.deepEqual(result.skills, []);
  });

  it("roundtrips skills through write/read", () => {
    const filePath = path.join(tmpDir, ".teamrc.yaml");
    const team = {
      name: "roundtrip-team",
      members: [{ name: "agent-a", role: "role-a", skills: ["skill_y"] }],
      skills: [{ id: "skill_y", description: "Does Y", alwaysApply: true, body: "Do Y." }],
    };

    writeTeamYaml(filePath, team);
    const result = readTeamYaml(filePath);

    assert.ok(result);
    assert.equal(result.skills!.length, 1);
    assert.equal(result.skills![0].id, "skill_y");
    assert.equal(result.skills![0].alwaysApply, true);
    assert.deepEqual(result.members[0].skills, ["skill_y"]);
  });
});

describe("global team YAML", () => {
  it("GLOBAL_TEAM_YAML points to ~/.teamrc/team.yaml", () => {
    assert.ok(GLOBAL_TEAM_YAML.includes(".teamrc"));
    assert.ok(GLOBAL_TEAM_YAML.endsWith("team.yaml"));
  });

  it("can read and write global team YAML", () => {
    const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "global-yaml-"));
    const yamlPath = path.join(tmpDir, "team.yaml");

    const team: TeamDefinition = {
      name: "global-test",
      members: [{ name: "agent", role: "helper" }],
      teamId: "abc-123",
      relay: "http://localhost:4000",
      platforms: ["claude-code"],
    };

    writeTeamYaml(yamlPath, team);
    const read = readTeamYaml(yamlPath);

    assert.equal(read?.name, "global-test");
    assert.equal(read?.teamId, "abc-123");
    assert.equal(read?.members.length, 1);

    fs.rmSync(tmpDir, { recursive: true, force: true });
  });
});

describe("resolveBody", () => {
  let tmpDir: string;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "trc-resolve-"));
  });

  afterEach(() => {
    fs.rmSync(tmpDir, { recursive: true });
  });

  it("returns empty string for undefined", () => {
    assert.equal(resolveBody(undefined, tmpDir), "");
  });

  it("returns string body as-is", () => {
    assert.equal(resolveBody("hello world", tmpDir), "hello world");
  });

  it("reads file from source", () => {
    fs.writeFileSync(path.join(tmpDir, "rules.md"), "Be careful.");
    const result = resolveBody({ source: "./rules.md" }, tmpDir);
    assert.equal(result, "Be careful.");
  });

  it("returns empty string for missing source file", () => {
    const result = resolveBody({ source: "./nonexistent.md" }, tmpDir);
    assert.equal(result, "");
  });

  it("blocks path traversal", () => {
    assert.throws(
      () => resolveBody({ source: "../../etc/passwd" }, tmpDir),
      /Path traversal blocked/,
    );
  });

  it("handles concurrent deletion without TOCTOU race (no existsSync pre-check)", () => {
    // The fix removes existsSync and uses try/catch on realpathSync,
    // so a missing file returns "" without a race window.
    const result = resolveBody({ source: "./deleted-between-check-and-read.md" }, tmpDir);
    assert.equal(result, "");
  });
});

describe("readTeamYaml limit enforcement", () => {
  let tmpDir: string;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "trc-yaml-limits-"));
  });

  afterEach(() => {
    fs.rmSync(tmpDir, { recursive: true });
  });

  it("throws when YAML exceeds MAX_YAML_SIZE (256 KB)", () => {
    const filePath = path.join(tmpDir, ".teamrc.yaml");
    // Create a file larger than 256 KB
    const bigContent = "name: big-team\nmembers: []\n# " + "x".repeat(256 * 1024);
    fs.writeFileSync(filePath, bigContent);

    assert.throws(
      () => readTeamYaml(filePath),
      /exceeds maximum size/,
    );
  });

  it("throws when team has too many members (> 20)", () => {
    const filePath = path.join(tmpDir, ".teamrc.yaml");
    const members = Array.from({ length: 21 }, (_, i) => `  - name: agent${i}\n    role: helper`);
    const yaml = `name: big-team\nmembers:\n${members.join("\n")}\n`;
    fs.writeFileSync(filePath, yaml);

    assert.throws(
      () => readTeamYaml(filePath),
      /at most 20 entries/,
    );
  });

  it("throws when team has too many skills (> 50)", () => {
    const filePath = path.join(tmpDir, ".teamrc.yaml");
    const skills = Array.from({ length: 51 }, (_, i) => `  - id: skill${i}\n    body: "do stuff"`);
    const yaml = `name: skill-team\nmembers:\n  - name: agent\n    role: helper\nskills:\n${skills.join("\n")}\n`;
    fs.writeFileSync(filePath, yaml);

    assert.throws(
      () => readTeamYaml(filePath),
      /at most 50 entries/,
    );
  });

  it("accepts team at exactly MAX_MEMBERS (20)", () => {
    const filePath = path.join(tmpDir, ".teamrc.yaml");
    const members = Array.from({ length: 20 }, (_, i) => `  - name: agent${i}\n    role: helper`);
    const yaml = `name: full-team\nmembers:\n${members.join("\n")}\n`;
    fs.writeFileSync(filePath, yaml);

    const result = readTeamYaml(filePath);
    assert.ok(result);
    assert.equal(result.members.length, 20);
  });

  it("accepts team at exactly MAX_SKILLS (50)", () => {
    const filePath = path.join(tmpDir, ".teamrc.yaml");
    const skills = Array.from({ length: 50 }, (_, i) => `  - id: skill${i}\n    body: "do stuff"`);
    const yaml = `name: skill-team\nmembers:\n  - name: agent\n    role: helper\nskills:\n${skills.join("\n")}\n`;
    fs.writeFileSync(filePath, yaml);

    const result = readTeamYaml(filePath);
    assert.ok(result);
    assert.equal(result.skills!.length, 50);
  });

  it("throws when member names produce slug collisions", () => {
    const filePath = path.join(tmpDir, ".teamrc.yaml");
    const yaml = `name: collision-team\nmembers:\n  - name: my-agent\n    role: helper\n  - name: my_agent\n    role: reviewer\n`;
    fs.writeFileSync(filePath, yaml);

    assert.throws(
      () => readTeamYaml(filePath),
      /produce the same filename/,
    );
  });

  it("allows members with distinct slugs", () => {
    const filePath = path.join(tmpDir, ".teamrc.yaml");
    const yaml = `name: distinct-team\nmembers:\n  - name: frontend-dev\n    role: helper\n  - name: backend-dev\n    role: reviewer\n`;
    fs.writeFileSync(filePath, yaml);

    const result = readTeamYaml(filePath);
    assert.ok(result);
    assert.equal(result.members.length, 2);
  });

  it("throws when skill IDs produce slug collisions", () => {
    const filePath = path.join(tmpDir, ".teamrc.yaml");
    const yaml = `name: collision-team\nmembers:\n  - name: agent\n    role: helper\nskills:\n  - id: code_review\n    body: "Review code."\n  - id: code-review\n    body: "Also review code."\n`;
    fs.writeFileSync(filePath, yaml);

    assert.throws(
      () => readTeamYaml(filePath),
      /produce the same filename/,
    );
  });

  it("allows skills with distinct slugs", () => {
    const filePath = path.join(tmpDir, ".teamrc.yaml");
    const yaml = `name: distinct-team\nmembers:\n  - name: agent\n    role: helper\nskills:\n  - id: code-review\n    body: "Review code."\n  - id: deploy-prod\n    body: "Deploy to prod."\n`;
    fs.writeFileSync(filePath, yaml);

    const result = readTeamYaml(filePath);
    assert.ok(result);
    assert.equal(result.skills!.length, 2);
  });
});

describe("writeTeamYaml atomic writes", () => {
  let tmpDir: string;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "trc-atomic-"));
  });

  afterEach(() => {
    fs.rmSync(tmpDir, { recursive: true });
  });

  it("writes atomically (no leftover temp files)", () => {
    const filePath = path.join(tmpDir, ".teamrc.yaml");
    writeTeamYaml(filePath, {
      name: "atomic-test",
      members: [{ name: "agent", role: "helper" }],
    });

    // The file should exist and be readable
    const result = readTeamYaml(filePath);
    assert.ok(result);
    assert.equal(result.name, "atomic-test");

    // No temp files should remain
    const files = fs.readdirSync(tmpDir);
    assert.equal(files.length, 1, "only the target file should exist, no temp files");
    assert.equal(files[0], ".teamrc.yaml");
  });

  it("creates parent directories if needed", () => {
    const nested = path.join(tmpDir, "sub", "dir");
    const filePath = path.join(nested, "team.yaml");
    writeTeamYaml(filePath, {
      name: "nested-test",
      members: [{ name: "agent", role: "helper" }],
    });

    const result = readTeamYaml(filePath);
    assert.ok(result);
    assert.equal(result.name, "nested-test");
  });

  it("overwrites existing file atomically", () => {
    const filePath = path.join(tmpDir, ".teamrc.yaml");

    writeTeamYaml(filePath, {
      name: "version-1",
      members: [{ name: "agent-a", role: "role-a" }],
    });

    writeTeamYaml(filePath, {
      name: "version-2",
      members: [{ name: "agent-b", role: "role-b" }],
    });

    const result = readTeamYaml(filePath);
    assert.ok(result);
    assert.equal(result.name, "version-2");
    assert.equal(result.members[0].name, "agent-b");

    // No temp files should remain
    const files = fs.readdirSync(tmpDir);
    assert.equal(files.length, 1);
  });

  it("round-trips disableModelInvocation and argumentHint fields", () => {
    const filePath = path.join(tmpDir, ".teamrc.yaml");
    const team = {
      name: "test",
      members: [{ name: "dev", role: "developer" }],
      skills: [{
        id: "my-cmd",
        description: "A command",
        disableModelInvocation: true,
        argumentHint: "<file>",
        body: "Do things.",
      }],
    };

    writeTeamYaml(filePath, team);
    const result = readTeamYaml(filePath);
    assert.ok(result);
    assert.equal(result.skills!.length, 1);
    const skill = result.skills![0];
    assert.equal(skill.disableModelInvocation, true);
    assert.equal(skill.argumentHint, "<file>");
  });
});
