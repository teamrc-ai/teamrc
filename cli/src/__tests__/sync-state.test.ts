import { describe, it, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";
import { readSyncState, writeSyncState, migrateLegacySyncHashes, migrateLegacyYamlHashes } from "../sync-state.js";

describe("readSyncState", () => {
  let tmpDir: string;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "trc-state-"));
  });

  afterEach(() => {
    fs.rmSync(tmpDir, { recursive: true });
  });

  it("returns empty object when state.json does not exist", () => {
    const result = readSyncState(tmpDir);
    assert.deepEqual(result, {});
  });

  it("reads a valid state.json", () => {
    const stateDir = path.join(tmpDir, ".teamrc");
    fs.mkdirSync(stateDir, { recursive: true });
    fs.writeFileSync(
      path.join(stateDir, "state.json"),
      JSON.stringify({
        syncHash: "abc123",
        syncHashMembers: "m_hash",
        syncHashSkills: "s_hash",
        syncHashKnowledge: "k_hash",
        lastPollAt: "2026-03-12T10:00:00Z",
      }),
    );

    const result = readSyncState(tmpDir);
    assert.equal(result.syncHash, "abc123");
    assert.equal(result.syncHashMembers, "m_hash");
    assert.equal(result.syncHashSkills, "s_hash");
    assert.equal(result.syncHashKnowledge, "k_hash");
    assert.equal(result.lastPollAt, "2026-03-12T10:00:00Z");
  });

  it("returns empty object for corrupted state.json", () => {
    const stateDir = path.join(tmpDir, ".teamrc");
    fs.mkdirSync(stateDir, { recursive: true });
    fs.writeFileSync(path.join(stateDir, "state.json"), "not json{{{");

    const result = readSyncState(tmpDir);
    assert.deepEqual(result, {});
  });

  it("handles partial state.json", () => {
    const stateDir = path.join(tmpDir, ".teamrc");
    fs.mkdirSync(stateDir, { recursive: true });
    fs.writeFileSync(
      path.join(stateDir, "state.json"),
      JSON.stringify({ syncHash: "only-hash" }),
    );

    const result = readSyncState(tmpDir);
    assert.equal(result.syncHash, "only-hash");
    assert.equal(result.syncHashMembers, undefined);
  });
});

describe("writeSyncState", () => {
  let tmpDir: string;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "trc-state-"));
  });

  afterEach(() => {
    fs.rmSync(tmpDir, { recursive: true });
  });

  it("creates .teamrc/ directory and state.json", () => {
    writeSyncState(
      {
        syncHash: "abc123",
        syncHashMembers: "m_hash",
        syncHashSkills: "s_hash",
        syncHashKnowledge: "k_hash",
      },
      tmpDir,
    );

    const stateDir = path.join(tmpDir, ".teamrc");
    assert.ok(fs.existsSync(stateDir), ".teamrc/ directory should exist");

    const statePath = path.join(stateDir, "state.json");
    assert.ok(fs.existsSync(statePath), "state.json should exist");

    const content = JSON.parse(fs.readFileSync(statePath, "utf-8"));
    assert.equal(content.syncHash, "abc123");
    assert.equal(content.syncHashMembers, "m_hash");
  });

  it("overwrites existing state.json", () => {
    writeSyncState({ syncHash: "first" }, tmpDir);
    writeSyncState({ syncHash: "second" }, tmpDir);

    const result = readSyncState(tmpDir);
    assert.equal(result.syncHash, "second");
  });

  it("atomic write leaves no temp files", () => {
    writeSyncState({ syncHash: "atomic-test" }, tmpDir);

    const stateDir = path.join(tmpDir, ".teamrc");
    const files = fs.readdirSync(stateDir);
    assert.equal(files.length, 1, "only state.json should exist, no temp files");
    assert.equal(files[0], "state.json");
  });

  it("roundtrips correctly", () => {
    const state = {
      syncHash: "hash123",
      syncHashMembers: "m123",
      syncHashSkills: "s123",
      syncHashKnowledge: "k123",
      lastPollAt: "2026-03-12T12:00:00.000Z",
    };

    writeSyncState(state, tmpDir);
    const result = readSyncState(tmpDir);
    assert.deepEqual(result, state);
  });
});

