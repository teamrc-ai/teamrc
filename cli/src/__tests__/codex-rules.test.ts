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

  it("writes native skill directories to skills/", async () => {
    const { CodexAdapter } = await import("../adapters/codex.js");
    const adapter = new CodexAdapter();

    const team = {
      name: "test-team",
      members: [{ name: "architect", role: "design" }],
      skills: [{ id: "skill_search", description: "Search code", body: "Use grep." }],
    };

    adapter.writeTeam(team);

    const skillFile = path.join(tmpDir, "skills", "trc-skill_search", "SKILL.md");
    assert.ok(fs.existsSync(skillFile), "SKILL.md should exist");

    const content = fs.readFileSync(skillFile, "utf-8");
    assert.ok(content.includes("name: trc-skill_search"));
    assert.ok(content.includes("Search code"));
  });

  it("writes subagent TOML files to .codex/agents/", async () => {
    const { CodexAdapter } = await import("../adapters/codex.js");
    const adapter = new CodexAdapter();

    const team = {
      name: "test-team",
      members: [
        { name: "architect", role: "design architecture", rules: ["rule_style"] },
        { name: "coder", role: "write code" },
      ],
      rules: [{ id: "rule_style", title: "Code Style", body: "Use prettier." }],
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
});
