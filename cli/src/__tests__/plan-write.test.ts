import { describe, it, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";
import type { TeamDefinition } from "../adapters/base.js";

function makeTmpDir(): string {
  return fs.mkdtempSync(path.join(os.tmpdir(), "planwrite-test-"));
}

const team: TeamDefinition = {
  name: "test-team",
  members: [
    { name: "dev", role: "developer" },
    { name: "reviewer", role: "code reviewer" },
  ],
  skills: [
    { id: "tdd", body: "Write tests first.", alwaysApply: true },
    { id: "docs", body: "Write docs.", description: "Documentation" },
  ],
};

describe("planWrite", () => {
  let tmpDir: string;
  let originalCwd: string;

  beforeEach(() => {
    tmpDir = makeTmpDir();
    originalCwd = process.cwd();
    process.chdir(tmpDir);
  });

  afterEach(() => {
    process.chdir(originalCwd);
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  it("claude-code: reports creates on empty dir", async () => {
    const { ClaudeCodeAdapter } = await import("../adapters/claude-code.js");
    const adapter = new ClaudeCodeAdapter();
    const actions = adapter.planWrite(team, "project");

    assert.ok(actions.length > 0, "Should have planned actions");
    const creates = actions.filter((a) => a.type === "create");
    assert.ok(creates.length >= 2, "Should create at least 2 agent files");
    assert.ok(actions.some((a) => a.description === "agent: dev"));
    assert.ok(actions.some((a) => a.description === "agent: reviewer"));
  });

  it("claude-code: reports updates when files exist", async () => {
    const { ClaudeCodeAdapter } = await import("../adapters/claude-code.js");
    const adapter = new ClaudeCodeAdapter();

    // First write
    adapter.writeTeam(team, "project");

    // Plan a second write
    const actions = adapter.planWrite(team, "project");
    const updates = actions.filter((a) => a.type === "update");
    assert.ok(updates.length >= 2, "Should report updates for existing files");
  });

  it("claude-code: reports deletes for orphaned agents", async () => {
    const { ClaudeCodeAdapter } = await import("../adapters/claude-code.js");
    const adapter = new ClaudeCodeAdapter();

    // Write with two agents
    adapter.writeTeam(team, "project");

    // Plan with only one agent
    const smallTeam: TeamDefinition = {
      name: "test-team",
      members: [{ name: "dev", role: "developer" }],
    };
    const actions = adapter.planWrite(smallTeam, "project");
    const deletes = actions.filter((a) => a.type === "delete");
    assert.ok(deletes.length >= 1, "Should plan deletion of orphaned agent");
  });

  it("cursor: plans agents, rules, and skills", async () => {
    const { CursorAdapter } = await import("../adapters/cursor.js");
    const adapter = new CursorAdapter();
    const actions = adapter.planWrite(team);

    assert.ok(actions.some((a) => a.description === "agent: dev"));
    assert.ok(actions.some((a) => a.description === "rule: tdd"));
    assert.ok(actions.some((a) => a.description === "skill: docs"));
    assert.ok(actions.some((a) => a.description === "teamrc routing"));
  });

  it("codex: plans toml agents, config, skills, and AGENTS.md", async () => {
    const { CodexAdapter } = await import("../adapters/codex.js");
    const adapter = new CodexAdapter();
    const actions = adapter.planWrite(team);

    assert.ok(actions.some((a) => a.description === "agent: dev"));
    assert.ok(actions.some((a) => a.description === "agent registration"));
    assert.ok(actions.some((a) => a.description === "skill: docs"));
    assert.ok(actions.some((a) => a.description === "team routing"));
  });

  it("gemini: plans agents, skills, and GEMINI.md", async () => {
    const { GeminiAdapter } = await import("../adapters/gemini.js");
    const adapter = new GeminiAdapter();
    const actions = adapter.planWrite(team, "project");

    assert.ok(actions.some((a) => a.description === "agent: dev"));
    assert.ok(actions.some((a) => a.description === "skill: docs"));
    assert.ok(actions.some((a) => a.description === "teamrc section"));
  });

  it("openclaw: plans agent files, shared skills, and openclaw.json", async () => {
    const { OpenClawAdapter } = await import("../adapters/openclaw.js");
    const origHome = process.env.HOME;
    process.env.HOME = tmpDir;
    try {
      const adapter = new OpenClawAdapter();
      const actions = adapter.planWrite(team);

      assert.ok(actions.some((a) => a.description === "agent: dev"), "Should plan agent file");
      assert.ok(actions.some((a) => a.description === "agent: reviewer"), "Should plan reviewer file");
      assert.ok(actions.some((a) => a.description?.startsWith("skill:")), "Should plan skills");
      assert.ok(actions.some((a) => a.description === "agent registration"), "Should plan openclaw.json update");
    } finally {
      if (origHome !== undefined) process.env.HOME = origHome;
      else delete process.env.HOME;
    }
  });
});