describe("migrateLegacySyncHashes", () => {
  let tmpDir: string;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "trc-migrate-"));
  });

  afterEach(() => {
    fs.rmSync(tmpDir, { recursive: true });
  });

  it("migrates legacy syncHash fields to state.json", () => {
    const yamlData = {
      syncHash: "legacy-hash",
      syncHashMembers: "legacy-m",
      syncHashSkills: "legacy-s",
      syncHashKnowledge: "legacy-k",
    };

    const migrated = migrateLegacySyncHashes(yamlData, tmpDir);
    assert.ok(migrated, "should return true when migration occurs");

    const state = readSyncState(tmpDir);
    assert.equal(state.syncHash, "legacy-hash");
    assert.equal(state.syncHashMembers, "legacy-m");
    assert.equal(state.syncHashSkills, "legacy-s");
    assert.equal(state.syncHashKnowledge, "legacy-k");
  });

  it("returns false when no legacy hashes exist", () => {
    const yamlData = {};
    const migrated = migrateLegacySyncHashes(yamlData, tmpDir);
    assert.ok(!migrated, "should return false when no legacy hashes");
  });

  it("does not overwrite existing state.json", () => {
    writeSyncState({ syncHash: "existing-hash" }, tmpDir);

    const yamlData = {
      syncHash: "legacy-hash",
      syncHashMembers: "legacy-m",
    };

    const migrated = migrateLegacySyncHashes(yamlData, tmpDir);
    assert.ok(!migrated, "should not migrate when state.json already has hashes");

    const state = readSyncState(tmpDir);
    assert.equal(state.syncHash, "existing-hash");
  });
});

describe("migrateLegacyYamlHashes", () => {
  let tmpDir: string;

  beforeEach(() => {
    tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), "trc-yaml-migrate-"));
  });

  afterEach(() => {
    fs.rmSync(tmpDir, { recursive: true });
  });

  it("migrates syncHash fields from YAML to state.json and rewrites YAML", () => {
    const yamlPath = path.join(tmpDir, ".teamrc.yaml");
    fs.writeFileSync(yamlPath, `name: my-team
syncHash: legacy-hash
syncHashMembers: legacy-m
syncHashSkills: legacy-s
syncHashKnowledge: legacy-k
members:
  - name: agent
    role: helper
`);

    migrateLegacyYamlHashes(yamlPath, tmpDir);

    // State.json should have the migrated hashes
    const state = readSyncState(tmpDir);
    assert.equal(state.syncHash, "legacy-hash");
    assert.equal(state.syncHashMembers, "legacy-m");
    assert.equal(state.syncHashSkills, "legacy-s");
    assert.equal(state.syncHashKnowledge, "legacy-k");

    // YAML should no longer contain syncHash fields
    const yamlContent = fs.readFileSync(yamlPath, "utf-8");
    assert.ok(!yamlContent.includes("syncHash"), "YAML should not contain syncHash after migration");
    assert.ok(yamlContent.includes("my-team"), "YAML should still contain team name");
    assert.ok(yamlContent.includes("agent"), "YAML should still contain members");
  });

  it("does nothing when YAML has no legacy hashes", () => {
    const yamlPath = path.join(tmpDir, ".teamrc.yaml");
    fs.writeFileSync(yamlPath, `name: clean-team
members:
  - name: agent
    role: helper
`);

    migrateLegacyYamlHashes(yamlPath, tmpDir);

    // No state.json should be created
    const state = readSyncState(tmpDir);
    assert.deepEqual(state, {});
  });

  it("does nothing when state.json already exists", () => {
    writeSyncState({ syncHash: "existing" }, tmpDir);

    const yamlPath = path.join(tmpDir, ".teamrc.yaml");
    fs.writeFileSync(yamlPath, `name: my-team
syncHash: legacy-hash
members:
  - name: agent
    role: helper
`);

    migrateLegacyYamlHashes(yamlPath, tmpDir);

    // State.json should still have the original hash
    const state = readSyncState(tmpDir);
    assert.equal(state.syncHash, "existing");

    // YAML should NOT be rewritten (migration was skipped)
    const yamlContent = fs.readFileSync(yamlPath, "utf-8");
    assert.ok(yamlContent.includes("syncHash"), "YAML should not be rewritten when migration is skipped");
  });

  it("handles missing YAML file gracefully", () => {
    const yamlPath = path.join(tmpDir, "nonexistent.yaml");
    // Should not throw
    migrateLegacyYamlHashes(yamlPath, tmpDir);
    const state = readSyncState(tmpDir);
    assert.deepEqual(state, {});
  });
});
