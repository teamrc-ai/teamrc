import { describe, it, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";

describe("OpenClaw adapter (file-based agents)", () => {
  let tmpDir: string;
  let origHome: string | undefined;
  let origCwd: string;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "trc-oc-"));
    origHome = process.env.HOME;
    origCwd = process.cwd();
    process.env.HOME = tmpDir;
    process.chdir(tmpDir);
  });

  afterEach(() => {
    process.chdir(origCwd);
    if (origHome !== undefined) {
      process.env.HOME = origHome;
    } else {
      delete process.env.HOME;
    }
    fs.rmSync(tmpDir, { recursive: true });
  });

  it("creates agent .md files in ~/.openclaw/agents/", async () => {
    const { OpenClawAdapter } = await import("../adapters/openclaw.js");
    const adapter = new OpenClawAdapter();

    const team = {
      name: "test-team",
      members: [
        { name: "architect", role: "System architect" },
        { name: "dev", role: "Developer" },
      ],
    };

    adapter.writeTeam(team);

    const architectFile = path.join(tmpDir, ".openclaw", "agents", "trc-architect.md");
    const devFile = path.join(tmpDir, ".openclaw", "agents", "trc-dev.md");
    assert.ok(fs.existsSync(architectFile), "architect agent file should exist");
    assert.ok(fs.existsSync(devFile), "dev agent file should exist");
  });

  it("writes agent files with YAML frontmatter and team info", async () => {
    const { OpenClawAdapter } = await import("../adapters/openclaw.js");
    const adapter = new OpenClawAdapter();

    const team = {
      name: "test-team",
      members: [
        { name: "architect", role: "System architect" },
        { name: "dev", role: "Developer" },
      ],
    };

    adapter.writeTeam(team);

    const content = fs.readFileSync(
      path.join(tmpDir, ".openclaw", "agents", "trc-architect.md"),
      "utf-8",
    );
    assert.ok(content.startsWith("---\n"), "Should start with YAML frontmatter");
    assert.ok(content.includes("name: trc-architect"), "Should have agent name in frontmatter");
    assert.ok(content.includes("description: System architect"), "Should have role as description");
    assert.ok(content.includes("## Team: test-team"), "Should have team name");
    assert.ok(content.includes("**dev**"), "Should list teammate");
  });

  it("includes custom soul in agent file", async () => {
    const { OpenClawAdapter } = await import("../adapters/openclaw.js");
    const adapter = new OpenClawAdapter();

    const team = {
      name: "test-team",
      members: [
        { name: "architect", role: "System architect", soul: "You design distributed systems." },
        { name: "dev", role: "Developer" },
      ],
    };

    adapter.writeTeam(team);

    const content = fs.readFileSync(
      path.join(tmpDir, ".openclaw", "agents", "trc-architect.md"),
      "utf-8",
    );
    assert.ok(content.includes("teamrc-role: System architect"), "Should encode role");
    assert.ok(content.includes("You design distributed systems."), "Should have custom soul");
  });

  it("registers agents in openclaw.json", async () => {
    const { OpenClawAdapter } = await import("../adapters/openclaw.js");
    const adapter = new OpenClawAdapter();

    const team = {
      name: "test-team",
      members: [
        { name: "architect", role: "System architect" },
        { name: "dev", role: "Developer" },
      ],
    };

    adapter.writeTeam(team);

    const configPath = path.join(tmpDir, ".openclaw", "openclaw.json");
    assert.ok(fs.existsSync(configPath), "openclaw.json should exist");

    const config = JSON.parse(fs.readFileSync(configPath, "utf-8"));
    assert.ok(config.agents?.list, "Should have agents.list");
    assert.equal(config.agents.list.length, 2, "Should have 2 agents");

    const architectEntry = config.agents.list.find((a: { id: string }) => a.id === "trc-architect");
    assert.ok(architectEntry, "Should have architect entry");
    assert.equal(architectEntry.name, "architect", "Should have agent name");
    assert.deepEqual(
      architectEntry.subagents?.allowAgents,
      ["trc-architect", "trc-dev"],
      "Should have subagent allowlist with all team members",
    );
  });

  it("configures subagent allowlists for all team members", async () => {
    const { OpenClawAdapter } = await import("../adapters/openclaw.js");
    const adapter = new OpenClawAdapter();

    const team = {
      name: "test-team",
      members: [
        { name: "architect", role: "System architect" },
        { name: "implementer", role: "Developer" },
        { name: "reviewer", role: "Code reviewer" },
      ],
    };

    adapter.writeTeam(team);

    const config = JSON.parse(fs.readFileSync(
      path.join(tmpDir, ".openclaw", "openclaw.json"), "utf-8",
    ));

    const allIds = ["trc-architect", "trc-implementer", "trc-reviewer"];
    for (const id of allIds) {
      const entry = config.agents.list.find((a: { id: string }) => a.id === id);
      assert.ok(entry, `Should have entry for ${id}`);
      assert.deepEqual(
        entry.subagents?.allowAgents,
        allIds,
        `${id} should be able to spawn all team agents`,
      );
    }
  });

  it("updates subagent allowlists when team changes", async () => {
    const { OpenClawAdapter } = await import("../adapters/openclaw.js");
    const adapter = new OpenClawAdapter();

    // Write initial team with 3 members
    adapter.writeTeam({
      name: "test-team",
      members: [
        { name: "architect", role: "Architect" },
        { name: "dev", role: "Developer" },
        { name: "dba", role: "DBA" },
      ],
    });

    // Remove dba from team
    adapter.writeTeam({
      name: "test-team",
      members: [
        { name: "architect", role: "Architect" },
        { name: "dev", role: "Developer" },
      ],
    });

    const config = JSON.parse(fs.readFileSync(
      path.join(tmpDir, ".openclaw", "openclaw.json"), "utf-8",
    ));

    const architectEntry = config.agents.list.find((a: { id: string }) => a.id === "trc-architect");
    assert.deepEqual(
      architectEntry.subagents?.allowAgents,
      ["trc-architect", "trc-dev"],
      "Should no longer include removed agent in allowlist",
    );
    assert.ok(
      !config.agents.list.find((a: { id: string }) => a.id === "trc-dba"),
      "Removed agent should not be in config",
    );
  });

  it("preserves non-trc agents in openclaw.json", async () => {
    const { OpenClawAdapter } = await import("../adapters/openclaw.js");
    const adapter = new OpenClawAdapter();

    // Pre-populate with a user's existing agent
    const configDir = path.join(tmpDir, ".openclaw");
    fs.mkdirSync(configDir, { recursive: true });
    fs.writeFileSync(path.join(configDir, "openclaw.json"), JSON.stringify({
      agents: { list: [{ id: "main", workspace: "~/.openclaw/workspace", default: true }] },
    }, null, 2));

    const team = {
      name: "test-team",
      members: [{ name: "dev", role: "Developer" }],
    };

    adapter.writeTeam(team);

    const config = JSON.parse(fs.readFileSync(path.join(configDir, "openclaw.json"), "utf-8"));
    assert.equal(config.agents.list.length, 2, "Should have 2 agents (1 existing + 1 trc)");
    assert.ok(config.agents.list.find((a: { id: string }) => a.id === "main"), "Should preserve existing agent");
    assert.ok(config.agents.list.find((a: { id: string }) => a.id === "trc-dev"), "Should add new trc agent");
  });

  it("writes skills to ~/.openclaw/skills/", async () => {
    const { OpenClawAdapter } = await import("../adapters/openclaw.js");
    const adapter = new OpenClawAdapter();

    const team = {
      name: "test-team",
      members: [{ name: "dev", role: "developer" }],
      skills: [
        { id: "tdd", title: "TDD", description: "Test-driven dev", body: "Red green refactor." },
      ],
    };

    adapter.writeTeam(team);

    const sharedSkillDir = path.join(tmpDir, ".openclaw", "skills");
    assert.ok(fs.existsSync(path.join(sharedSkillDir, "trc-tdd", "SKILL.md")), "Shared skill should exist");

    const content = fs.readFileSync(path.join(sharedSkillDir, "trc-tdd", "SKILL.md"), "utf-8");
    assert.ok(content.includes("name: trc-tdd"), "SKILL.md should have name");
    assert.ok(content.includes("Red green refactor."), "SKILL.md should have body");
  });

  it("lists per-agent skills in agent file", async () => {
    const { OpenClawAdapter } = await import("../adapters/openclaw.js");
    const adapter = new OpenClawAdapter();

    const team = {
      name: "test-team",
      members: [
        { name: "architect", role: "design", skills: ["skill-search"] },
      ],
      skills: [{ id: "skill-search", description: "Search code", body: "Use grep." }],
    };

    adapter.writeTeam(team);

    const content = fs.readFileSync(
      path.join(tmpDir, ".openclaw", "agents", "trc-architect.md"),
      "utf-8",
    );
    assert.ok(content.includes("## Skills"), "Should have skills section");
    assert.ok(content.includes("skill-search"), "Should list assigned skill");
  });

  it("readTeam parses agent files", async () => {
    const { OpenClawAdapter } = await import("../adapters/openclaw.js");
    const adapter = new OpenClawAdapter();

    const team = {
      name: "test-team",
      members: [
        { name: "architect", role: "System architect", soul: "You design distributed systems." },
        { name: "dev", role: "Developer" },
      ],
    };

    adapter.writeTeam(team);

    const readTeam = adapter.readTeam();
    assert.ok(readTeam !== null, "Should read team back");
    assert.equal(readTeam!.name, "test-team");
    assert.equal(readTeam!.members.length, 2);

    const architect = readTeam!.members.find((m) => m.name === "architect");
    assert.ok(architect !== undefined, "Should find architect");
    assert.equal(architect!.role, "System architect");
    assert.equal(architect!.soul, "You design distributed systems.");
  });

  it("knowledge read/write works", async () => {
    const { OpenClawAdapter } = await import("../adapters/openclaw.js");
    const adapter = new OpenClawAdapter("test-team");

    assert.equal(adapter.readKnowledge(), "");

    adapter.writeKnowledge("# Knowledge\n\nSome content.");
    assert.equal(adapter.readKnowledge(), "# Knowledge\n\nSome content.");

    const knowledgePath = path.join(tmpDir, ".openclaw", "knowledge-test-team.md");
    assert.ok(fs.existsSync(knowledgePath), "Knowledge should be in ~/.openclaw/");
  });

  it("cleans up stale agent files on write", async () => {
    const { OpenClawAdapter } = await import("../adapters/openclaw.js");
    const adapter = new OpenClawAdapter();

    // Write initial team
    adapter.writeTeam({
      name: "test-team",
      members: [
        { name: "architect", role: "Architect" },
        { name: "dev", role: "Developer" },
      ],
    });

    // Write updated team without architect
    adapter.writeTeam({
      name: "test-team",
      members: [{ name: "dev", role: "Developer" }],
    });

    const agentsDir = path.join(tmpDir, ".openclaw", "agents");
    assert.ok(
      !fs.existsSync(path.join(agentsDir, "trc-architect.md")),
      "Stale agent file should be removed",
    );
    assert.ok(
      fs.existsSync(path.join(agentsDir, "trc-dev.md")),
      "Active agent file should remain",
    );
  });

  it("cleans up legacy workspace dirs on write", async () => {
    const { OpenClawAdapter } = await import("../adapters/openclaw.js");
    const adapter = new OpenClawAdapter();

    // Create legacy workspace dir
    const legacyWs = path.join(tmpDir, ".openclaw", "workspace-trc-dev");
    fs.mkdirSync(legacyWs, { recursive: true });
    fs.writeFileSync(path.join(legacyWs, "AGENTS.md"), "legacy");

    adapter.writeTeam({
      name: "test-team",
      members: [{ name: "dev", role: "Developer" }],
    });

    assert.ok(!fs.existsSync(legacyWs), "Legacy workspace should be removed");
    assert.ok(
      fs.existsSync(path.join(tmpDir, ".openclaw", "agents", "trc-dev.md")),
      "New agent file should exist",
    );
  });

  it("uninstall removes agent files, skills, config entries, and knowledge", async () => {
    const { OpenClawAdapter } = await import("../adapters/openclaw.js");
    const adapter = new OpenClawAdapter("test-team");

    const team = {
      name: "test-team",
      members: [{ name: "dev", role: "developer" }],
      skills: [{ id: "tdd", description: "TDD", body: "Red green refactor." }],
    };

    adapter.writeTeam(team);
    adapter.writeKnowledge("# Knowledge");

    const actions = adapter.uninstall();
    assert.ok(actions.length > 0, "Should have uninstall actions");

    // Agent file should be removed
    assert.ok(
      !fs.existsSync(path.join(tmpDir, ".openclaw", "agents", "trc-dev.md")),
      "Agent file should be removed",
    );

    // Shared skills should be removed
    const sharedSkills = path.join(tmpDir, ".openclaw", "skills");
    if (fs.existsSync(sharedSkills)) {
      assert.deepEqual(
        fs.readdirSync(sharedSkills).filter((f) => f.startsWith("trc-")),
        [],
        "Shared skill dirs should be removed",
      );
    }

    // openclaw.json should have no trc- entries
    const config = JSON.parse(fs.readFileSync(path.join(tmpDir, ".openclaw", "openclaw.json"), "utf-8"));
    const trcAgents = config.agents.list.filter((a: { id: string }) => a.id.startsWith("trc-"));
    assert.equal(trcAgents.length, 0, "trc- agents should be removed from config");

    // Knowledge should be removed
    assert.ok(!fs.existsSync(path.join(tmpDir, ".openclaw", "knowledge-test-team.md")), "Knowledge should be removed");
  });

  it("does not create .agents/ directory in project", async () => {
    const { OpenClawAdapter } = await import("../adapters/openclaw.js");
    const adapter = new OpenClawAdapter();

    const team = {
      name: "test-team",
      members: [{ name: "dev", role: "developer" }],
    };

    adapter.writeTeam(team);

    assert.ok(!fs.existsSync(path.join(tmpDir, ".agents")), "Should NOT create .agents directory");
  });
});
