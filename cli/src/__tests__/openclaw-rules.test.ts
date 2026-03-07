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

  it("includes rules and skills in AGENTS.md", async () => {
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
});
