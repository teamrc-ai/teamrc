/**
 * Tests for task-related TeamrcClient methods (createTask, listTasks, updateTask).
 *
 * These tests must exist BEFORE the task extraction refactor so that we can
 * verify the API contract is preserved when methods move to a new file.
 *
 * Uses the same fetch-mocking pattern as client-errors.test.ts.
 */

import { describe, it, afterEach } from "node:test";
import assert from "node:assert/strict";
import { TeamrcClient } from "../client.js";

// ---------------------------------------------------------------------------
// Helpers: intercept globalThis.fetch
// ---------------------------------------------------------------------------

interface CapturedCall {
  url: string;
  init?: RequestInit;
}

let captured: CapturedCall[] = [];
const originalFetch = globalThis.fetch;

function mockFetch(response: object, status = 200) {
  captured = [];
  globalThis.fetch = (async (input: RequestInfo | URL, init?: RequestInit) => {
    const url = typeof input === "string" ? input : input.toString();
    captured.push({ url, init });
    return new Response(JSON.stringify(response), {
      status,
      headers: { "Content-Type": "application/json" },
    });
  }) as typeof fetch;
}

function restoreFetch() {
  globalThis.fetch = originalFetch;
}

const dummyKey = new Uint8Array(32);
const dummyToken = "trc_ak_AAAAAAAAAAAAAAAAAAAAAA";
const dummyTeamId = "team-123";

// ---------------------------------------------------------------------------
// createTask
// ---------------------------------------------------------------------------

describe("TeamrcClient createTask", () => {
  afterEach(() => restoreFetch());

  it("sends POST to /api/teams/tasks with description and assignee", async () => {
    mockFetch({
      task: {
        number: 1,
        description: "Fix the login page",
        assignee: "frontend-dev",
        status: "todo",
      },
    });

    const client = new TeamrcClient("http://localhost:4000", dummyKey, dummyToken, dummyTeamId);
    const result = await client.createTask("Fix the login page", "frontend-dev");

    assert.equal(result.number, 1);
    assert.equal(result.description, "Fix the login page");
    assert.equal(result.assignee, "frontend-dev");
    assert.equal(result.status, "todo");

    // Verify request
    assert.equal(captured.length, 1);
    assert.ok(captured[0].url.includes("/api/teams/tasks"));
    assert.equal(captured[0].init?.method, "POST");

    const body = JSON.parse(captured[0].init?.body as string);
    assert.equal(body.description, "Fix the login page");
    assert.equal(body.assignee, "frontend-dev");
    assert.equal(body.token, dummyToken);
    assert.equal(body.team_id, dummyTeamId);
  });

  it("throws on non-ok response", async () => {
    mockFetch({ error: "member not found" }, 422);

    const client = new TeamrcClient("http://localhost:4000", dummyKey, dummyToken, dummyTeamId);

    await assert.rejects(
      () => client.createTask("Some task", "nonexistent-member"),
      (err: Error) => {
        assert.match(err.message, /createTask failed/);
        return true;
      },
    );
  });

  it("sends request without team_id when teamId is not set", async () => {
    mockFetch({
      task: { number: 1, description: "t", assignee: "a", status: "todo" },
    });

    const client = new TeamrcClient("http://localhost:4000", dummyKey, dummyToken);
    await client.createTask("t", "a");

    const body = JSON.parse(captured[0].init?.body as string);
    assert.equal(body.team_id, undefined);
  });
});

// ---------------------------------------------------------------------------
// listTasks
// ---------------------------------------------------------------------------

describe("TeamrcClient listTasks", () => {
  afterEach(() => restoreFetch());

  it("sends GET to /api/teams/tasks/:token", async () => {
    mockFetch({ tasks: [
      { number: 1, description: "Task 1", assignee: "dev", status: "todo" },
      { number: 2, description: "Task 2", assignee: "dev", status: "done" },
    ]});

    const client = new TeamrcClient("http://localhost:4000", dummyKey, dummyToken, dummyTeamId);
    const tasks = await client.listTasks();

    assert.equal(tasks.length, 2);
    assert.equal(tasks[0].number, 1);
    assert.equal(tasks[1].status, "done");
  });

  it("includes status filter in query params", async () => {
    mockFetch({ tasks: [] });

    const client = new TeamrcClient("http://localhost:4000", dummyKey, dummyToken, dummyTeamId);
    await client.listTasks({ status: "todo" });

    assert.equal(captured.length, 1);
    assert.ok(
      captured[0].url.includes("status=todo"),
      `URL should contain status=todo, got: ${captured[0].url}`,
    );
  });

  it("includes assignee filter in query params", async () => {
    mockFetch({ tasks: [] });

    const client = new TeamrcClient("http://localhost:4000", dummyKey, dummyToken, dummyTeamId);
    await client.listTasks({ assignee: "backend-dev" });

    assert.ok(
      captured[0].url.includes("assignee=backend-dev"),
      `URL should contain assignee param, got: ${captured[0].url}`,
    );
  });

  it("includes team_id in query params when set", async () => {
    mockFetch({ tasks: [] });

    const client = new TeamrcClient("http://localhost:4000", dummyKey, dummyToken, dummyTeamId);
    await client.listTasks();

    assert.ok(
      captured[0].url.includes(`team_id=${dummyTeamId}`),
      `URL should contain team_id, got: ${captured[0].url}`,
    );
  });

  it("handles empty task list", async () => {
    mockFetch({ tasks: [] });

    const client = new TeamrcClient("http://localhost:4000", dummyKey, dummyToken, dummyTeamId);
    const tasks = await client.listTasks();

    assert.equal(tasks.length, 0);
  });

  it("combines multiple filters", async () => {
    mockFetch({ tasks: [] });

    const client = new TeamrcClient("http://localhost:4000", dummyKey, dummyToken, dummyTeamId);
    await client.listTasks({ status: "in_progress", assignee: "qa-engineer" });

    assert.ok(captured[0].url.includes("status=in_progress"));
    assert.ok(captured[0].url.includes("assignee=qa-engineer"));
  });
});

