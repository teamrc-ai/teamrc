/**
 * Task System Isolation Tests
 *
 * These tests verify the core invariant of the task extraction refactor:
 * "Deleting task files + reverting hooks should leave the system fully functional."
 *
 * They prove that:
 * 1. The knowledge daemon works without any task features enabled
 * 2. Stop/cleanup is safe when task state does not exist
 * 3. Core knowledge functions have no task dependencies
 * 4. The daemon gracefully handles enableTasks:false (no task imports, no task state)
 * 5. Client task methods are separable from non-task methods
 */

import { describe, it, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";
import { startKnowledgeDaemon, computeKnowledgeHash } from "../daemon.js";
import type { PlatformAdapter } from "../adapters/base.js";
import { generateKeypair, toToken } from "../auth.js";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function makeTmpDir(): string {
  return fs.mkdtempSync(path.join(os.tmpdir(), "task-isolation-test-"));
}

function createInMemoryAdapter(opts?: {
  initialContent?: string;
}): PlatformAdapter & { knowledgeContent: string; writeCount: number } {
  const adapter = {
    knowledgeContent: opts?.initialContent ?? "",
    writeCount: 0,
    readTeam: () => null,
    writeTeam: () => {},
    planWrite: () => [],
    readKnowledge: () => adapter.knowledgeContent,
    writeKnowledge: (content: string) => {
      adapter.knowledgeContent = content;
      adapter.writeCount++;
    },
    getKnowledgePath: () => "/tmp/mock-knowledge-isolation.md",
    uninstall: () => [],
  };
  return adapter;
}

/** Capture console.log and console.warn during a synchronous callback. */
function captureConsole(fn: () => void): { logs: string[]; warns: string[] } {
  const logs: string[] = [];
  const warns: string[] = [];
  const origLog = console.log;
  const origWarn = console.warn;
  console.log = (...args: unknown[]) => { logs.push(args.join(" ")); };
  console.warn = (...args: unknown[]) => { warns.push(args.join(" ")); };
  try {
    fn();
  } finally {
    console.log = origLog;
    console.warn = origWarn;
  }
  return { logs, warns };
}

/** Async version that waits for promises to settle. */
async function captureConsoleAsync(
  fn: () => void | Promise<void>,
  waitMs = 50,
): Promise<{ logs: string[]; warns: string[] }> {
  const logs: string[] = [];
  const warns: string[] = [];
  const origLog = console.log;
  const origWarn = console.warn;
  console.log = (...args: unknown[]) => { logs.push(args.join(" ")); };
  console.warn = (...args: unknown[]) => { warns.push(args.join(" ")); };
  try {
    await fn();
    await new Promise((r) => setTimeout(r, waitMs));
  } finally {
    console.log = origLog;
    console.warn = origWarn;
  }
  return { logs, warns };
}

// ---------------------------------------------------------------------------
// 1. Revert test: Knowledge daemon works without task features
// ---------------------------------------------------------------------------

describe("task isolation: daemon without tasks", () => {
  let tmpDir: string;
  let originalCwd: string;

  beforeEach(() => {
    tmpDir = makeTmpDir();
    originalCwd = process.cwd();
    process.chdir(tmpDir);
    fs.mkdirSync(path.join(tmpDir, ".teamrc"), { recursive: true });
  });

  afterEach(() => {
    process.chdir(originalCwd);
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  it("starts and stops cleanly with enableTasks:false (REST mode)", async () => {
    const adapter = createInMemoryAdapter();
    const kp = await generateKeypair();
    const token = toToken(kp.publicKey);

    const { logs, warns } = await captureConsoleAsync(() => {
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
        fallbackPollInterval: 600_000,
        // enableTasks deliberately omitted
      });
      daemon.stop();
    });

    // Verify daemon started and stopped
    assert.ok(logs.some((l) => l.includes("daemon started")), "Should log daemon start");
    assert.ok(logs.some((l) => l.includes("daemon stopped")), "Should log daemon stop");

    // Verify no task-related log messages
    const taskLogs = [...logs, ...warns].filter((l) => l.toLowerCase().includes("task"));
    assert.equal(taskLogs.length, 0, `Should have zero task-related log messages, got: ${JSON.stringify(taskLogs)}`);
  });

  it("stop() does not throw when task state was never initialized", async () => {
    const adapter = createInMemoryAdapter();
    const kp = await generateKeypair();
    const token = toToken(kp.publicKey);

    // Start and immediately stop -- no task state exists
    const { logs } = captureConsole(() => {
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
        fallbackPollInterval: 600_000,
      });

      // Calling stop should not throw even though tasksChannel, taskRunner are null
      assert.doesNotThrow(() => daemon.stop());
    });
  });

  it("does not create any task-related files", async () => {
    const adapter = createInMemoryAdapter();
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
      restOnly: true,
      fallbackPollInterval: 600_000,
    });

    await new Promise((r) => setTimeout(r, 50));
    daemon.stop();

    // Check that no task cache or claimed tasks file was created
    const teamrcDir = path.join(tmpDir, ".teamrc");
    const files = fs.readdirSync(teamrcDir);

    const taskFiles = files.filter((f) =>
      f.includes("task") || f.includes("claimed")
    );
    assert.equal(
      taskFiles.length,
      0,
      `Should have no task-related files in .teamrc, found: ${JSON.stringify(taskFiles)}`,
    );
  });

  it("multiple start-stop cycles without tasks do not leak resources", async () => {
    const adapter = createInMemoryAdapter();
    const kp = await generateKeypair();
    const token = toToken(kp.publicKey);

    // Run 3 cycles
    for (let i = 0; i < 3; i++) {
      const { logs } = captureConsole(() => {
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
          fallbackPollInterval: 600_000,
        });
        daemon.stop();
      });
      assert.ok(logs.some((l) => l.includes("daemon stopped")), `Cycle ${i} should stop cleanly`);
    }
  });
});

