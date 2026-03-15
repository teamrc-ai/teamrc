/**
 * Task daemon — manages task channel subscription, claimed-task tracking,
 * task caching, auto-claiming, and auto-spawn.
 *
 * Extracted from daemon.ts so that all task-related state and logic lives
 * in a single module. The main daemon loads this via dynamic import() only
 * when enableTasks is true.
 */

import * as fs from "node:fs";
import * as path from "node:path";
import {
  ChannelReplyError,
  type ChannelClient,
  type TasksChannel,
  type TaskChannelItem,
} from "./channel-client.js";
import type { TeamrcClient } from "./client.js";
import { TaskRunner, preflight as spawnPreflight } from "./spawn.js";

// ---------------------------------------------------------------------------
// Public contract
// ---------------------------------------------------------------------------

export interface TaskDaemonDeps {
  channelClient: ChannelClient;
  restClient: TeamrcClient;
  teamId: string;
  teamSlug: string;
  activeMembers: string[];
  autoSpawn: boolean;
  spawnTimeoutMs?: number;
  log: (msg: string) => void;
  warn: (msg: string) => void;
}

export interface TaskDaemonHandle {
  stop(): void;
}

// ---------------------------------------------------------------------------
// Claimed tasks tracking — persisted so we only re-queue our own tasks
// ---------------------------------------------------------------------------

const CLAIMED_TASKS_FILENAME = "daemon-claimed.json";

function claimedTasksFilePath(): string {
  return path.join(process.cwd(), ".teamrc", CLAIMED_TASKS_FILENAME);
}

function loadClaimedTasks(): Set<number> {
  try {
    const data = JSON.parse(fs.readFileSync(claimedTasksFilePath(), "utf-8"));
    return new Set(Array.isArray(data) ? data.filter(Number.isInteger) : []);
  } catch {
    return new Set();
  }
}

function saveClaimedTasks(claimed: Set<number>): void {
  const filePath = claimedTasksFilePath();
  const dir = path.dirname(filePath);
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(filePath, JSON.stringify([...claimed]));
}

// ---------------------------------------------------------------------------
// Task cache
// ---------------------------------------------------------------------------

function writeTaskCache(tasks: TaskChannelItem[], slug: string): void {
  if (!/^[a-z0-9-]+$/.test(slug)) return; // reject unsafe slugs
  const cacheDir = path.join(process.cwd(), ".teamrc");
  if (!fs.existsSync(cacheDir)) fs.mkdirSync(cacheDir, { recursive: true });

  const grouped: Record<string, TaskChannelItem[]> = {};
  for (const t of tasks) {
    (grouped[t.status] ??= []).push(t);
  }

  const lines: string[] = ["# Team Tasks", ""];
  for (const status of ["todo", "in_progress", "done", "cancelled", "failed"]) {
    if (!grouped[status]) continue;
    const label = { todo: "TODO", in_progress: "IN PROGRESS", done: "DONE", cancelled: "CANCELLED", failed: "FAILED" }[status] ?? status;
    lines.push(`## ${label}`, "");
    for (const t of grouped[status]) {
      let line = `- **#${t.number}** [${t.assignee}] ${t.description}`;
      if (t.result && (t.status === "done" || t.status === "failed")) {
        const truncated = t.result.length > 200 ? t.result.slice(0, 197) + "..." : t.result;
        line += `\n  > ${truncated}`;
      }
      lines.push(line);
    }
    lines.push("");
  }

  fs.writeFileSync(path.join(cacheDir, `tasks-${slug}.md`), lines.join("\n"));
}

// ---------------------------------------------------------------------------
// Init
// ---------------------------------------------------------------------------

