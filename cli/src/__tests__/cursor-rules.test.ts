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

  it("removes orphaned agent files when members are removed", async () => {
    const { CursorAdapter } = await import("../adapters/cursor.js");
    const adapter = new CursorAdapter();

    adapter.writeTeam({
      name: "test-team",
      members: [
        { name: "alice", role: "frontend" },
        { name: "bob", role: "backend" },
      ],
    });

    const agentDir = path.join(tmpDir, ".cursor", "agents");
    assert.ok(fs.existsSync(path.join(agentDir, "trc-alice.md")));
    assert.ok(fs.existsSync(path.join(agentDir, "trc-bob.md")));

    // Remove bob from team and re-apply
    adapter.writeTeam({
      name: "test-team",
      members: [{ name: "alice", role: "frontend" }],
    });

    assert.ok(fs.existsSync(path.join(agentDir, "trc-alice.md")), "alice should remain");
    assert.ok(!fs.existsSync(path.join(agentDir, "trc-bob.md")), "bob should be deleted");
  });

  it("writes built-in teamrc skills to .cursor/skills/", async () => {
    const { CursorAdapter } = await import("../adapters/cursor.js");
    const adapter = new CursorAdapter();

    adapter.writeTeam({
      name: "test-team",
      members: [{ name: "coder", role: "write code" }],
    });

    const skillsDir = path.join(tmpDir, ".cursor", "skills");
    const builtInSkills = ["trc-save-knowledge", "trc-save-core", "trc-knowledge", "trc-status"];
    for (const skillName of builtInSkills) {
      const skillFile = path.join(skillsDir, skillName, "SKILL.md");
      assert.ok(fs.existsSync(skillFile), `${skillName}/SKILL.md should exist`);
    }

    // Verify disable-model-invocation is written
    const saveContent = fs.readFileSync(
      path.join(skillsDir, "trc-save-knowledge", "SKILL.md"), "utf-8"
    );
    assert.ok(saveContent.includes("disable-model-invocation: true"));
  });

  it("uses member description in agent file when present", async () => {
    const { CursorAdapter } = await import("../adapters/cursor.js");
    const adapter = new CursorAdapter();

    adapter.writeTeam({
      name: "test-team",
      members: [
        { name: "coder", role: "developer", description: "Builds features. Use for feature work." },
      ],
    });

    const agentDir = path.join(tmpDir, ".cursor", "agents");
    const content = fs.readFileSync(path.join(agentDir, "trc-coder.md"), "utf-8");
    assert.ok(content.includes('description: "Builds features. Use for feature work."'));
    // Description should NOT contain the role-based fallback pattern
    assert.ok(!content.includes('description: "developer on the'));
  });
});
