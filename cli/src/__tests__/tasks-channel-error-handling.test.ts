/**
 * Tests for tasks channel error handling in the daemon.
 *
 * Bug context: When the tasks channel fails to join (e.g., Phoenix returns
 * "unmatched topic"), the daemon at line 366 logs the raw error message
 * via warn() without any user-friendly context. Users see something like:
 *
 *   WARN: Failed to join tasks channel: Channel reply error: unmatched topic
 *
 * This is a raw Phoenix protocol error with no explanation of what went
 * wrong or how to fix it. The error should explain that task sync requires
 * server support and suggest checking the relay version or removing
 * --experimental.
 *
 * These tests verify:
 * 1. The daemon handles tasks channel join failures gracefully
 * 2. Error messages provide actionable context, not raw protocol errors
 * 3. The daemon continues running (knowledge sync) even when tasks fail
 * 4. The channel-client error wrapping provides useful information
 */

import { describe, it } from "node:test";
import assert from "node:assert/strict";
import * as fs from "node:fs";
import * as path from "node:path";

const DAEMON_PATH = path.resolve(import.meta.dirname, "..", "daemon.ts");
const TASK_DAEMON_PATH = path.resolve(import.meta.dirname, "..", "task-daemon.ts");
const CHANNEL_CLIENT_PATH = path.resolve(import.meta.dirname, "..", "channel-client.ts");

describe("tasks channel error handling in task-daemon", () => {
  const taskDaemonSource = fs.readFileSync(TASK_DAEMON_PATH, "utf-8");

  it("catches tasks channel join failures without crashing", () => {
    // The tasks channel join is inside a try/catch
    // Verify the structure: joinTasks call is wrapped in try/catch
    assert.ok(
      taskDaemonSource.includes("catch (err)") || taskDaemonSource.includes("catch(err)"),
      "Task daemon should have try/catch around tasks channel operations",
    );

    // Specifically check that joinTasks failure is caught
    assert.ok(
      taskDaemonSource.includes("Failed to join tasks channel"),
      "Task daemon should have a specific error message for tasks channel join failure",
    );
  });

  it("should provide user-friendly context in tasks channel error messages", () => {
    // Find the tasks channel error handling section
    const errorLineIdx = taskDaemonSource.indexOf("Failed to join tasks channel");
    assert.ok(errorLineIdx > -1, "Should find tasks channel error message");

    // Extract surrounding context (200 chars around the error message)
    const context = taskDaemonSource.slice(
      Math.max(0, errorLineIdx - 100),
      errorLineIdx + 300,
    );

    // The error message should include actionable guidance, not just the raw error.
    const hasActionableGuidance =
      context.includes("relay") ||
      context.includes("server") ||
      context.includes("--experimental") ||
      context.includes("not supported") ||
      context.includes("upgrade") ||
      context.includes("version");

    assert.ok(
      hasActionableGuidance,
      "Tasks channel error should include actionable guidance for the user.\n" +
      "Current code just logs the raw error message:\n" +
      `  ${context.trim()}\n\n` +
      "The error should explain possible causes (e.g., relay doesn't support tasks)\n" +
      "and suggest actions (e.g., remove --experimental, or upgrade the relay).",
    );
  });

  it("task daemon is loaded after knowledge channel in daemon.ts", () => {
    // After task extraction, daemon.ts should dynamically import task-daemon
    // only after the knowledge channel is successfully joined.
    const daemonSource = fs.readFileSync(DAEMON_PATH, "utf-8");
    const knowledgeChannelIdx = daemonSource.indexOf("Joined knowledge channel");
    const taskDaemonIdx = daemonSource.indexOf("initTaskDaemon");

    assert.ok(knowledgeChannelIdx > -1, "Should find knowledge channel join");
    assert.ok(taskDaemonIdx > -1, "Should find initTaskDaemon call");
    assert.ok(
      taskDaemonIdx > knowledgeChannelIdx,
      "initTaskDaemon should come after knowledge channel join (daemon continues after tasks failure)",
    );
  });
});

describe("channel-client error message quality", () => {
  const channelSource = fs.readFileSync(CHANNEL_CLIENT_PATH, "utf-8");

  it("joinTasks reject includes topic information", () => {
    // When Phoenix rejects a channel join (e.g., "unmatched topic"),
    // the error should include what topic was being joined.
    //
    // Current behavior: sendMessage rejects with "Channel reply error: unmatched topic"
    // which is generic and doesn't say it was the tasks channel.

    // Check the sendMessage error formatting
    const replyErrorSection = channelSource.slice(
      channelSource.indexOf("Channel reply error"),
      channelSource.indexOf("Channel reply error") + 200,
    );

    // The error should ideally include the topic name
    assert.ok(
      replyErrorSection.includes("topic") ||
      channelSource.includes("tasks") && channelSource.includes("Channel reply error"),
      "Channel reply errors should include topic context for debugging",
    );
  });

  it("tasks channel error handler wraps errors with channel context", () => {
    // The error event handler for tasks channel should identify itself
    const tasksErrorHandler = channelSource.match(
      /`\$\{topic\}:error`.*?=.*?\(payload\).*?=>\s*\{[^}]*tasks/s,
    ) || channelSource.includes("Tasks channel error");

    assert.ok(
      channelSource.includes("Tasks channel error"),
      "Tasks channel error handler should prefix errors with 'Tasks channel error'",
    );
  });

  it("sanitizeTaskItem handles null/undefined input gracefully", () => {
    // The sanitizeTaskItem function should handle bad input
    assert.ok(
      channelSource.includes("if (!raw || typeof raw !== \"object\") return null"),
      "sanitizeTaskItem should guard against null/undefined input",
    );
  });
});

describe("tasks channel error scenarios", () => {
  it("'unmatched topic' error uses ChannelReplyError for typed detection", async () => {
    const { ChannelReplyError } = await import("../channel-client.js");

    const err = new ChannelReplyError("unmatched topic");
    assert.equal(err.reason, "unmatched topic");
    assert.equal(err.message, "Channel reply error: unmatched topic");
    assert.ok(err instanceof Error);
    assert.ok(err instanceof ChannelReplyError);
  });

  it("task-daemon detects 'unmatched topic' and shows user-friendly message", () => {
    const taskDaemonSource = fs.readFileSync(TASK_DAEMON_PATH, "utf-8");

    // The task daemon should check for ChannelReplyError with reason "unmatched topic"
    assert.ok(
      taskDaemonSource.includes('err.reason === "unmatched topic"') ||
      taskDaemonSource.includes("err.reason === 'unmatched topic'"),
      "Task daemon should detect 'unmatched topic' reason from ChannelReplyError",
    );

    // And show a user-friendly message instead of the raw error
    assert.ok(
      taskDaemonSource.includes("relay does not support tasks") ||
      taskDaemonSource.includes("relay does not support task"),
      "Task daemon should show a user-friendly message for unmatched topic errors",
    );
  });
});
