import { describe, it, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";

describe("OpenClaw agent files with rules and skills", () => {
  let tmpDir: string;
  let origHome: string | undefined;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "trc-oc-rules-"));
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

  it("includes rules and skills in AGENTS.md (global scope)", async () => {
    const { OpenClawAdapter } = await import("../adapters/openclaw.js");
    const adapter = new OpenClawAdapter();

    const team = {
      name: "test-team",
      members: [
        { name: "architect", role: "design", rules: ["rule_style"], skills: ["skill_search"] },
      ],
      rules: [{ id: "rule_style", title: "Code Style", body: "Use prettier." }],
      skills: [{ id: "skill_search", description: "Search code", body: "Use grep." }],
    };

    adapter.writeTeam(team);

    const agentsPath = path.join(tmpDir, ".openclaw", "workspaces", "trc-architect", "AGENTS.md");
    assert.ok(fs.existsSync(agentsPath), "AGENTS.md should exist");

    const content = fs.readFileSync(agentsPath, "utf-8");
    assert.ok(content.includes("## Rules"), "Should have Rules section");
    assert.ok(content.includes("Code Style"), "Should include rule title");
    assert.ok(content.includes("Use prettier."), "Should include rule body");
    assert.ok(content.includes("## Skills"), "Should have Skills section");
    assert.ok(content.includes("Search code"), "Should include skill description");
  });

  it("uses namespaced workspaces for project scope", async () => {
    const { OpenClawAdapter } = await import("../adapters/openclaw.js");
    const adapter = new OpenClawAdapter();

    const team = {
      name: "my-project",
      members: [
        { name: "dev", role: "developer" },
        { name: "qa", role: "tester" },
      ],
    };

    adapter.writeTeam(team, "project");

    const wsBase = path.join(tmpDir, ".openclaw", "workspaces");
    // Project scope: trc-{teamSlug}-{agentName}
    assert.ok(fs.existsSync(path.join(wsBase, "trc-my-project-dev")), "dev workspace should be namespaced");
    assert.ok(fs.existsSync(path.join(wsBase, "trc-my-project-qa")), "qa workspace should be namespaced");
    // Should NOT have global-style workspaces
    assert.ok(!fs.existsSync(path.join(wsBase, "trc-dev")), "Should not have global-style dev workspace");
    assert.ok(!fs.existsSync(path.join(wsBase, "trc-qa")), "Should not have global-style qa workspace");
  });

  it("uses global workspaces when scope is not project", async () => {
    const { OpenClawAdapter } = await import("../adapters/openclaw.js");
    const adapter = new OpenClawAdapter();

    const team = {
      name: "global-team",
      members: [{ name: "lead", role: "team lead" }],
    };

    adapter.writeTeam(team);

    const wsBase = path.join(tmpDir, ".openclaw", "workspaces");
    assert.ok(fs.existsSync(path.join(wsBase, "trc-lead")), "lead workspace should use global naming");
    assert.ok(!fs.existsSync(path.join(wsBase, "trc-global-team-lead")), "Should not have namespaced workspace");
  });

  it("writes team-scoped routing markers for project scope", async () => {
    const { OpenClawAdapter } = await import("../adapters/openclaw.js");
    const adapter = new OpenClawAdapter();

    const team = {
      name: "my-project",
      members: [{ name: "dev", role: "developer" }],
    };

    adapter.writeTeam(team, "project");

    const agentsMd = path.join(tmpDir, ".openclaw", "workspace", "AGENTS.md");
    assert.ok(fs.existsSync(agentsMd), "AGENTS.md should exist in default workspace");

    const content = fs.readFileSync(agentsMd, "utf-8");
    assert.ok(content.includes("<!-- teamrc:my-project:routing -->"), "Should have team-scoped start marker");
    assert.ok(content.includes("<!-- /teamrc:my-project:routing -->"), "Should have team-scoped end marker");
  });

  it("writes global routing markers when no scope", async () => {
    const { OpenClawAdapter } = await import("../adapters/openclaw.js");
    const adapter = new OpenClawAdapter();

    const team = {
      name: "global-team",
      members: [{ name: "dev", role: "developer" }],
    };

    adapter.writeTeam(team);

    const agentsMd = path.join(tmpDir, ".openclaw", "workspace", "AGENTS.md");
    const content = fs.readFileSync(agentsMd, "utf-8");
    assert.ok(content.includes("<!-- teamrc:routing -->"), "Should have global start marker");
    assert.ok(content.includes("<!-- /teamrc:routing -->"), "Should have global end marker");
  });

  it("uninstall removes both global and team-scoped workspaces and markers", async () => {
    const { OpenClawAdapter } = await import("../adapters/openclaw.js");
    const adapter = new OpenClawAdapter();

    // Write a global team
    adapter.writeTeam({ name: "global-team", members: [{ name: "lead", role: "lead" }] });
    // Write a project team
    adapter.writeTeam({ name: "proj-a", members: [{ name: "dev", role: "dev" }] }, "project");

    const wsBase = path.join(tmpDir, ".openclaw", "workspaces");
    assert.ok(fs.existsSync(path.join(wsBase, "trc-lead")), "global workspace exists before uninstall");
    assert.ok(fs.existsSync(path.join(wsBase, "trc-proj-a-dev")), "project workspace exists before uninstall");

    const actions = adapter.uninstall();
    assert.ok(actions.length > 0, "Should have uninstall actions");

    // All trc-* workspaces should be gone
    assert.ok(!fs.existsSync(path.join(wsBase, "trc-lead")), "global workspace removed");
    assert.ok(!fs.existsSync(path.join(wsBase, "trc-proj-a-dev")), "project workspace removed");

    // Routing markers should be removed from AGENTS.md
    const agentsMd = path.join(tmpDir, ".openclaw", "workspace", "AGENTS.md");
    if (fs.existsSync(agentsMd)) {
      const content = fs.readFileSync(agentsMd, "utf-8");
      assert.ok(!content.includes("teamrc:routing"), "routing markers should be removed");
      assert.ok(!content.includes("teamrc:proj-a:routing"), "team-scoped markers should be removed");
    }
  });
});
