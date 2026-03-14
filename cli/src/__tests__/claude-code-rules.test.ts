import { describe, it, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";

describe("Claude Code agent file with skills", () => {
  let tmpDir: string;
  let origHome: string | undefined;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "trc-cc-rules-"));
    origHome = process.env.HOME;
    process.env.HOME = tmpDir;
  });

  afterEach(() => {
    if (origHome !== undefined) {
      process.env.HOME = origHome;
    } else {
      delete process.env.HOME;
    }
    fs.rmSync(tmpDir, { recursive: true });
  });

  it("includes resolved skills in agent file body", async () => {
    const { ClaudeCodeAdapter } = await import("../adapters/claude-code.js");
    const adapter = new ClaudeCodeAdapter();

    const team = {
      name: "test-team",
      members: [
        { name: "architect", role: "design", skills: ["skill_search"] },
      ],
      skills: [{ id: "skill_search", description: "Search code", body: "Use grep." }],
    };

    adapter.writeTeam(team, "global");

    const agentDir = path.join(tmpDir, ".claude", "agents");
    const files = fs.readdirSync(agentDir).filter((f: string) => f.startsWith("trc-"));
    assert.equal(files.length, 1);

    const content = fs.readFileSync(path.join(agentDir, files[0]), "utf-8");
    assert.ok(content.includes("## Skills"), "Should have Skills section");
    assert.ok(content.includes("Search code"), "Should include skill description");
    assert.ok(content.includes("Use grep."), "Should include skill body");
    assert.ok(!content.includes("## Rules"), "Should NOT have Rules section");
  });

  it("writes alwaysApply skills as native rule files to .claude/rules/", async () => {
    const { ClaudeCodeAdapter } = await import("../adapters/claude-code.js");
    const adapter = new ClaudeCodeAdapter();

    const team = {
      name: "test-team",
      members: [{ name: "architect", role: "design" }],
      skills: [
        { id: "skill_style", title: "Code Style", alwaysApply: true, body: "Use prettier." },
        { id: "skill_scoped", globs: ["src/**/*.ts"], body: "TS only skill." },
      ],
    };

    adapter.writeTeam(team, "global");

    const rulesDir = path.join(tmpDir, ".claude", "rules");
    assert.ok(fs.existsSync(rulesDir), "rules dir should exist");

    const styleFile = path.join(rulesDir, "trc-skill_style.md");
    const styleContent = fs.readFileSync(styleFile, "utf-8");
    assert.ok(!styleContent.includes("---"), "No frontmatter for alwaysApply without globs");
    assert.ok(styleContent.includes("Use prettier."));

    const scopedFile = path.join(rulesDir, "trc-skill_scoped.md");
    const scopedContent = fs.readFileSync(scopedFile, "utf-8");
    assert.ok(scopedContent.includes("paths:"), "Should have paths frontmatter");
    assert.ok(scopedContent.includes("src/**/*.ts"));
    assert.ok(scopedContent.includes("TS only skill."));
  });

  it("writes on-demand skills to .claude/skills/", async () => {
    const { ClaudeCodeAdapter } = await import("../adapters/claude-code.js");
    const adapter = new ClaudeCodeAdapter();

    const team = {
      name: "test-team",
      members: [{ name: "architect", role: "design" }],
      skills: [{ id: "skill_search", description: "Search code", body: "Use grep." }],
    };

    adapter.writeTeam(team, "global");

    const skillFile = path.join(tmpDir, ".claude", "skills", "trc-skill_search", "SKILL.md");
    assert.ok(fs.existsSync(skillFile), "SKILL.md should exist");

    const content = fs.readFileSync(skillFile, "utf-8");
    assert.ok(content.includes("name: trc-skill_search"));
    assert.ok(content.includes("Search code"));
    assert.ok(content.includes("Use grep."));
  });

  it("works without skills", async () => {
    const { ClaudeCodeAdapter } = await import("../adapters/claude-code.js");
    const adapter = new ClaudeCodeAdapter();

    const team = {
      name: "test-team",
      members: [{ name: "coder", role: "write code" }],
    };

    adapter.writeTeam(team, "global");

    const agentDir = path.join(tmpDir, ".claude", "agents");
    const files = fs.readdirSync(agentDir).filter((f: string) => f.startsWith("trc-"));
    const content = fs.readFileSync(path.join(agentDir, files[0]), "utf-8");
    assert.ok(!content.includes("## Rules"), "Should NOT have Rules section");
    assert.ok(!content.includes("## Skills"), "Should NOT have Skills section");
  });

  it("removes orphaned agent files when members are removed", async () => {
    const { ClaudeCodeAdapter } = await import("../adapters/claude-code.js");
    const adapter = new ClaudeCodeAdapter();

    // Write team with two members
    adapter.writeTeam({
      name: "test-team",
      members: [
        { name: "alice", role: "frontend" },
        { name: "bob", role: "backend" },
      ],
    }, "global");

    const agentDir = path.join(tmpDir, ".claude", "agents");
    assert.ok(fs.existsSync(path.join(agentDir, "trc-alice.md")));
    assert.ok(fs.existsSync(path.join(agentDir, "trc-bob.md")));

    // Remove bob from team and re-apply
    adapter.writeTeam({
      name: "test-team",
      members: [{ name: "alice", role: "frontend" }],
    }, "global");

    assert.ok(fs.existsSync(path.join(agentDir, "trc-alice.md")), "alice should remain");
    assert.ok(!fs.existsSync(path.join(agentDir, "trc-bob.md")), "bob should be deleted");
  });

  it("writes built-in teamrc skills to .claude/skills/", async () => {
    const { ClaudeCodeAdapter } = await import("../adapters/claude-code.js");
    const adapter = new ClaudeCodeAdapter();

    const team = {
      name: "test-team",
      members: [{ name: "coder", role: "write code" }],
    };

    adapter.writeTeam(team, "global");

    const skillsDir = path.join(tmpDir, ".claude", "skills");
    assert.ok(fs.existsSync(skillsDir), "skills dir should exist");

    // Check all four built-in skills are written
    const builtInSkills = ["trc-save-knowledge", "trc-save-core", "trc-knowledge", "trc-status"];
    for (const skillName of builtInSkills) {
      const skillFile = path.join(skillsDir, skillName, "SKILL.md");
      assert.ok(fs.existsSync(skillFile), `${skillName}/SKILL.md should exist`);
    }
  });

  it("writes disable-model-invocation frontmatter in built-in skills", async () => {
    const { ClaudeCodeAdapter } = await import("../adapters/claude-code.js");
    const adapter = new ClaudeCodeAdapter();

    adapter.writeTeam({
      name: "test-team",
      members: [{ name: "coder", role: "write code" }],
    }, "global");

    const skillsDir = path.join(tmpDir, ".claude", "skills");

    // save-knowledge should have disable-model-invocation: true
    const saveContent = fs.readFileSync(
      path.join(skillsDir, "trc-save-knowledge", "SKILL.md"), "utf-8"
    );
    assert.ok(saveContent.includes("disable-model-invocation: true"),
      "save-knowledge should have disable-model-invocation");
    assert.ok(saveContent.includes("argument-hint:"),
      "save-knowledge should have argument-hint");

    // knowledge should NOT have disable-model-invocation (agent can auto-trigger)
    const knowledgeContent = fs.readFileSync(
      path.join(skillsDir, "trc-knowledge", "SKILL.md"), "utf-8"
    );
    assert.ok(!knowledgeContent.includes("disable-model-invocation"),
      "knowledge should not have disable-model-invocation");
  });

  it("writes on-demand skills with new frontmatter fields", async () => {
    const { ClaudeCodeAdapter } = await import("../adapters/claude-code.js");
    const adapter = new ClaudeCodeAdapter();

    const team = {
      name: "test-team",
      members: [{ name: "coder", role: "write code" }],
      skills: [{
        id: "my-skill",
        description: "A custom skill",
        disableModelInvocation: true,
        argumentHint: "<file>",
        body: "Do the thing.",
      }],
    };

    adapter.writeTeam(team, "global");

    const skillFile = path.join(tmpDir, ".claude", "skills", "trc-my-skill", "SKILL.md");
    const content = fs.readFileSync(skillFile, "utf-8");
    assert.ok(content.includes("disable-model-invocation: true"));
    assert.ok(content.includes('argument-hint: "<file>"'));
  });

  it("cleans up built-in skills on uninstall", async () => {
    const { ClaudeCodeAdapter } = await import("../adapters/claude-code.js");
    const adapter = new ClaudeCodeAdapter();

    adapter.writeTeam({
      name: "test-team",
      members: [{ name: "coder", role: "write code" }],
    }, "global");

    const skillsDir = path.join(tmpDir, ".claude", "skills");
    assert.ok(fs.existsSync(path.join(skillsDir, "trc-save-knowledge")),
      "built-in skill should exist before uninstall");

    adapter.uninstall("global");

    assert.ok(!fs.existsSync(path.join(skillsDir, "trc-save-knowledge")),
      "built-in skill should be removed after uninstall");
  });
});
