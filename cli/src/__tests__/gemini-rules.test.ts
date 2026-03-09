import { describe, it, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";

describe("Gemini CLI adapter", () => {
  let tmpDir: string;
  let origCwd: string;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "trc-gemini-"));
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

    adapter.writeTeam(team, "project");

    const skillFile = path.join(tmpDir, ".gemini", "skills", "trc-skill_search", "SKILL.md");
    assert.ok(fs.existsSync(skillFile), "SKILL.md should exist");

    const content = fs.readFileSync(skillFile, "utf-8");
    assert.ok(content.includes("name: trc-skill_search"));
    assert.ok(content.includes("Search code"));
  });

  it("writes individual agent files to .gemini/agents/", async () => {
    const { GeminiAdapter } = await import("../adapters/gemini.js");
    const adapter = new GeminiAdapter();

    const team = {
      name: "test-team",
      members: [
        { name: "architect", role: "system design", skills: ["skill_style"] },
        { name: "developer", role: "implementation" },
      ],
      skills: [{ id: "skill_style", title: "Code Style", alwaysApply: true, body: "Use prettier." }],
    };

    adapter.writeTeam(team, "project");

    // Check agent files exist
    const agentDir = path.join(tmpDir, ".gemini", "agents");
    assert.ok(fs.existsSync(path.join(agentDir, "trc-architect.md")));
    assert.ok(fs.existsSync(path.join(agentDir, "trc-developer.md")));

    // Check architect has skills
    const architectContent = fs.readFileSync(path.join(agentDir, "trc-architect.md"), "utf-8");
    assert.ok(architectContent.includes('name: "trc-architect"'));
    assert.ok(architectContent.includes('description: "system design"'));
    assert.ok(architectContent.includes("## Skills"));
    assert.ok(architectContent.includes("Code Style"));
    assert.ok(architectContent.includes("Use prettier."));

    // Check developer has no skills section
    const devContent = fs.readFileSync(path.join(agentDir, "trc-developer.md"), "utf-8");
    assert.ok(devContent.includes('name: "trc-developer"'));
    assert.ok(!devContent.includes("## Skills"));
  });

  it("writes GEMINI.md with team knowledge marker block", async () => {
    const { GeminiAdapter } = await import("../adapters/gemini.js");
    const adapter = new GeminiAdapter();

    const team = {
      name: "test-team",
      members: [{ name: "architect", role: "design" }],
    };

    adapter.writeTeam(team, "project");

    const geminiMd = path.join(tmpDir, "GEMINI.md");
    assert.ok(fs.existsSync(geminiMd));

    const content = fs.readFileSync(geminiMd, "utf-8");
    assert.ok(content.includes("<!-- teamrc -->"));
    assert.ok(content.includes("<!-- /teamrc -->"));
    assert.ok(content.includes("test-team"));
    assert.ok(content.includes("architect"));
    assert.ok(!content.includes("## Rules"));
  });

  it("readTeam parses agent files from .gemini/agents/", async () => {
    const { GeminiAdapter } = await import("../adapters/gemini.js");
    const adapter = new GeminiAdapter();

    // Write a team first
    const team = {
      name: "test-team",
      members: [
        { name: "architect", role: "system design" },
        { name: "developer", role: "implementation" },
      ],
    };

    adapter.writeTeam(team, "project");

    // Read it back
    const result = adapter.readTeam();
    assert.ok(result !== null);
    assert.equal(result!.name, "test-team");
    assert.equal(result!.members.length, 2);
    const names = result!.members.map((m) => m.name).sort();
    assert.deepEqual(names, ["architect", "developer"]);
  });

  it("cleans old agent files before writing new ones", async () => {
    const { GeminiAdapter } = await import("../adapters/gemini.js");
    const adapter = new GeminiAdapter();

    // Write initial team
    adapter.writeTeam({
      name: "test-team",
      members: [{ name: "old-agent", role: "legacy" }],
    }, "project");

    const agentDir = path.join(tmpDir, ".gemini", "agents");
    assert.ok(fs.existsSync(path.join(agentDir, "trc-old-agent.md")));

    // Write new team
    adapter.writeTeam({
      name: "test-team",
      members: [{ name: "new-agent", role: "modern" }],
    }, "project");

    // Old agent should be gone
    assert.ok(!fs.existsSync(path.join(agentDir, "trc-old-agent.md")));
    assert.ok(fs.existsSync(path.join(agentDir, "trc-new-agent.md")));
  });

  it("supports knowledge read/write/append", async () => {
    const { GeminiAdapter } = await import("../adapters/gemini.js");
    const adapter = new GeminiAdapter();

    // Initially empty
    assert.equal(adapter.readKnowledge(), "");

    // Write
    adapter.writeKnowledge("initial knowledge");
    assert.equal(adapter.readKnowledge(), "initial knowledge");

    // Append
    adapter.appendKnowledge(["finding one", "finding two"]);
    const knowledge = adapter.readKnowledge();
    assert.ok(knowledge.includes("finding one"));
    assert.ok(knowledge.includes("finding two"));
  });

  it("uninstall cleans agent files, skills, knowledge, and GEMINI.md", async () => {
    const { GeminiAdapter } = await import("../adapters/gemini.js");
    const adapter = new GeminiAdapter();

    adapter.writeTeam({
      name: "test-team",
      members: [{ name: "architect", role: "design" }],
      skills: [{ id: "skill_search", description: "Search code", body: "Use grep." }],
    }, "project");
    adapter.writeKnowledge("some knowledge");

    const actions = adapter.uninstall();
    assert.ok(actions.length > 0);

    // Agent files should be cleaned
    const agentDir = path.join(tmpDir, ".gemini", "agents");
    const remaining = fs.existsSync(agentDir)
      ? fs.readdirSync(agentDir).filter((f) => f.startsWith("trc-"))
      : [];
    assert.equal(remaining.length, 0);

    // Skill dirs should be cleaned
    const skillDir = path.join(tmpDir, ".gemini", "skills");
    const remainingSkills = fs.existsSync(skillDir)
      ? fs.readdirSync(skillDir).filter((f) => f.startsWith("trc-"))
      : [];
    assert.equal(remainingSkills.length, 0);
  });

  it("supportsSync is true", async () => {
    const { GeminiAdapter } = await import("../adapters/gemini.js");
    const adapter = new GeminiAdapter();
    assert.equal(adapter.supportsSync, true);
  });
});