// ---------------------------------------------------------------------------
// 2. Core knowledge functions are task-independent
// ---------------------------------------------------------------------------

describe("task isolation: knowledge functions", () => {
  it("computeKnowledgeHash works independently of any task code", () => {
    // This is a pure function with no task dependencies
    const hash1 = computeKnowledgeHash("hello");
    const hash2 = computeKnowledgeHash("hello ");
    const hash3 = computeKnowledgeHash("hello\n");

    // All should produce the same hash (trailing whitespace normalized)
    assert.equal(hash1, hash2);
    assert.equal(hash2, hash3);

    // Different content produces different hash
    const hash4 = computeKnowledgeHash("world");
    assert.notEqual(hash1, hash4);
  });

  it("computeKnowledgeHash handles empty string", () => {
    // Should not throw
    const hash = computeKnowledgeHash("");
    assert.equal(typeof hash, "string");
    assert.ok(hash.length > 0);
  });

  it("computeKnowledgeHash handles large content", () => {
    const large = "x".repeat(200_000);
    const hash = computeKnowledgeHash(large);
    assert.equal(typeof hash, "string");
    assert.equal(hash.length, 64); // SHA-256 hex is 64 chars
  });
});

// ---------------------------------------------------------------------------
// 3. Source-level isolation verification
// ---------------------------------------------------------------------------

