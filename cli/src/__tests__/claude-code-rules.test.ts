import { describe, it, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";

describe("Claude Code agent file with rules and skills", () => {
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

  it("includes resolved rules in agent file body", async () => {
    const { ClaudeCodeAdapter } = await import("../adapters/claude-code.js");
    const adapter = new ClaudeCodeAdapter();

    const team = {
      name: "test-team",
      members: [
        { name: "architect", role: "design", rules: ["rule_style"], skills: ["skill_search"] },
      ],
      rules: [{ id: "rule_style", title: "Code Style", body: "Use prettier." }],
      skills: [{ id: "skill_search", description: "Search code", body: "Use grep." }],
    };

    adapter.writeTeam(team, "global");

    const agentDir = path.join(tmpDir, ".claude", "agents");
    const files = fs.readdirSync(agentDir).filter((f: string) => f.startsWith("trc-"));
    assert.equal(files.length, 1);

    const content = fs.readFileSync(path.join(agentDir, files[0]), "utf-8");
    assert.ok(content.includes("## Rules"), "Should have Rules section");
    assert.ok(content.includes("Code Style"), "Should include rule title");
    assert.ok(content.includes("Use prettier."), "Should include rule body");
    assert.ok(content.includes("## Skills"), "Should have Skills section");
    assert.ok(content.includes("Search code"), "Should include skill description");
    assert.ok(content.includes("Use grep."), "Should include skill body");
  });

  it("writes native rule files to .claude/rules/", async () => {
    const { ClaudeCodeAdapter } = await import("../adapters/claude-code.js");
    const adapter = new ClaudeCodeAdapter();

    const team = {
      name: "test-team",
      members: [{ name: "architect", role: "design" }],
      rules: [
        { id: "rule_style", title: "Code Style", body: "Use prettier." },
        { id: "rule_scoped", globs: ["src/**/*.ts"], body: "TS only rule." },
      ],
    };

    adapter.writeTeam(team, "global");

    const rulesDir = path.join(tmpDir, ".claude", "rules");
    assert.ok(fs.existsSync(rulesDir), "rules dir should exist");

    const styleFile = path.join(rulesDir, "trc-rule_style.md");
    const styleContent = fs.readFileSync(styleFile, "utf-8");
    assert.ok(!styleContent.includes("---"), "No frontmatter for unscoped rule");
    assert.ok(styleContent.includes("Use prettier."));

    const scopedFile = path.join(rulesDir, "trc-rule_scoped.md");
    const scopedContent = fs.readFileSync(scopedFile, "utf-8");
    assert.ok(scopedContent.includes("paths:"), "Should have paths frontmatter");
    assert.ok(scopedContent.includes("src/**/*.ts"));
    assert.ok(scopedContent.includes("TS only rule."));
  });

  it("writes native skill directories to .claude/skills/", async () => {
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

  it("works without rules or skills", async () => {
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
});
