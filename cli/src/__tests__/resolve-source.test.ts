import { describe, it, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";
import { resolveTeamSource, resolveBody } from "../resolve-source.js";
import type { TeamDefinition } from "../adapters/base.js";

describe("resolveTeamSource", () => {
  let tmpDir: string;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "trc-resolve-"));
  });

  afterEach(() => {
    fs.rmSync(tmpDir, { recursive: true });
  });

  it("returns YAML source when agent-team.yaml exists", () => {
    const yamlPath = path.join(tmpDir, "agent-team.yaml");
    fs.writeFileSync(yamlPath, "name: yaml-team\nmembers:\n  - name: a\n    role: r\n");

    const adapterTeam: TeamDefinition = { name: "adapter-team", members: [{ name: "b", role: "s" }] };

    const result = resolveTeamSource(yamlPath, adapterTeam);
    assert.equal(result.source, "yaml");
    assert.equal(result.team!.name, "yaml-team");
  });

  it("falls back to adapter when no YAML exists", () => {
    const yamlPath = path.join(tmpDir, "agent-team.yaml");
    const adapterTeam: TeamDefinition = { name: "adapter-team", members: [{ name: "b", role: "s" }] };

    const result = resolveTeamSource(yamlPath, adapterTeam);
    assert.equal(result.source, "platform");
    assert.equal(result.team!.name, "adapter-team");
  });

  it("returns null team when nothing available", () => {
    const yamlPath = path.join(tmpDir, "agent-team.yaml");

    const result = resolveTeamSource(yamlPath, null);
    assert.equal(result.source, "none");
    assert.equal(result.team, null);
  });
});

describe("resolveBody", () => {
  let tmpDir: string;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "trc-resolve-"));
  });

  afterEach(() => {
    fs.rmSync(tmpDir, { recursive: true });
  });

  it("returns string body as-is", () => {
    const result = resolveBody("Use prettier.", tmpDir);
    assert.equal(result, "Use prettier.");
  });

  it("resolves file source reference", () => {
    const rulePath = path.join(tmpDir, "rules", "style.md");
    fs.mkdirSync(path.join(tmpDir, "rules"), { recursive: true });
    fs.writeFileSync(rulePath, "# Style Guide\nUse tabs.");

    const result = resolveBody({ source: "./rules/style.md" }, tmpDir);
    assert.equal(result, "# Style Guide\nUse tabs.");
  });

  it("returns empty string for missing file", () => {
    const result = resolveBody({ source: "./nonexistent.md" }, tmpDir);
    assert.equal(result, "");
  });

  it("returns empty string for undefined body", () => {
    const result = resolveBody(undefined, tmpDir);
    assert.equal(result, "");
  });

  it("blocks absolute path traversal", () => {
    assert.throws(
      () => resolveBody({ source: "/etc/hosts" }, tmpDir),
      /Path traversal blocked/,
    );
  });

  it("blocks relative path traversal", () => {
    assert.throws(
      () => resolveBody({ source: "../../etc/hosts" }, tmpDir),
      /Path traversal blocked/,
    );
  });

  it("blocks parent directory escape", () => {
    assert.throws(
      () => resolveBody({ source: "../outside.txt" }, tmpDir),
      /Path traversal blocked/,
    );
  });
});
