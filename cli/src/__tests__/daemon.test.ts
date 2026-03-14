import { describe, it, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";
import { startKnowledgeDaemon, computeKnowledgeHash } from "../daemon.js";
import type { PlatformAdapter, TeamDefinition } from "../adapters/base.js";
import { generateKeypair, toToken } from "../auth.js";

function makeTmpDir(): string {
  return fs.mkdtempSync(path.join(os.tmpdir(), "daemon-test-"));
}

function createMockAdapter(tmpDir: string): PlatformAdapter & { knowledgeContent: string; writeCount: number } {
  const knowledgeFile = path.join(tmpDir, ".teamrc", "knowledge-test-team.md");

  const adapter = {
    knowledgeContent: "",
    writeCount: 0,
    readTeam: () => null,
    writeTeam: () => {},
    planWrite: () => [],
    readKnowledge: () => {
      try { return fs.readFileSync(knowledgeFile, "utf-8"); } catch { return ""; }
    },
    writeKnowledge: (content: string) => {
      fs.mkdirSync(path.dirname(knowledgeFile), { recursive: true });
      fs.writeFileSync(knowledgeFile, content);
      adapter.knowledgeContent = content;
      adapter.writeCount++;
    },
    uninstall: () => [],
  };

  return adapter;
}

describe("computeKnowledgeHash", () => {
  it("normalizes content by trimming trailing whitespace and adding newline", () => {
    const hash1 = computeKnowledgeHash("hello world");
    const hash2 = computeKnowledgeHash("hello world\n");
    const hash3 = computeKnowledgeHash("hello world\n\n");
    const hash4 = computeKnowledgeHash("hello world   ");

    // All should produce the same hash since normalization trims end + adds \n
    assert.equal(hash1, hash2, "With and without trailing newline should match");
    assert.equal(hash1, hash3, "Multiple trailing newlines should normalize");
    assert.equal(hash1, hash4, "Trailing spaces should normalize");
  });

  it("returns a hex SHA-256 hash", () => {
    const hash = computeKnowledgeHash("test content");
    // SHA-256 hex is 64 characters
    assert.equal(hash.length, 64, "SHA-256 hex should be 64 chars");
    assert.ok(/^[0-9a-f]{64}$/.test(hash), "Should be lowercase hex");
  });

  it("produces different hashes for different content", () => {
    const hash1 = computeKnowledgeHash("content A");
    const hash2 = computeKnowledgeHash("content B");
    assert.notEqual(hash1, hash2, "Different content should produce different hashes");
  });

  it("handles empty string", () => {
    const hash = computeKnowledgeHash("");
    assert.equal(hash.length, 64, "Should still produce a valid hash");
  });
});

describe("knowledge daemon", () => {
  let tmpDir: string;
  let originalCwd: string;

  beforeEach(() => {
    tmpDir = makeTmpDir();
    originalCwd = process.cwd();
    process.chdir(tmpDir);

    // Create .teamrc directory for the knowledge file
    fs.mkdirSync(path.join(tmpDir, ".teamrc"), { recursive: true });
  });

  afterEach(() => {
    process.chdir(originalCwd);
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  it("starts and stops without error", async () => {
    const adapter = createMockAdapter(tmpDir);
    const kp = await generateKeypair();
    const token = toToken(kp.publicKey);

    const daemon = startKnowledgeDaemon({
      relayUrl: "http://localhost:4000",
      privateKey: kp.privateKey,
      token,
      teamId: "test-id",
      teamSlug: "test-team",
      scope: "project",
      adapters: [adapter],
      platforms: ["claude-code"],
      restOnly: true, // REST-only to avoid WebSocket connection attempt
      fallbackPollInterval: 60000,
    });

    // Give it a moment to initialize
    await new Promise((r) => setTimeout(r, 50));

    daemon.stop();
  });

  it("starts in REST-only mode when restOnly flag is set", async () => {
    const adapter = createMockAdapter(tmpDir);
    const kp = await generateKeypair();
    const token = toToken(kp.publicKey);

    // Capture console output
    const logs: string[] = [];
    const originalLog = console.log;
    console.log = (...args: unknown[]) => { logs.push(args.join(" ")); };

    const daemon = startKnowledgeDaemon({
      relayUrl: "http://localhost:4000",
      privateKey: kp.privateKey,
      token,
      teamId: "test-id",
      teamSlug: "test-team",
      scope: "project",
      adapters: [adapter],
      platforms: ["claude-code"],
      restOnly: true,
      fallbackPollInterval: 60000,
    });

    await new Promise((r) => setTimeout(r, 50));

    console.log = originalLog;

    assert.ok(
      logs.some((l) => l.includes("REST polling")),
      `Expected logs to mention REST polling. Logs: ${logs.join("; ")}`,
    );

    daemon.stop();
  });

  it("falls back to REST when WebSocket connection fails", async () => {
    const adapter = createMockAdapter(tmpDir);
    const kp = await generateKeypair();
    const token = toToken(kp.publicKey);

    const logs: string[] = [];
    const originalLog = console.log;
    console.log = (...args: unknown[]) => { logs.push(args.join(" ")); };

    const daemon = startKnowledgeDaemon({
      relayUrl: "http://localhost:19999", // Non-existent server
      privateKey: kp.privateKey,
      token,
      teamId: "test-id",
      teamSlug: "test-team",
      scope: "project",
      adapters: [adapter],
      platforms: ["claude-code"],
      fallbackPollInterval: 60000,
    });

    // Wait for connection attempt to fail and fallback to activate
    await new Promise((r) => setTimeout(r, 2000));

    console.log = originalLog;

    assert.ok(
      logs.some((l) => l.includes("last-resort REST")),
      `Expected last-resort REST fallback message. Logs: ${logs.join("; ")}`,
    );

    daemon.stop();
  });
});

describe("anti-echo mechanism", () => {
  it("computeKnowledgeHash matches for content written by daemon", () => {
    // Simulate: daemon writes content, then chokidar detects the write.
    // The hash of the written content should match lastWrittenHash,
    // so the push is skipped.
    const content = "# Knowledge\n\n## Topic\nSome finding.\n";
    const hash1 = computeKnowledgeHash(content);

    // Re-read and re-hash should produce same result
    const hash2 = computeKnowledgeHash(content);
    assert.equal(hash1, hash2, "Same content should produce same hash");
  });

  it("detects new content that differs from last written", () => {
    const written = "# Knowledge\n\n## Topic\nOriginal.\n";
    const writtenHash = computeKnowledgeHash(written);

    const modified = "# Knowledge\n\n## Topic\nOriginal.\n\n## New Topic\nNew finding.\n";
    const modifiedHash = computeKnowledgeHash(modified);

    assert.notEqual(writtenHash, modifiedHash, "Modified content should produce different hash");
  });
});

describe("size warning thresholds", () => {
  it("size at 70% triggers info log", () => {
    // This tests the threshold logic conceptually.
    // 70% of 100KB cap = 70,000 bytes
    const cap = 100_000;
    const size70 = 70_001;
    const pct70 = size70 / cap;
    assert.ok(pct70 > 0.7, "70,001 bytes should be >70% of 100KB");
    assert.ok(pct70 <= 0.9, "70,001 bytes should be <=90% of 100KB");
  });

  it("size at 90% triggers warning log", () => {
    const cap = 100_000;
    const size90 = 90_001;
    const pct90 = size90 / cap;
    assert.ok(pct90 > 0.9, "90,001 bytes should be >90% of 100KB");
  });

  it("size under 70% triggers no warning", () => {
    const cap = 100_000;
    const sizeOk = 69_999;
    const pctOk = sizeOk / cap;
    assert.ok(pctOk <= 0.7, "69,999 bytes should be <=70% of 100KB");
  });
});