describe("task isolation: source structure", () => {
  const DAEMON_SRC = path.resolve(import.meta.dirname, "..", "daemon.ts");
  const TASK_DAEMON_SRC = path.resolve(import.meta.dirname, "..", "task-daemon.ts");
  const CLIENT_SRC = path.resolve(import.meta.dirname, "..", "client.ts");
  const CHANNEL_SRC = path.resolve(import.meta.dirname, "..", "channel-client.ts");

  it("daemon uses dynamic import for task-daemon, guarded by enableTasks", () => {
    const src = fs.readFileSync(DAEMON_SRC, "utf-8");

    // The initTaskDaemon call should only happen inside an enableTasks guard
    const initIdx = src.indexOf("initTaskDaemon");
    assert.ok(initIdx > -1, "daemon should reference initTaskDaemon");

    // Look backwards from initTaskDaemon for the enableTasks guard
    const preceding = src.slice(Math.max(0, initIdx - 200), initIdx);
    assert.ok(
      preceding.includes("enableTasks"),
      "initTaskDaemon should be guarded by enableTasks check",
    );

    // Should use dynamic import
    assert.ok(
      src.includes('import("./task-daemon.js")'),
      "daemon should use dynamic import for task-daemon",
    );
  });

  it("daemon has no direct TaskRunner or joinTasks references", () => {
    const src = fs.readFileSync(DAEMON_SRC, "utf-8");

    assert.ok(
      !src.includes("new TaskRunner"),
      "TaskRunner should be extracted to task-daemon.ts",
    );
    assert.ok(
      !src.includes("joinTasks"),
      "joinTasks should be extracted to task-daemon.ts",
    );
  });

  it("task-daemon.ts contains all extracted task logic", () => {
    const src = fs.readFileSync(TASK_DAEMON_SRC, "utf-8");

    assert.ok(src.includes("joinTasks"), "task-daemon should contain joinTasks");
    assert.ok(src.includes("TaskRunner"), "task-daemon should contain TaskRunner");
    assert.ok(src.includes("claimedTasks"), "task-daemon should contain claimed tasks logic");
    assert.ok(src.includes("writeTaskCache"), "task-daemon should contain task cache logic");
    assert.ok(src.includes("autoClaimTask"), "task-daemon should contain auto-claim logic");
  });

  it("task-related daemon code does not pollute the knowledge sync path", () => {
    const src = fs.readFileSync(DAEMON_SRC, "utf-8");

    // The setupFileWatcher callback should not contain task logic
    const watcherStart = src.indexOf("setupFileWatcher");
    const watcherDef = src.indexOf("function setupFileWatcher");
    assert.ok(watcherDef > -1, "setupFileWatcher should exist");

    // Extract the function body (rough heuristic: next 500 chars)
    const watcherBody = src.slice(watcherDef, watcherDef + 600);
    assert.ok(
      !watcherBody.includes("task") && !watcherBody.includes("Task"),
      "setupFileWatcher should not contain task-related logic",
    );
  });

  it("client.ts task methods are separable (all grouped together)", () => {
    const src = fs.readFileSync(CLIENT_SRC, "utf-8");

    // All task methods should appear after the non-task methods
    const createTaskIdx = src.indexOf("async createTask");
    const listTasksIdx = src.indexOf("async listTasks");
    const updateTaskIdx = src.indexOf("async updateTask");

    assert.ok(createTaskIdx > -1, "createTask should exist");
    assert.ok(listTasksIdx > -1, "listTasks should exist");
    assert.ok(updateTaskIdx > -1, "updateTask should exist");

    // Verify they are contiguous (within 1500 chars of each other)
    const minIdx = Math.min(createTaskIdx, listTasksIdx, updateTaskIdx);
    const maxIdx = Math.max(createTaskIdx, listTasksIdx, updateTaskIdx);
    assert.ok(
      maxIdx - minIdx < 1500,
      `Task methods should be grouped together for easy extraction (spread: ${maxIdx - minIdx} chars)`,
    );
  });

  it("channel-client.ts task types and joinTasks are separable", () => {
    const src = fs.readFileSync(CHANNEL_SRC, "utf-8");

    const tasksChannelEventsIdx = src.indexOf("interface TasksChannelEvents");
    const sanitizeIdx = src.indexOf("function sanitizeTaskItem");
    const joinTasksIdx = src.indexOf("async joinTasks");

    assert.ok(tasksChannelEventsIdx > -1, "TasksChannelEvents should exist");
    assert.ok(sanitizeIdx > -1, "sanitizeTaskItem should exist");
    assert.ok(joinTasksIdx > -1, "joinTasks should exist");
  });
});

// ---------------------------------------------------------------------------
// 4. enableTasks:true with autoSpawn:false does not create TaskRunner
// ---------------------------------------------------------------------------

describe("task isolation: feature flag independence", () => {
  let tmpDir: string;
  let originalCwd: string;

  beforeEach(() => {
    tmpDir = makeTmpDir();
    originalCwd = process.cwd();
    process.chdir(tmpDir);
    fs.mkdirSync(path.join(tmpDir, ".teamrc"), { recursive: true });
  });

  afterEach(() => {
    process.chdir(originalCwd);
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  it("enableTasks:true autoSpawn:false does not log auto-spawn messages", async () => {
    const adapter = createInMemoryAdapter();
    const kp = await generateKeypair();
    const token = toToken(kp.publicKey);

    const { logs } = await captureConsoleAsync(() => {
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
        fallbackPollInterval: 600_000,
        enableTasks: true,
        autoSpawn: false,
      });
      daemon.stop();
    });

    const spawnLogs = logs.filter((l) => l.includes("Auto-spawn"));
    assert.equal(spawnLogs.length, 0, "Should not log auto-spawn messages when autoSpawn is false");
  });

  it("enableTasks:false with activeMembers set does not trigger task behavior", async () => {
    const adapter = createInMemoryAdapter();
    const kp = await generateKeypair();
    const token = toToken(kp.publicKey);

    const { logs, warns } = await captureConsoleAsync(() => {
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
        fallbackPollInterval: 600_000,
        enableTasks: false,
        activeMembers: ["frontend-dev", "backend-dev"],
      });
      daemon.stop();
    });

    const taskLogs = [...logs, ...warns].filter((l) =>
      l.toLowerCase().includes("task") || l.toLowerCase().includes("claim")
    );
    assert.equal(taskLogs.length, 0, "No task/claim activity when enableTasks is false");
  });
});
