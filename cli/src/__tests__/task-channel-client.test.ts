/**
 * Tests for task-related channel-client functionality.
 *
 * Covers:
 * 1. sanitizeTaskItem validation and capping
 * 2. TasksChannelEvents interface contract
 * 3. TaskChannelItem type contract
 * 4. ChannelReplyError behavior for task scenarios
 *
 * These tests must exist before the task extraction so that the
 * sanitizeTaskItem contract is verified when it moves to task-channel-client.ts.
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";
import { ChannelReplyError } from "../channel-client.js";

// We need to test sanitizeTaskItem but it is not exported.
// We verify its behavior indirectly through source analysis and
// through the ChannelReplyError which IS exported.

const CHANNEL_SRC_PATH = path.resolve(import.meta.dirname, "..", "channel-client.ts");
const channelSource = fs.readFileSync(CHANNEL_SRC_PATH, "utf-8");

// ---------------------------------------------------------------------------
// sanitizeTaskItem contract (source-level verification)
// ---------------------------------------------------------------------------

describe("sanitizeTaskItem contract", () => {
  it("returns null for null input", () => {
    // Verify via source: the function checks !raw first
    assert.ok(
      channelSource.includes("if (!raw || typeof raw !== \"object\") return null"),
      "sanitizeTaskItem should return null for null/non-object input",
    );
  });

  it("returns null when required fields are missing", () => {
    // number, description, assignee are required
    assert.ok(
      channelSource.includes("if (typeof t.number !== \"number\") return null"),
      "sanitizeTaskItem should reject items without a numeric 'number' field",
    );
    assert.ok(
      channelSource.includes("if (typeof t.description !== \"string\") return null"),
      "sanitizeTaskItem should reject items without a string 'description' field",
    );
    assert.ok(
      channelSource.includes("if (typeof t.assignee !== \"string\") return null"),
      "sanitizeTaskItem should reject items without a string 'assignee' field",
    );
  });

  it("caps description to 2000 characters", () => {
    assert.ok(
      channelSource.includes("description: t.description.slice(0, 2000)"),
      "sanitizeTaskItem should cap description at 2000 chars",
    );
  });

  it("caps assignee to 64 characters", () => {
    assert.ok(
      channelSource.includes("assignee: t.assignee.slice(0, 64)"),
      "sanitizeTaskItem should cap assignee at 64 chars",
    );
  });

  it("caps status to 20 characters", () => {
    assert.ok(
      channelSource.includes(".slice(0, 20)") && channelSource.includes("status"),
      "sanitizeTaskItem should cap status length",
    );
  });

  it("caps result to 10000 characters", () => {
    assert.ok(
      channelSource.includes("result: t.result.slice(0, 10_000)"),
      "sanitizeTaskItem should cap result at 10000 chars",
    );
  });

  it("handles optional fields gracefully", () => {
    // Optional fields: created_by, claimed_by, claimed_at, completed_at, result, inserted_at, updated_at
    const optionalFields = ["created_by", "claimed_by", "claimed_at", "completed_at", "result", "inserted_at", "updated_at"];
    for (const field of optionalFields) {
      assert.ok(
        channelSource.includes(`typeof t.${field} === "string"`),
        `sanitizeTaskItem should check typeof for optional field '${field}'`,
      );
    }
  });
});

// ---------------------------------------------------------------------------
// TaskChannelItem type structure (source verification)
// ---------------------------------------------------------------------------

describe("TaskChannelItem interface", () => {
  it("defines required fields: number, description, assignee, status", () => {
    // Look for the interface definition
    const ifaceMatch = channelSource.match(/export interface TaskChannelItem[\s\S]*?\}/);
    assert.ok(ifaceMatch, "TaskChannelItem interface should exist");

    const iface = ifaceMatch![0];
    assert.ok(iface.includes("number: number"), "should have number field");
    assert.ok(iface.includes("description: string"), "should have description field");
    assert.ok(iface.includes("assignee: string"), "should have assignee field");
    assert.ok(iface.includes("status: string"), "should have status field");
  });

  it("defines optional metadata fields", () => {
    const ifaceMatch = channelSource.match(/export interface TaskChannelItem[\s\S]*?\}/);
    const iface = ifaceMatch![0];

    // These should be optional (marked with ?)
    assert.ok(iface.includes("created_by?"), "created_by should be optional");
    assert.ok(iface.includes("claimed_by?"), "claimed_by should be optional");
    assert.ok(iface.includes("result?"), "result should be optional");
  });
});

// ---------------------------------------------------------------------------
// ChannelReplyError for task scenarios
// ---------------------------------------------------------------------------

describe("ChannelReplyError for task scenarios", () => {
  it("preserves reason string for 'unmatched topic'", () => {
    const err = new ChannelReplyError("unmatched topic");
    assert.equal(err.reason, "unmatched topic");
    assert.equal(err.name, "ChannelReplyError");
    assert.ok(err instanceof Error);
  });

  it("preserves reason string for 'unauthorized'", () => {
    const err = new ChannelReplyError("unauthorized");
    assert.equal(err.reason, "unauthorized");
  });

  it("message includes reason", () => {
    const err = new ChannelReplyError("some error reason");
    assert.ok(err.message.includes("some error reason"));
  });

  it("reason is readonly", () => {
    const err = new ChannelReplyError("test");
    // TypeScript enforces readonly, but at runtime we verify the value persists
    assert.equal(err.reason, "test");
  });
});

// ---------------------------------------------------------------------------
// joinTasks event handler registration (source verification)
// ---------------------------------------------------------------------------

describe("joinTasks event handlers", () => {
  it("registers created event handler", () => {
    assert.ok(
      channelSource.includes("tasks:created"),
      "joinTasks should register a handler for tasks:created events",
    );
  });

  it("registers updated event handler", () => {
    assert.ok(
      channelSource.includes("tasks:updated"),
      "joinTasks should register a handler for tasks:updated events",
    );
  });

  it("registers error event handler", () => {
    // The tasks channel should have its own error handler
    const joinTasksSection = channelSource.slice(
      channelSource.indexOf("async joinTasks"),
    );
    assert.ok(
      joinTasksSection.includes(":error"),
      "joinTasks should register an error handler",
    );
  });

  it("registers close event handler", () => {
    const joinTasksSection = channelSource.slice(
      channelSource.indexOf("async joinTasks"),
    );
    assert.ok(
      joinTasksSection.includes(":close"),
      "joinTasks should register a close handler",
    );
  });

  it("leave() cleans up all event handlers", () => {
    // The leave function in joinTasks should delete all registered handlers
    const joinTasksSection = channelSource.slice(
      channelSource.indexOf("async joinTasks"),
    );
    const leaveSection = joinTasksSection.slice(
      joinTasksSection.indexOf("leave()"),
    );

    assert.ok(leaveSection.includes("eventHandlers.delete"), "leave should clean up event handlers");

    // Count the number of handler deletions -- should match registrations
    const deleteCount = (leaveSection.match(/eventHandlers\.delete/g) || []).length;
    assert.ok(
      deleteCount >= 4,
      `leave() should delete at least 4 handlers (created, updated, error, close), found ${deleteCount}`,
    );
  });

  it("sanitizes task items received from relay", () => {
    // Both onCreated and onUpdated should call sanitizeTaskItem
    const joinTasksSection = channelSource.slice(
      channelSource.indexOf("async joinTasks"),
    );
    const sanitizeCalls = (joinTasksSection.match(/sanitizeTaskItem/g) || []).length;
    assert.ok(
      sanitizeCalls >= 3,
      `joinTasks should call sanitizeTaskItem at least 3 times (onJoin list, onCreated, onUpdated), found ${sanitizeCalls}`,
    );
  });
});

// ---------------------------------------------------------------------------
// ChannelClient interface includes joinTasks
// ---------------------------------------------------------------------------

describe("ChannelClient interface", () => {
  it("exports joinTasks as part of the interface", () => {
    assert.ok(
      channelSource.includes("joinTasks(teamId: string"),
      "ChannelClient interface should include joinTasks method",
    );
  });

  it("joinTasks returns TasksChannel", () => {
    assert.ok(
      channelSource.includes("Promise<TasksChannel>"),
      "joinTasks should return Promise<TasksChannel>",
    );
  });

  it("TasksChannel has leave method", () => {
    // Match TasksChannel specifically (not TasksChannelEvents)
    const tasksChannelMatch = channelSource.match(/export interface TasksChannel \{[\s\S]*?\}/);
    assert.ok(tasksChannelMatch, "TasksChannel interface should exist");
    assert.ok(
      tasksChannelMatch![0].includes("leave()"),
      "TasksChannel should have a leave() method",
    );
  });
});