// ---------------------------------------------------------------------------
// updateTask
// ---------------------------------------------------------------------------

describe("TeamrcClient updateTask", () => {
  afterEach(() => restoreFetch());

  it("sends PATCH to /api/teams/tasks/:number with status", async () => {
    mockFetch({
      task: { number: 5, description: "Test", assignee: "dev", status: "in_progress" },
    });

    const client = new TeamrcClient("http://localhost:4000", dummyKey, dummyToken, dummyTeamId);
    const result = await client.updateTask(5, "in_progress");

    assert.equal(result.number, 5);
    assert.equal(result.status, "in_progress");

    assert.equal(captured.length, 1);
    assert.ok(captured[0].url.endsWith("/api/teams/tasks/5"));
    assert.equal(captured[0].init?.method, "PATCH");

    const body = JSON.parse(captured[0].init?.body as string);
    assert.equal(body.status, "in_progress");
    assert.equal(body.token, dummyToken);
    assert.equal(body.team_id, dummyTeamId);
  });

  it("includes result when provided", async () => {
    mockFetch({
      task: { number: 3, description: "T", assignee: "d", status: "done" },
    });

    const client = new TeamrcClient("http://localhost:4000", dummyKey, dummyToken, dummyTeamId);
    await client.updateTask(3, "done", "Task completed successfully");

    const body = JSON.parse(captured[0].init?.body as string);
    assert.equal(body.result, "Task completed successfully");
  });

  it("omits result when not provided", async () => {
    mockFetch({
      task: { number: 3, description: "T", assignee: "d", status: "in_progress" },
    });

    const client = new TeamrcClient("http://localhost:4000", dummyKey, dummyToken, dummyTeamId);
    await client.updateTask(3, "in_progress");

    const body = JSON.parse(captured[0].init?.body as string);
    assert.equal(body.result, undefined);
  });

  it("throws on non-ok response with context", async () => {
    mockFetch({ error: "invalid status transition" }, 422);

    const client = new TeamrcClient("http://localhost:4000", dummyKey, dummyToken, dummyTeamId);

    await assert.rejects(
      () => client.updateTask(1, "done"),
      (err: Error) => {
        assert.match(err.message, /updateTask failed/);
        assert.match(err.message, /invalid status transition/);
        return true;
      },
    );
  });

  it("uses correct URL path with task number", async () => {
    mockFetch({
      task: { number: 42, description: "T", assignee: "d", status: "cancelled" },
    });

    const client = new TeamrcClient("http://localhost:4000", dummyKey, dummyToken);
    await client.updateTask(42, "cancelled");

    assert.ok(
      captured[0].url.includes("/api/teams/tasks/42"),
      `URL should contain /api/teams/tasks/42, got: ${captured[0].url}`,
    );
  });
});

// ---------------------------------------------------------------------------
// TaskItem type contract
// ---------------------------------------------------------------------------

describe("TaskItem contract", () => {
  afterEach(() => restoreFetch());

  it("preserves all fields from the relay response", async () => {
    mockFetch({
      task: {
        number: 1,
        description: "Full task",
        assignee: "dev",
        status: "done",
        created_by: "machine-abc",
        claimed_by: "machine-xyz",
        claimed_at: "2026-03-15T10:00:00Z",
        completed_at: "2026-03-15T11:00:00Z",
        result: "Task completed with 3 commits",
        inserted_at: "2026-03-15T09:00:00Z",
        updated_at: "2026-03-15T11:00:00Z",
      },
    });

    const client = new TeamrcClient("http://localhost:4000", dummyKey, dummyToken, dummyTeamId);
    const task = await client.createTask("Full task", "dev");

    assert.equal(task.number, 1);
    assert.equal(task.description, "Full task");
    assert.equal(task.assignee, "dev");
    assert.equal(task.status, "done");
    assert.equal(task.created_by, "machine-abc");
    assert.equal(task.claimed_by, "machine-xyz");
    assert.equal(task.claimed_at, "2026-03-15T10:00:00Z");
    assert.equal(task.completed_at, "2026-03-15T11:00:00Z");
    assert.equal(task.result, "Task completed with 3 commits");
    assert.equal(task.inserted_at, "2026-03-15T09:00:00Z");
    assert.equal(task.updated_at, "2026-03-15T11:00:00Z");
  });
});
