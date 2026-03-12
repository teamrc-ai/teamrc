import { describe, it, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";

describe("OpenClaw adapter (multi-agent workspaces)", () => {
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

  it("creates per-agent workspace directories", async () => {
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

    const architectWs = path.join(tmpDir, ".openclaw", "workspace-trc-architect");
    const devWs = path.join(tmpDir, ".openclaw", "workspace-trc-dev");
    assert.ok(fs.existsSync(architectWs), "architect workspace should exist");
    assert.ok(fs.existsSync(devWs), "dev workspace should exist");
  });

  it("writes AGENTS.md into each agent workspace with team info", async () => {
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

    const agentsMd = path.join(tmpDir, ".openclaw", "workspace-trc-architect", "AGENTS.md");
    assert.ok(fs.existsSync(agentsMd), "AGENTS.md should exist in workspace");

    const content = fs.readFileSync(agentsMd, "utf-8");
    assert.ok(content.includes("# Team: test-team"), "Should have team name");
    assert.ok(content.includes("architect"), "Should mention agent name");
    assert.ok(content.includes("**dev**"), "Should list teammate");
  });

  it("writes SOUL.md into each agent workspace with persona", async () => {
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

    const soulMd = path.join(tmpDir, ".openclaw", "workspace-trc-architect", "SOUL.md");
    assert.ok(fs.existsSync(soulMd), "SOUL.md should exist");

    const content = fs.readFileSync(soulMd, "utf-8");
    assert.ok(content.includes("teamrc-role: System architect"), "Should encode role");
    assert.ok(content.includes("You design distributed systems."), "Should have custom soul");
  });

  it("creates agent state directories", async () => {
    const { OpenClawAdapter } = await import("../adapters/openclaw.js");
    const adapter = new OpenClawAdapter();

    const team = {
      name: "test-team",
      members: [{ name: "dev", role: "Developer" }],
    };

    adapter.writeTeam(team);

    const agentDir = path.join(tmpDir, ".openclaw", "agents", "trc-dev", "agent");
    assert.ok(fs.existsSync(agentDir), "Agent state dir should exist at ~/.openclaw/agents/<id>/agent/");
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
    assert.ok(architectEntry.workspace.includes("workspace-trc-architect"), "Should have correct workspace path");
    assert.ok(architectEntry.agentDir.includes("agents/trc-architect/agent"), "Should have correct agentDir");
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

  it("writes per-agent skills to workspace/skills/", async () => {
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

    const wsSkillPath = path.join(
      tmpDir, ".openclaw", "workspace-trc-architect", "skills", "trc-skill-search", "SKILL.md",
    );
    assert.ok(fs.existsSync(wsSkillPath), "Per-agent skill should be in workspace/skills/");
  });

  it("writes shared skills to ~/.openclaw/skills/", async () => {
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

  it("readTeam parses openclaw.json + workspace files", async () => {
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
    const adapter = new OpenClawAdapter();

    assert.equal(adapter.readKnowledge(), "");

    adapter.writeKnowledge("# Knowledge\n\nSome content.");
    assert.equal(adapter.readKnowledge(), "# Knowledge\n\nSome content.");

    const knowledgePath = path.join(tmpDir, ".openclaw", "teamrc-knowledge.md");
    assert.ok(fs.existsSync(knowledgePath), "Knowledge should be in ~/.openclaw/");
  });

  it("uninstall removes workspaces, agent dirs, skills, config entries, and knowledge", async () => {
    const { OpenClawAdapter } = await import("../adapters/openclaw.js");
    const adapter = new OpenClawAdapter();

    const team = {
      name: "test-team",
      members: [{ name: "dev", role: "developer" }],
      skills: [{ id: "tdd", description: "TDD", body: "Red green refactor." }],
    };

    adapter.writeTeam(team);
    adapter.writeKnowledge("# Knowledge");

    const actions = adapter.uninstall();
    assert.ok(actions.length > 0, "Should have uninstall actions");

    // Workspace should be removed
    assert.ok(
      !fs.existsSync(path.join(tmpDir, ".openclaw", "workspace-trc-dev")),
      "Agent workspace should be removed",
    );

    // Agent state dir should be removed
    assert.ok(
      !fs.existsSync(path.join(tmpDir, ".openclaw", "agents", "trc-dev")),
      "Agent state dir should be removed",
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
    assert.ok(!fs.existsSync(path.join(tmpDir, ".openclaw", "teamrc-knowledge.md")), "Knowledge should be removed");
  });

  it("does not create .agents/ directory", async () => {
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
