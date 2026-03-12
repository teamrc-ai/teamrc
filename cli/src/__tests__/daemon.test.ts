import { describe, it, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";
import { startDaemon } from "../daemon.js";
import type { PlatformAdapter } from "../adapters/base.js";
import type { TeamBridgeClient } from "../client.js";

function makeTmpDir(): string {
  return fs.mkdtempSync(path.join(os.tmpdir(), "daemon-test-"));
}

function createMockAdapter(tmpDir: string): PlatformAdapter {
  const teamFile = path.join(tmpDir, "agent-team.yaml");
  const knowledgeFile = path.join(tmpDir, "team-knowledge.md");

  return {
    readTeam: () => null,
    writeTeam: () => {},
    readKnowledge: () => {
      try { return fs.readFileSync(knowledgeFile, "utf-8"); } catch { return ""; }
    },
    writeKnowledge: (content: string) => fs.writeFileSync(knowledgeFile, content),
    appendKnowledge: () => {},
    getHashes: () => {
      const hashes: Record<string, string> = {};
      if (fs.existsSync(teamFile)) {
        hashes["team-spec"] = "hash-team";
      }
      if (fs.existsSync(knowledgeFile)) {
        hashes["knowledge:project"] = "hash-knowledge";
      }
      return hashes;
    },
    watchPaths: () => [teamFile, knowledgeFile],
    writeFile: (key: string, content: string) => {
      if (key === "team-spec") fs.writeFileSync(teamFile, content);
      if (key === "knowledge:project") fs.writeFileSync(knowledgeFile, content);
    },
    readFile: (key: string) => {
      try {
        if (key === "team-spec") return fs.readFileSync(teamFile, "utf-8");
        if (key === "knowledge:project") return fs.readFileSync(knowledgeFile, "utf-8");
      } catch { /* ignore */ }
      return null;
    },
  };
}

function createMockClient(responses: {
  syncCheck?: boolean;
  sync?: { changes: Record<string, { content: string; updated_at: number }> };
}): TeamBridgeClient & { calls: { method: string; args: unknown[] }[] } {
  const calls: { method: string; args: unknown[] }[] = [];

  return {
    calls,
    syncCheck: async (since: number) => {
      calls.push({ method: "syncCheck", args: [since] });
      return responses.syncCheck ?? false;
    },
    sync: async (platform: string, hashes: Record<string, string>, files?: Record<string, string>) => {
      calls.push({ method: "sync", args: [platform, hashes, files] });
      return responses.sync ?? { changes: {} };
    },
  } as unknown as ReturnType<typeof createMockClient>;
}

describe("daemon", () => {
  let tmpDir: string;

  beforeEach(() => {
    tmpDir = makeTmpDir();
  });

  afterEach(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  it("starts and stops without error", () => {
    const adapter = createMockAdapter(tmpDir);
    const client = createMockClient({});

    const daemon = startDaemon({
      adapter,
      client,
      platform: "claude-code",
      pollInterval: 60000,
    });

    daemon.stop();
  });

  it("performs initial sync check on start", async () => {
    const adapter = createMockAdapter(tmpDir);
    const client = createMockClient({ syncCheck: false });

    const daemon = startDaemon({
      adapter,
      client,
      platform: "claude-code",
      pollInterval: 60000,
    });

    // Give the initial async poll a moment to execute
    await new Promise((r) => setTimeout(r, 100));

    assert.ok(client.calls.some((c) => c.method === "syncCheck"));

    daemon.stop();
  });

  it("applies remote changes when syncCheck returns true", async () => {
    const adapter = createMockAdapter(tmpDir);
    const client = createMockClient({
      syncCheck: true,
      sync: { changes: { "team-spec": { content: "name: remote-team\nagents:\n  - name: a\n    role: r\n", updated_at: Math.floor(Date.now() / 1000) + 100 } } },
    });

    const daemon = startDaemon({
      adapter,
      client,
      platform: "claude-code",
      pollInterval: 60000,
    });

    await new Promise((r) => setTimeout(r, 200));

    // syncCheck should be called, then sync
    assert.ok(client.calls.some((c) => c.method === "syncCheck"));
    assert.ok(client.calls.some((c) => c.method === "sync"));

    // The file should have been written
    const teamFile = path.join(tmpDir, "agent-team.yaml");
    assert.ok(fs.existsSync(teamFile));
    const content = fs.readFileSync(teamFile, "utf-8");
    assert.ok(content.includes("remote-team"));

    daemon.stop();
  });
});