export async function initTaskDaemon(deps: TaskDaemonDeps): Promise<TaskDaemonHandle | null> {
  const {
    channelClient,
    restClient,
    teamId,
    teamSlug,
    activeMembers,
    autoSpawn,
    spawnTimeoutMs,
    log,
    warn,
  } = deps;

  // --- Task runner (auto-spawn) setup ---
  let taskRunner: TaskRunner | null = null;
  if (autoSpawn) {
    const preflightErr = spawnPreflight();
    if (preflightErr) {
      warn(`Auto-spawn disabled: ${preflightErr}`);
    } else {
      taskRunner = new TaskRunner({
        client: restClient,
        timeoutMs: spawnTimeoutMs,
        teamSlug,
        log,
        warn,
      });
      log("Auto-spawn enabled.");
    }
  }

  // --- Claimed tasks ---
  const claimedTasks = loadClaimedTasks();

  // --- Helpers ---
  async function refreshTaskCache(): Promise<void> {
    try {
      const tasks = await restClient.listTasks();
      writeTaskCache(tasks, teamSlug);
    } catch (err) {
      warn(`Failed to refresh task cache: ${(err as Error).message}`);
    }
  }

  async function autoClaimTask(task: TaskChannelItem): Promise<void> {
    try {
      await restClient.updateTask(task.number, "in_progress");
      claimedTasks.add(task.number);
      saveClaimedTasks(claimedTasks);
      log(`Auto-claimed task #${task.number}: "${task.description}" (${task.assignee})`);
      // Enqueue for auto-spawn if enabled
      if (taskRunner) {
        taskRunner.enqueue({
          number: task.number,
          description: task.description,
          assignee: task.assignee,
        });
      }
    } catch (err) {
      warn(`Failed to auto-claim task #${task.number}: ${(err as Error).message}`);
    }
  }

  // --- Join tasks channel ---
  let tasksChannel: TasksChannel | null = null;

  try {
    tasksChannel = await channelClient.joinTasks(teamId, {
      onJoin(tasks) {
        writeTaskCache(tasks, teamSlug);
        const byStatus = tasks.reduce((acc, t) => {
          acc[t.status] = (acc[t.status] || 0) + 1;
          return acc;
        }, {} as Record<string, number>);
        const statusSummary = Object.entries(byStatus).map(([s, n]) => `${n} ${s}`).join(", ");
        log(`Tasks: ${tasks.length} loaded (${statusSummary || "none"}).`);

        // Re-queue tasks that THIS daemon previously claimed
        if (taskRunner) {
          for (const task of tasks) {
            if (task.status === "in_progress" && claimedTasks.has(task.number)) {
              log(`Task #${task.number} "${task.description}" was claimed by this daemon — re-queuing.`);
              taskRunner.enqueue({
                number: task.number,
                description: task.description,
                assignee: task.assignee,
              });
            }
          }
        }
      },
      onCreated(task) {
        log(`Task #${task.number} created: "${task.description}" (assigned to ${task.assignee})`);
        void refreshTaskCache();
        // Auto-claim: if task assignee is in activeMembers and status is todo
        if (activeMembers.includes(task.assignee) && task.status === "todo") {
          void autoClaimTask(task);
        }
      },
      onUpdated(task) {
        log(`Task #${task.number} "${task.description}" -> ${task.status}`);
        void refreshTaskCache();
      },
      onError(error) {
        warn(`Tasks channel error: ${error.message}`);
      },
      onClose() {
        log("Tasks channel closed.");
        tasksChannel = null;
      },
    });
    log(`Joined tasks channel for team ${teamId}.`);
  } catch (err) {
    if (err instanceof ChannelReplyError && err.reason === "unmatched topic") {
      warn("Task sync unavailable — the relay does not support tasks for this team yet.");
    } else {
      warn(`Failed to join tasks channel: ${(err as Error).message}`);
    }
    // Non-fatal — return a handle that only cleans up the task runner
    return {
      stop() {
        taskRunner?.stop();
      },
    };
  }

  return {
    stop() {
      taskRunner?.stop();
      tasksChannel?.leave();
    },
  };
}
