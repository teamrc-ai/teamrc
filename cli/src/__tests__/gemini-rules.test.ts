import { describe, it, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";

describe("Gemini CLI adapter", () => {
  let tmpDir: string;
  let origCwd: string;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "tb-gemini-"));
    origCwd = process.cwd();
    process.chdir(tmpDir);
  });

  afterEach(() => {
    process.chdir(origCwd);
    fs.rmSync(tmpDir, { recursive: true });
  });

  it("writes native skill directories to .gemini/skills/", async () => {
    const { GeminiAdapter } = await import("../adapters/gemini.js");
    const adapter = new GeminiAdapter();

    const team = {
      name: "test-team",
      members: [{ name: "architect", role: "design" }],
      skills: [{ id: "skill_search", description: "Search code", body: "Use grep." }],
    };

    adapter.writeTeam(team);

    const skillFile = path.join(tmpDir, ".gemini", "skills", "trc-skill_search", "SKILL.md");
    assert.ok(fs.existsSync(skillFile), "SKILL.md should exist");

    const content = fs.readFileSync(skillFile, "utf-8");
    assert.ok(content.includes("name: trc-skill_search"));
    assert.ok(content.includes("Search code"));
  });

  it("writes team and rules to GEMINI.md", async () => {
    const { GeminiAdapter } = await import("../adapters/gemini.js");
    const adapter = new GeminiAdapter();

    const team = {
      name: "test-team",
      members: [{ name: "architect", role: "design", rules: ["rule_style"] }],
      rules: [{ id: "rule_style", title: "Code Style", body: "Use prettier." }],
    };

    adapter.writeTeam(team);

    const geminiMd = path.join(tmpDir, "GEMINI.md");
    assert.ok(fs.existsSync(geminiMd));

    const content = fs.readFileSync(geminiMd, "utf-8");
    assert.ok(content.includes("test-team"));
    assert.ok(content.includes("Code Style"));
    assert.ok(content.includes("Use prettier."));
  });
});
