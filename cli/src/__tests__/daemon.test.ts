import { describe, it, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";
import { startDaemon } from "../daemon.js";
import type { PlatformAdapter, TeamDefinition } from "../adapters/base.js";
import type { TeamrcClient, TeamrcTeam, TeamHeadResponse } from "../client.js";

function makeTmpDir(): string {
  return fs.mkdtempSync(path.join(os.tmpdir(), "daemon-test-"));
}

function createMockAdapter(tmpDir: string): PlatformAdapter & { writtenTeams: TeamDefinition[] } {
  const knowledgeFile = path.join(tmpDir, "teamrc-knowledge.md");
  const writtenTeams: TeamDefinition[] = [];

  return {
    writtenTeams,
    readTeam: () => null,
    writeTeam: (team: TeamDefinition) => { writtenTeams.push(team); },
    planWrite: () => [],
    readKnowledge: () => {
      try { return fs.readFileSync(knowledgeFile, "utf-8"); } catch { return ""; }
    },
    writeKnowledge: (content: string) => fs.writeFileSync(knowledgeFile, content),
    uninstall: () => [],
  };
}

function createMockClient(responses: {
  getTeam?: TeamrcTeam;
  getTeamHead?: TeamHeadResponse;
}): TeamrcClient & { calls: { method: string; args: unknown[] }[] } {
  const calls: { method: string; args: unknown[] }[] = [];
  const defaultHash = "abc123def456";
  const defaultHead: TeamHeadResponse = {
    hash: responses.getTeamHead?.hash ?? defaultHash,
    members_hash: responses.getTeamHead?.members_hash ?? "m_hash",
    skills_hash: responses.getTeamHead?.skills_hash ?? "s_hash",
    knowledge_hash: responses.getTeamHead?.knowledge_hash ?? "k_hash",
  };
  const defaultTeam: TeamrcTeam = {
    id: "test-id",
    name: "test-team",
    members: [{ name: "agent", role: "helper" }],
    hash: defaultHead.hash,
    members_hash: defaultHead.members_hash,
    skills_hash: defaultHead.skills_hash,
    knowledge_hash: defaultHead.knowledge_hash,
  };

  return {
    calls,
    getTeam: async (...args: unknown[]) => {
      calls.push({ method: "getTeam", args });
      return responses.getTeam ?? defaultTeam;
    },
    getTeamHead: async (...args: unknown[]) => {
      calls.push({ method: "getTeamHead", args });
      return responses.getTeamHead ?? defaultHead;
    },
    pushTeam: async (...args: unknown[]) => {
      calls.push({ method: "pushTeam", args });
      return responses.getTeam ?? defaultTeam;
    },
  } as unknown as ReturnType<typeof createMockClient>;
}

describe("daemon", () => {
  let tmpDir: string;
  let originalCwd: string;

  beforeEach(() => {
    tmpDir = makeTmpDir();
    originalCwd = process.cwd();
    process.chdir(tmpDir);

    // Create a .teamrc.yaml so the daemon can read it
    fs.writeFileSync(
      path.join(tmpDir, ".teamrc.yaml"),
      "name: test-team\nteamId: test-id\nrelay: http://localhost:4000\nplatforms:\n  - claude-code\nmembers:\n  - name: agent\n    role: helper\n",
    );
  });

  afterEach(() => {
    process.chdir(originalCwd);
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  it("starts and stops without error", () => {
    const adapter = createMockAdapter(tmpDir);
    const client = createMockClient({});

    const daemon = startDaemon({
      client,
      adapters: [adapter],
      platforms: ["claude-code"],
      pollInterval: 60000,
      watchYaml: false,
    });

    daemon.stop();
  });

  it("polls relay on start and calls getTeamHead", async () => {
    const adapter = createMockAdapter(tmpDir);
    const client = createMockClient({});

    const daemon = startDaemon({
      client,
      adapters: [adapter],
      platforms: ["claude-code"],
      pollInterval: 60000,
      watchYaml: false,
    });

    // Give the initial async poll a moment to execute
    await new Promise((r) => setTimeout(r, 200));

    assert.ok(client.calls.some((c) => c.method === "getTeamHead"));

    daemon.stop();
  });

  it("fetches full team when hash changes", async () => {
    const adapter = createMockAdapter(tmpDir);
    const remoteTeam: TeamrcTeam = {
      id: "test-id",
      name: "updated-team",
      members: [{ name: "agent", role: "updated-role" }],
      hash: "new-hash-123",
    };
    const head: TeamHeadResponse = {
      hash: "new-hash-123",
      members_hash: "new_m",
      skills_hash: "new_s",
      knowledge_hash: "new_k",
    };
    const client = createMockClient({ getTeam: remoteTeam, getTeamHead: head });

    const daemon = startDaemon({
      client,
      adapters: [adapter],
      platforms: ["claude-code"],
      pollInterval: 60000,
      watchYaml: false,
    });

    await new Promise((r) => setTimeout(r, 200));

    // The adapter should have received a writeTeam call
    assert.ok(adapter.writtenTeams.length > 0);
    assert.equal(adapter.writtenTeams[0].name, "updated-team");

    // Both getTeamHead and getTeam should have been called
    assert.ok(client.calls.some((c) => c.method === "getTeamHead"));
    assert.ok(client.calls.some((c) => c.method === "getTeam"));

    daemon.stop();
  });

  it("does not fetch full team when hash hasn't changed", async () => {
    const adapter = createMockAdapter(tmpDir);
    const fixedHash = "fixed-hash-value";
    const head: TeamHeadResponse = {
      hash: fixedHash,
      members_hash: "m",
      skills_hash: "s",
      knowledge_hash: "k",
    };
    const remoteTeam: TeamrcTeam = {
      id: "test-id",
      name: "test-team",
      members: [{ name: "agent", role: "helper" }],
      hash: fixedHash,
    };
    const client = createMockClient({ getTeam: remoteTeam, getTeamHead: head });

    const daemon = startDaemon({
      client,
      adapters: [adapter],
      platforms: ["claude-code"],
      pollInterval: 100, // fast poll for testing
      watchYaml: false,
    });

    // Wait for initial poll + one more
    await new Promise((r) => setTimeout(r, 350));

    // getTeamHead should be called multiple times
    const headCalls = client.calls.filter((c) => c.method === "getTeamHead");
    assert.ok(headCalls.length >= 2, `Expected at least 2 getTeamHead calls, got ${headCalls.length}`);

    // getTeam should only be called once (initial poll), then skipped when hash unchanged
    const getTeamCalls = client.calls.filter((c) => c.method === "getTeam");
    assert.equal(getTeamCalls.length, 1, "Should only fetch full team once when hash unchanged");

    // writeTeam should only be called once
    assert.equal(adapter.writtenTeams.length, 1, "Should only apply once when hash unchanged");

    daemon.stop();
  });

  it("writes sync hashes to state.json after pull", async () => {
    const adapter = createMockAdapter(tmpDir);
    const head: TeamHeadResponse = {
      hash: "sync-hash-abc",
      members_hash: "m_abc",
      skills_hash: "s_abc",
      knowledge_hash: "k_abc",
    };
    const remoteTeam: TeamrcTeam = {
      id: "test-id",
      name: "test-team",
      members: [{ name: "agent", role: "helper" }],
      hash: head.hash,
    };
    const client = createMockClient({ getTeam: remoteTeam, getTeamHead: head });

    const daemon = startDaemon({
      client,
      adapters: [adapter],
      platforms: ["claude-code"],
      pollInterval: 60000,
      watchYaml: false,
    });

    await new Promise((r) => setTimeout(r, 200));

    // Read state.json and check sync hashes were written
    const stateContent = fs.readFileSync(path.join(tmpDir, ".teamrc", "state.json"), "utf-8");
    const state = JSON.parse(stateContent);
    assert.equal(state.syncHash, "sync-hash-abc", "state.json should contain the actual hash value");
    assert.equal(state.syncHashMembers, "m_abc");
    assert.equal(state.syncHashSkills, "s_abc");
    assert.equal(state.syncHashKnowledge, "k_abc");
    assert.ok(state.lastPollAt, "state.json should contain lastPollAt");

    // YAML should NOT contain syncHash fields
    const yamlContent = fs.readFileSync(path.join(tmpDir, ".teamrc.yaml"), "utf-8");
    assert.ok(!yamlContent.includes("syncHash"), "YAML should NOT contain syncHash");

    daemon.stop();
  });

  it("merges remote knowledge with local knowledge", async () => {
    const adapter = createMockAdapter(tmpDir);

    // Write some local knowledge
    adapter.writeKnowledge("# Knowledge\n\n- local fact 1\n");

    const head: TeamHeadResponse = {
      hash: "knowledge-hash",
      members_hash: "m",
      skills_hash: "s",
      knowledge_hash: "k",
    };
    const remoteTeam: TeamrcTeam = {
      id: "test-id",
      name: "test-team",
      members: [{ name: "agent", role: "helper" }],
      knowledge: "# Knowledge\n\n- local fact 1\n- remote fact 2\n",
      hash: head.hash,
    };
    const client = createMockClient({ getTeam: remoteTeam, getTeamHead: head });

    const daemon = startDaemon({
      client,
      adapters: [adapter],
      platforms: ["claude-code"],
      pollInterval: 60000,
      watchYaml: false,
    });

    await new Promise((r) => setTimeout(r, 200));

    const knowledge = adapter.readKnowledge();
    assert.ok(knowledge.includes("local fact 1"), "Should keep local knowledge");
    assert.ok(knowledge.includes("remote fact 2"), "Should merge remote knowledge");

    daemon.stop();
  });

  it("never auto-pushes", async () => {
    const adapter = createMockAdapter(tmpDir);
    const client = createMockClient({});

    const daemon = startDaemon({
      client,
      adapters: [adapter],
      platforms: ["claude-code"],
      pollInterval: 60000,
      watchYaml: false,
    });

    await new Promise((r) => setTimeout(r, 200));

    // No pushTeam calls should have been made
    const pushCalls = client.calls.filter((c) => c.method === "pushTeam");
    assert.equal(pushCalls.length, 0, "Daemon should never auto-push");

    daemon.stop();
  });
});
