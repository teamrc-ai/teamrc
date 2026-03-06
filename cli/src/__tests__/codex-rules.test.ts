import { describe, it, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";

describe("Codex adapter", () => {
  let tmpDir: string;
  let origCwd: string;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "tb-codex-"));
    origCwd = process.cwd();
    process.chdir(tmpDir);
  });

  afterEach(() => {
    process.chdir(origCwd);
    fs.rmSync(tmpDir, { recursive: true });
  });

  it("writes native skill directories to skills/", async () => {
    const { CodexAdapter } = await import("../adapters/codex.js");
    const adapter = new CodexAdapter();

    const team = {
      name: "test-team",
      members: [{ name: "architect", role: "design" }],
      skills: [{ id: "skill_search", description: "Search code", body: "Use grep." }],
    };

    adapter.writeTeam(team);

    const skillFile = path.join(tmpDir, "skills", "tb-skill_search", "SKILL.md");
    assert.ok(fs.existsSync(skillFile), "SKILL.md should exist");

    const content = fs.readFileSync(skillFile, "utf-8");
    assert.ok(content.includes("name: tb-skill_search"));
    assert.ok(content.includes("Search code"));
  });

  it("writes team and rules to AGENTS.md", async () => {
    const { CodexAdapter } = await import("../adapters/codex.js");
    const adapter = new CodexAdapter();

    const team = {
      name: "test-team",
      members: [{ name: "architect", role: "design", rules: ["rule_style"] }],
      rules: [{ id: "rule_style", title: "Code Style", body: "Use prettier." }],
    };

    adapter.writeTeam(team);

    const agentsMd = path.join(tmpDir, "AGENTS.md");
    assert.ok(fs.existsSync(agentsMd));

    const content = fs.readFileSync(agentsMd, "utf-8");
    assert.ok(content.includes("test-team"));
    assert.ok(content.includes("architect"));
    assert.ok(content.includes("Code Style"));
    assert.ok(content.includes("Use prettier."));
  });
});
