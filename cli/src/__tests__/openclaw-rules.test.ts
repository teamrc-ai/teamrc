import { describe, it, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";

describe("OpenClaw adapter (native OpenHands format)", () => {
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

  it("writes agent files to .agents/agents/ (global scope)", async () => {
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

    const globalAgentsDir = path.join(tmpDir, ".agents", "agents");
    assert.ok(fs.existsSync(path.join(globalAgentsDir, "trc-architect.md")), "architect agent file should exist");
    assert.ok(fs.existsSync(path.join(globalAgentsDir, "trc-dev.md")), "dev agent file should exist");

    // Verify YAML frontmatter format
    const content = fs.readFileSync(path.join(globalAgentsDir, "trc-architect.md"), "utf-8");
    assert.ok(content.startsWith("---\n"), "Should start with frontmatter");
    assert.ok(content.includes('name: "trc-architect"'), "Should have name in frontmatter");
    assert.ok(content.includes('description: "System architect"'), "Should have description in frontmatter");
    assert.ok(content.includes("# Team: test-team"), "Should have team header in body");
  });

  it("writes agent files to .agents/agents/ (project scope)", async () => {
    const { OpenClawAdapter } = await import("../adapters/openclaw.js");
    const adapter = new OpenClawAdapter();

    const team = {
      name: "my-project",
      members: [{ name: "dev", role: "Developer" }],
    };

    adapter.writeTeam(team, "project");

    const projectAgentsDir = path.join(tmpDir, ".agents", "agents");
    assert.ok(fs.existsSync(path.join(projectAgentsDir, "trc-dev.md")), "agent file should exist in project .agents/agents/");
  });

  it("includes native skills frontmatter for per-agent skills", async () => {
    const { OpenClawAdapter } = await import("../adapters/openclaw.js");
    const adapter = new OpenClawAdapter();

    const team = {
      name: "test-team",
      members: [
        { name: "architect", role: "design", skills: ["skill_search"] },
      ],
      skills: [{ id: "skill_search", description: "Search code", body: "Use grep." }],
    };

    adapter.writeTeam(team);

    const agentPath = path.join(tmpDir, ".agents", "agents", "trc-architect.md");
    const content = fs.readFileSync(agentPath, "utf-8");
    assert.ok(content.includes("skills:"), "Should have skills in frontmatter");
    assert.ok(content.includes("  - trc-skill_search"), "Should list skill ID in frontmatter");
    assert.ok(content.includes("## Skills"), "Should have Skills section in body");
    assert.ok(content.includes("Search code"), "Should include skill description in body");
  });

  it("writes skill directories to .agents/skills/", async () => {
    const { OpenClawAdapter } = await import("../adapters/openclaw.js");
    const adapter = new OpenClawAdapter();

    const team = {
      name: "test-team",
      members: [{ name: "dev", role: "developer" }],
      skills: [
        { id: "write-tests", title: "Write Tests", description: "Testing reqs", alwaysApply: true, body: "Write tests." },
        { id: "tdd", title: "TDD", description: "Test-driven dev", body: "Red green refactor." },
      ],
    };

    adapter.writeTeam(team, "project");

    const skillDir = path.join(tmpDir, ".agents", "skills");
    assert.ok(fs.existsSync(path.join(skillDir, "trc-write-tests", "SKILL.md")), "alwaysApply skill should be written");
    assert.ok(fs.existsSync(path.join(skillDir, "trc-tdd", "SKILL.md")), "on-demand skill should be written");

    const skillContent = fs.readFileSync(path.join(skillDir, "trc-tdd", "SKILL.md"), "utf-8");
    assert.ok(skillContent.includes("name: trc-tdd"), "SKILL.md should have name");
    assert.ok(skillContent.includes("Test-driven dev"), "SKILL.md should have description");
    assert.ok(skillContent.includes("Red green refactor."), "SKILL.md should have body");
  });

  it("writes AGENTS.md routing block", async () => {
    const { OpenClawAdapter } = await import("../adapters/openclaw.js");
    const adapter = new OpenClawAdapter();

    const team = {
      name: "my-project",
      members: [{ name: "dev", role: "developer" }],
    };

    adapter.writeTeam(team, "project");

    const agentsMd = path.join(tmpDir, "AGENTS.md");
    assert.ok(fs.existsSync(agentsMd), "AGENTS.md should exist at project root");

    const content = fs.readFileSync(agentsMd, "utf-8");
    assert.ok(content.includes("<!-- teamrc -->"), "Should have start marker");
    assert.ok(content.includes("<!-- /teamrc -->"), "Should have end marker");
    assert.ok(content.includes("teamrc Team: my-project"), "Should have team name");
    assert.ok(content.includes("**dev**"), "Should list agent");
  });

  it("readTeam parses agent files correctly", async () => {
    const { OpenClawAdapter } = await import("../adapters/openclaw.js");
    const adapter = new OpenClawAdapter();

    const team = {
      name: "test-team",
      members: [
        { name: "architect", role: "System architect", soul: "You design systems." },
        { name: "dev", role: "Developer" },
      ],
    };

    adapter.writeTeam(team, "project");

    const readTeam = adapter.readTeam();
    assert.ok(readTeam, "Should read team back");
    assert.equal(readTeam.name, "test-team");
    assert.equal(readTeam.members.length, 2);

    const architect = readTeam.members.find((m) => m.name === "architect");
    assert.ok(architect, "Should find architect");
    assert.equal(architect.role, "System architect");
    assert.equal(architect.soul, "You design systems.");
  });

  it("knowledge read/write works", async () => {
    const { OpenClawAdapter } = await import("../adapters/openclaw.js");
    const adapter = new OpenClawAdapter();

    assert.equal(adapter.readKnowledge(), "");

    adapter.writeKnowledge("# Knowledge\n\nSome content.");
    assert.equal(adapter.readKnowledge(), "# Knowledge\n\nSome content.");
  });

  it("uninstall removes agent files, skills, knowledge, and AGENTS.md section", async () => {
    const { OpenClawAdapter } = await import("../adapters/openclaw.js");
    const adapter = new OpenClawAdapter();

    const team = {
      name: "test-team",
      members: [{ name: "dev", role: "developer" }],
      skills: [{ id: "tdd", description: "TDD", body: "Red green refactor." }],
    };

    adapter.writeTeam(team, "project");
    adapter.writeKnowledge("# Knowledge");

    const actions = adapter.uninstall();
    assert.ok(actions.length > 0, "Should have uninstall actions");

    const agentsDir = path.join(tmpDir, ".agents", "agents");
    assert.deepEqual(
      fs.readdirSync(agentsDir).filter((f) => f.startsWith("trc-")),
      [],
      "Agent files should be removed",
    );

    const skillsDir = path.join(tmpDir, ".agents", "skills");
    if (fs.existsSync(skillsDir)) {
      assert.deepEqual(
        fs.readdirSync(skillsDir).filter((f) => f.startsWith("trc-")),
        [],
        "Skill dirs should be removed",
      );
    }

    // AGENTS.md should have teamrc section removed
    const agentsMd = path.join(tmpDir, "AGENTS.md");
    if (fs.existsSync(agentsMd)) {
      const content = fs.readFileSync(agentsMd, "utf-8");
      assert.ok(!content.includes("<!-- teamrc -->"), "teamrc markers should be removed");
    }
  });

  it("does not use workspace directories or openclaw.json", async () => {
    const { OpenClawAdapter } = await import("../adapters/openclaw.js");
    const adapter = new OpenClawAdapter();

    const team = {
      name: "test-team",
      members: [{ name: "dev", role: "developer" }],
    };

    adapter.writeTeam(team);

    // None of the old invented paths should exist
    assert.ok(!fs.existsSync(path.join(tmpDir, ".openclaw")), "Should NOT create .openclaw directory");
    assert.ok(!fs.existsSync(path.join(tmpDir, ".agents", "agents", "trc-dev", "SOUL.md")), "Should NOT create SOUL.md");
  });
});
