import { describe, it, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";

describe("Codex adapter", () => {
  let tmpDir: string;
  let origCwd: string;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "trc-codex-"));
    origCwd = process.cwd();
    process.chdir(tmpDir);
  });

  afterEach(() => {
    process.chdir(origCwd);
    fs.rmSync(tmpDir, { recursive: true });
  });

  it("writes on-demand skill directories to .agents/skills/", async () => {
    const { CodexAdapter } = await import("../adapters/codex.js");
    const adapter = new CodexAdapter();

    const team = {
      name: "test-team",
      members: [{ name: "architect", role: "design" }],
      skills: [{ id: "skill_search", description: "Search code", body: "Use grep." }],
    };

    adapter.writeTeam(team);

    const skillFile = path.join(tmpDir, ".agents", "skills", "trc-skill_search", "SKILL.md");
    assert.ok(fs.existsSync(skillFile), "SKILL.md should exist in .agents/skills/");

    const content = fs.readFileSync(skillFile, "utf-8");
    assert.ok(content.includes("name: trc-skill_search"));
    assert.ok(content.includes("Search code"));
  });

  it("routes alwaysApply skills into AGENTS.md instead of skill dirs", async () => {
    const { CodexAdapter } = await import("../adapters/codex.js");
    const adapter = new CodexAdapter();

    const team = {
      name: "test-team",
      members: [{ name: "architect", role: "design" }],
      skills: [
        { id: "skill_style", title: "Code Style", alwaysApply: true, body: "Use prettier." },
        { id: "skill_search", description: "Search code", body: "Use grep." },
      ],
    };

    adapter.writeTeam(team);

    // alwaysApply skill should NOT be in skill dirs
    assert.ok(!fs.existsSync(path.join(tmpDir, ".agents", "skills", "trc-skill_style")),
      "alwaysApply skill should not be written as skill dir");

    // on-demand skill should be in skill dirs
    assert.ok(fs.existsSync(path.join(tmpDir, ".agents", "skills", "trc-skill_search", "SKILL.md")),
      "on-demand skill should be in .agents/skills/");

    // alwaysApply skill should be inlined in AGENTS.md
    const agentsMd = fs.readFileSync(path.join(tmpDir, "AGENTS.md"), "utf-8");
    assert.ok(agentsMd.includes("Team Rules"), "AGENTS.md should have Team Rules section");
    assert.ok(agentsMd.includes("Code Style"), "AGENTS.md should include alwaysApply skill title");
    assert.ok(agentsMd.includes("Use prettier."), "AGENTS.md should include alwaysApply skill body");
  });

  it("writes subagent TOML files with skills to .codex/agents/", async () => {
    const { CodexAdapter } = await import("../adapters/codex.js");
    const adapter = new CodexAdapter();

    const team = {
      name: "test-team",
      members: [
        { name: "architect", role: "design architecture", skills: ["skill_style"] },
        { name: "coder", role: "write code" },
      ],
      skills: [{ id: "skill_style", title: "Code Style", alwaysApply: true, body: "Use prettier." }],
    };

    adapter.writeTeam(team);

    // Check TOML agent file
    const tomlFile = path.join(tmpDir, ".codex", "agents", "trc-architect.toml");
    assert.ok(fs.existsSync(tomlFile), "TOML agent file should exist");

    const content = fs.readFileSync(tomlFile, "utf-8");
    assert.ok(content.includes("developer_instructions"));
    assert.ok(content.includes("design architecture"));
    assert.ok(content.includes("Code Style"));
    assert.ok(content.includes("Use prettier."));
    assert.ok(content.includes("coder"));
  });

  it("registers subagents in .codex/config.toml", async () => {
    const { CodexAdapter } = await import("../adapters/codex.js");
    const adapter = new CodexAdapter();

    const team = {
      name: "test-team",
      members: [{ name: "architect", role: "design" }],
    };

    adapter.writeTeam(team);

    const configPath = path.join(tmpDir, ".codex", "config.toml");
    assert.ok(fs.existsSync(configPath), "config.toml should exist");

    const content = fs.readFileSync(configPath, "utf-8");
    assert.ok(content.includes("multi_agent = true"), "config.toml should have multi_agent flag");
    assert.ok(content.includes("[agents.trc-architect]"));
    assert.ok(content.includes('config_file = "agents/trc-architect.toml"'));
  });

  it("writes routing AGENTS.md", async () => {
    const { CodexAdapter } = await import("../adapters/codex.js");
    const adapter = new CodexAdapter();

    const team = {
      name: "test-team",
      members: [{ name: "architect", role: "design" }],
    };

    adapter.writeTeam(team);

    const agentsMd = path.join(tmpDir, "AGENTS.md");
    assert.ok(fs.existsSync(agentsMd));

    const content = fs.readFileSync(agentsMd, "utf-8");
    assert.ok(content.includes("test-team"));
    assert.ok(content.includes("trc-architect"));
  });

  it("cleans up on uninstall", async () => {
    const { CodexAdapter } = await import("../adapters/codex.js");
    const adapter = new CodexAdapter();

    const team = {
      name: "test-team",
      members: [{ name: "architect", role: "design" }],
      skills: [{ id: "skill_search", description: "Search code", body: "Use grep." }],
    };

    adapter.writeTeam(team);

    // Verify files exist
    assert.ok(fs.existsSync(path.join(tmpDir, ".codex", "agents", "trc-architect.toml")));
    assert.ok(fs.existsSync(path.join(tmpDir, ".codex", "config.toml")));
    assert.ok(fs.existsSync(path.join(tmpDir, "AGENTS.md")));

    const actions = adapter.uninstall();
    assert.ok(actions.length > 0);
    assert.ok(!fs.existsSync(path.join(tmpDir, ".codex", "agents", "trc-architect.toml")));
  });

  it("readTeam() parses existing trc-*.toml agent files (roundtrip)", async () => {
    const { CodexAdapter } = await import("../adapters/codex.js");
    const adapter = new CodexAdapter();

    const team = {
      name: "roundtrip-team",
      members: [
        { name: "alice", role: "frontend developer" },
        { name: "bob", role: "backend engineer" },
      ],
    };

    adapter.writeTeam(team);

    const imported = adapter.readTeam();
    assert.ok(imported, "readTeam should return a team definition");
    assert.equal(imported.members.length, 2);
    assert.ok(imported.members.some((m) => m.name === "alice"), "Should have alice");
    assert.ok(imported.members.some((m) => m.name === "bob"), "Should have bob");
    assert.ok(imported.members.some((m) => m.role === "frontend developer"), "Should preserve role");
  });

  it("readTeam() returns null when no trc-*.toml files exist", async () => {
    const { CodexAdapter } = await import("../adapters/codex.js");
    const adapter = new CodexAdapter();

    const result = adapter.readTeam();
    assert.equal(result, null);
  });

  it("removes orphaned agent files when members are removed", async () => {
    const { CodexAdapter } = await import("../adapters/codex.js");
    const adapter = new CodexAdapter();

    adapter.writeTeam({
      name: "test-team",
      members: [
        { name: "alice", role: "frontend" },
        { name: "bob", role: "backend" },
      ],
    });

    const agentDir = path.join(tmpDir, ".codex", "agents");
    assert.ok(fs.existsSync(path.join(agentDir, "trc-alice.toml")));
    assert.ok(fs.existsSync(path.join(agentDir, "trc-bob.toml")));

    // Remove bob from team and re-apply
    adapter.writeTeam({
      name: "test-team",
      members: [{ name: "alice", role: "frontend" }],
    });

    assert.ok(fs.existsSync(path.join(agentDir, "trc-alice.toml")), "alice should remain");
    assert.ok(!fs.existsSync(path.join(agentDir, "trc-bob.toml")), "bob should be deleted");
  });

  it("uses member description in config.toml when present", async () => {
    const { CodexAdapter } = await import("../adapters/codex.js");
    const adapter = new CodexAdapter();

    adapter.writeTeam({
      name: "test-team",
      members: [
        { name: "coder", role: "developer", description: "Builds features. Use for feature work." },
      ],
    });

    const configPath = path.join(tmpDir, ".codex", "config.toml");
    const content = fs.readFileSync(configPath, "utf-8");
    assert.ok(content.includes("Builds features. Use for feature work."));
  });
});
