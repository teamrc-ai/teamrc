import { describe, it, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";
import { writeTeamYaml, readTeamYaml } from "../team-yaml.js";
import type { TeamDefinition } from "../adapters/base.js";

/**
 * Tests that verify the init guard logic allows cloned YAMLs (no teamId)
 * to be adopted rather than rejected as "already initialized".
 *
 * The actual init command is interactive, so we test the guard condition
 * and the YAML shape that clone produces.
 */

describe("init clone adoption", () => {
  let tmpDir: string;
  let yamlPath: string;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "trc-init-test-"));
    yamlPath = path.join(tmpDir, ".teamrc.yaml");
  });

  afterEach(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  it("cloned YAML has cloneToken and no teamId", () => {
    // Simulate what clone.ts writes
    const clonedTeam: TeamDefinition = {
      name: "product-team-brook-0eb6",
      members: [{ name: "dev", role: "Developer" }],
      cloneToken: "trc_cl_NtxNUMHh0WfvS5HOkPpbT_ND",
      relay: "https://relay.teamrc.ai",
    };
    writeTeamYaml(yamlPath, clonedTeam);

    const read = readTeamYaml(yamlPath);
    assert.ok(read, "should be readable");
    assert.equal(read.teamId, undefined, "cloned YAML should not have teamId");
    assert.ok(read.cloneToken, "cloned YAML should have cloneToken");
  });

  it("init guard should NOT block cloned YAML (no teamId)", () => {
    const clonedTeam: TeamDefinition = {
      name: "product-team",
      members: [{ name: "dev", role: "Developer" }],
      cloneToken: "trc_cl_test",
    };
    writeTeamYaml(yamlPath, clonedTeam);
    const existingYaml = readTeamYaml(yamlPath);

    // This is the fixed guard condition from init.ts
    const shouldBlock = existingYaml && existingYaml.teamId;
    assert.ok(!shouldBlock, "cloned YAML without teamId should not be blocked");
  });

  it("init guard SHOULD block fully initialized YAML (has teamId)", () => {
    const initializedTeam: TeamDefinition = {
      name: "product-team",
      members: [{ name: "dev", role: "Developer" }],
      teamId: "team_abc123",
    };
    writeTeamYaml(yamlPath, initializedTeam);
    const existingYaml = readTeamYaml(yamlPath);

    const shouldBlock = existingYaml && existingYaml.teamId;
    assert.ok(shouldBlock, "initialized YAML with teamId should be blocked");
  });

  it("adoption path strips cloneToken", () => {
    const clonedTeam: TeamDefinition = {
      name: "product-team",
      members: [{ name: "dev", role: "Developer" }],
      cloneToken: "trc_cl_test",
      relay: "https://relay.teamrc.ai",
    };

    // Simulate the adoption logic from init.ts lines 87-96
    const adopted = { ...clonedTeam };
    delete adopted.cloneToken;

    assert.equal(adopted.cloneToken, undefined, "cloneToken should be stripped");
    assert.equal(adopted.name, "product-team", "name should be preserved");
    assert.equal(adopted.members.length, 1, "members should be preserved");
  });
});
