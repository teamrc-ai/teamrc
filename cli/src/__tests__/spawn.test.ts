import { describe, it } from "node:test";
import assert from "node:assert/strict";
import { taskBranchName, buildSpawnPrompt, buildSpawnEnv, TaskRunner, type SpawnableTask } from "../spawn.js";
import type { TeamrcClient } from "../client.js";

describe("taskBranchName", () => {
  it("generates slug from description", () => {
    assert.equal(taskBranchName(1, "Add input validation"), "task-1-add-input-validation");
  });

  it("truncates long descriptions to 40 chars", () => {
    const desc = "This is a very long description that should be truncated to fit branch naming";
    const name = taskBranchName(42, desc);
    const slug = name.replace(/^task-42-/, "");
    assert.ok(slug.length <= 40, `slug "${slug}" is ${slug.length} chars`);
    assert.ok(!slug.endsWith("-"), `slug should not end with dash: "${slug}"`);
  });

  it("handles special characters", () => {
    assert.equal(
      taskBranchName(3, "Fix bug: login page (urgent!)"),
      "task-3-fix-bug-login-page-urgent",
    );
  });

  it("handles all-special-chars description", () => {
    const name = taskBranchName(5, "!!@@##");
    assert.equal(name, "task-5");
  });

  it("handles empty description", () => {
    assert.equal(taskBranchName(7, ""), "task-7");
  });

  it("collapses multiple dashes", () => {
    assert.equal(
      taskBranchName(2, "fix---multiple   spaces"),
      "task-2-fix-multiple-spaces",
    );
  });
});

describe("buildSpawnPrompt", () => {
  const task: SpawnableTask = {
    number: 1,
    description: "Add input validation",
    assignee: "backend-dev",
  };

  it("contains task number", () => {
    const prompt = buildSpawnPrompt(task, "task-1-add-input-validation");
    assert.ok(prompt.includes("#1"), "should contain task number");
  });

  it("contains description as untrusted input", () => {
    const prompt = buildSpawnPrompt(task, "task-1-add-input-validation");
    assert.ok(prompt.includes("Add input validation"), "should contain description");
    assert.ok(prompt.includes("user-supplied input"), "should mark description as user-supplied input");
  });

  it("contains assignee", () => {
    const prompt = buildSpawnPrompt(task, "task-1-add-input-validation");
    assert.ok(prompt.includes("backend-dev"), "should contain assignee");
  });

  it("contains branch name", () => {
    const prompt = buildSpawnPrompt(task, "task-1-add-input-validation");
    assert.ok(prompt.includes("task-1-add-input-validation"), "should contain branch name");
  });

  it("includes security constraints", () => {
    const prompt = buildSpawnPrompt(task, "task-1-add-input-validation");
    assert.ok(prompt.includes("SECURITY CONSTRAINTS"), "should include security constraints");
    assert.ok(prompt.includes("Do NOT read ~/.ssh/"), "should block credential access");
    assert.ok(prompt.includes("Do NOT make outbound network requests"), "should block network");
    assert.ok(prompt.includes("Do NOT modify .claude/"), "should block config modification");
  });

  it("includes no-push instruction", () => {
    const prompt = buildSpawnPrompt(task, "task-1-add-input-validation");
    assert.ok(prompt.includes("Do NOT push"), "should say not to push");
  });
});

describe("buildSpawnEnv", () => {
  it("includes only PATH", () => {
    const env = buildSpawnEnv();
    assert.ok(env.PATH, "should include PATH");
    assert.equal(Object.keys(env).length, 1, "should only have PATH");
  });

  it("does not include arbitrary env vars", () => {
    process.env.__TEST_SECRET_KEY = "should-not-leak";
    const env = buildSpawnEnv();
    assert.equal(env.__TEST_SECRET_KEY, undefined, "should not include arbitrary vars");
    delete process.env.__TEST_SECRET_KEY;
  });

  it("does not include HOME", () => {
    const env = buildSpawnEnv();
    assert.equal(env.HOME, undefined, "HOME should not be passed");
  });
});

describe("TaskRunner", () => {
  function makeMockClient(): TeamrcClient {
    return {
      updateTask: async () => ({
        number: 1,
        description: "test",
        assignee: "dev",
        status: "done",
      }),
    } as unknown as TeamrcClient;
  }

  describe("enqueue", () => {
    it("deduplicates by task number", () => {
      const runner = new TaskRunner({
        client: makeMockClient(),
        log: () => {},
        warn: () => {},
      });

      runner.enqueue({ number: 1, description: "Task A", assignee: "dev" });
      runner.enqueue({ number: 1, description: "Task A again", assignee: "dev" });
      runner.enqueue({ number: 2, description: "Task B", assignee: "dev" });

      runner.stop();
    });

    it("ignores enqueue after stop", () => {
      const runner = new TaskRunner({
        client: makeMockClient(),
        log: () => {},
        warn: () => {},
      });

      runner.stop();
      runner.enqueue({ number: 1, description: "After stop", assignee: "dev" });
    });

    it("drops tasks when queue is full", () => {
      const warnings: string[] = [];
      const runner = new TaskRunner({
        client: makeMockClient(),
        maxQueueDepth: 2,
        log: () => {},
        warn: (msg) => warnings.push(msg),
      });

      // First task starts processing, so queue has room
      runner.enqueue({ number: 1, description: "Task 1", assignee: "dev" });
      runner.enqueue({ number: 2, description: "Task 2", assignee: "dev" });
      runner.enqueue({ number: 3, description: "Task 3", assignee: "dev" });
      // Task 4 should be dropped (queue has 2: tasks 2 and 3, task 1 is processing)
      runner.enqueue({ number: 4, description: "Task 4", assignee: "dev" });

      runner.stop();

      // At least one warning about queue full
      assert.ok(warnings.some((w) => w.includes("Queue full")), "should warn about queue full");
    });
  });

  describe("stop", () => {
    it("can be called multiple times without error", () => {
      const runner = new TaskRunner({
        client: makeMockClient(),
        log: () => {},
        warn: () => {},
      });

      runner.stop();
      runner.stop();
    });
  });
});
