import { describe, it, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";

describe("Cursor adapter", () => {
  let tmpDir: string;
  let origCwd: string;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "trc-cursor-"));
    origCwd = process.cwd();
    process.chdir(tmpDir);
  });

  afterEach(() => {
    process.chdir(origCwd);
    fs.rmSync(tmpDir, { recursive: true });
  });

  it("writes alwaysApply/globs skills as .mdc files in .cursor/rules/", async () => {
    const { CursorAdapter } = await import("../adapters/cursor.js");
    const adapter = new CursorAdapter();

    const team = {
      name: "test-team",
      members: [{ name: "architect", role: "design" }],
      skills: [
        { id: "skill_style", title: "Code Style", description: "Enforce code style", globs: ["*.ts"], alwaysApply: false, body: "Use prettier." },
        { id: "skill_security", title: "Security", description: "Security validation", alwaysApply: true, body: "Validate all inputs." },
      ],
    };

    adapter.writeTeam(team);

    const rulesDir = path.join(tmpDir, ".cursor", "rules");
    assert.ok(fs.existsSync(rulesDir));

    const styleFile = path.join(rulesDir, "trc-skill_style.mdc");
    assert.ok(fs.existsSync(styleFile));

    const content = fs.readFileSync(styleFile, "utf-8");
    assert.ok(content.includes("Enforce code style"));
    assert.ok(content.includes('globs: ["*.ts"]'));
    assert.ok(content.includes("alwaysApply: false"));
    assert.ok(content.includes("Use prettier."));

    const secFile = path.join(rulesDir, "trc-skill_security.mdc");
    const secContent = fs.readFileSync(secFile, "utf-8");
    assert.ok(secContent.includes("alwaysApply: true"));
  });

  it("writes on-demand skills to .cursor/skills/", async () => {
    const { CursorAdapter } = await import("../adapters/cursor.js");
    const adapter = new CursorAdapter();

    const team = {
      name: "test-team",
      members: [{ name: "architect", role: "design" }],
      skills: [{ id: "skill_search", description: "Search code", body: "Use grep." }],
    };

    adapter.writeTeam(team);

    const skillFile = path.join(tmpDir, ".cursor", "skills", "trc-skill_search", "SKILL.md");
    assert.ok(fs.existsSync(skillFile), "SKILL.md should exist");

    const content = fs.readFileSync(skillFile, "utf-8");
    assert.ok(content.includes("name: trc-skill_search"));
    assert.ok(content.includes("Search code"));
    assert.ok(content.includes("Use grep."));
  });

  it("writes subagent .md files to .cursor/agents/", async () => {
    const { CursorAdapter } = await import("../adapters/cursor.js");
    const adapter = new CursorAdapter();

    const team = {
      name: "test-team",
      members: [
        { name: "architect", role: "design architecture", skills: ["skill_style"] },
        { name: "coder", role: "write code" },
      ],
      skills: [{ id: "skill_style", title: "Code Style", alwaysApply: true, body: "Use prettier." }],
    };

    adapter.writeTeam(team);

    const agentFile = path.join(tmpDir, ".cursor", "agents", "trc-architect.md");
    assert.ok(fs.existsSync(agentFile), "Subagent .md file should exist");

    const content = fs.readFileSync(agentFile, "utf-8");
    assert.ok(content.includes("name: trc-architect"));
    assert.ok(content.includes("design architecture"));
    assert.ok(content.includes("Code Style"));
    assert.ok(content.includes("Use prettier."));
    assert.ok(content.includes("coder"));
  });

  it("writes routing instructions to AGENTS.md", async () => {
    const { CursorAdapter } = await import("../adapters/cursor.js");
    const adapter = new CursorAdapter();

    const team = {
      name: "test-team",
      members: [
        { name: "architect", role: "design architecture" },
        { name: "coder", role: "write code" },
      ],
    };

    adapter.writeTeam(team);

    const agentsMd = path.join(tmpDir, ".cursor", "AGENTS.md");
    assert.ok(fs.existsSync(agentsMd));
    const content = fs.readFileSync(agentsMd, "utf-8");
    assert.ok(content.includes("test-team"));
    assert.ok(content.includes("trc-architect"));
    assert.ok(content.includes("subagents"));
  });

  it("cleans up subagent files on uninstall", async () => {
    const { CursorAdapter } = await import("../adapters/cursor.js");
    const adapter = new CursorAdapter();

    const team = {
      name: "test-team",
      members: [{ name: "architect", role: "design" }],
      skills: [{ id: "skill_style", title: "Code Style", alwaysApply: true, body: "Use prettier." }],
    };

    adapter.writeTeam(team);

    // Verify files exist
    assert.ok(fs.existsSync(path.join(tmpDir, ".cursor", "agents", "trc-architect.md")));
    assert.ok(fs.existsSync(path.join(tmpDir, ".cursor", "rules", "trc-skill_style.mdc")));

    const actions = adapter.uninstall();
    assert.ok(actions.length > 0);
    assert.ok(!fs.existsSync(path.join(tmpDir, ".cursor", "agents", "trc-architect.md")));
    assert.ok(!fs.existsSync(path.join(tmpDir, ".cursor", "rules", "trc-skill_style.mdc")));
  });
});
