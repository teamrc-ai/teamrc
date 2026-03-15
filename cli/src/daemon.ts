/**
 * Knowledge-only sync daemon.
 *
 * Keeps the team knowledge file in sync across machines in real-time
 * via Phoenix Channels (WebSocket). Phoenix longpoll handles transport
 * fallback natively. REST polling is retained as a last-resort fallback
 * for cases where the server is completely unreachable via WebSocket/longpoll.
 *
 * Does NOT sync team config (members, skills, name) -- those remain
 * explicit via push/pull/sync.
 */

import { createHash } from "node:crypto";
import * as fs from "node:fs";
import * as path from "node:path";
import { watch } from "chokidar";
import type { PlatformAdapter, TeamScope } from "./adapters/base.js";
import {
  createChannelClient,
  type ChannelClient,
  type KnowledgeChannel,
  type TasksChannel,
  type TaskChannelItem,
} from "./channel-client.js";
import { TeamrcClient, TeamNotFoundError } from "./client.js";
import { mergeKnowledge, pruneKnowledge } from "./team-yaml.js";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface KnowledgeDaemonOptions {
  relayUrl: string;
  privateKey: Uint8Array;
  token: string;
  teamId: string;
  teamSlug: string;
  scope: TeamScope;
  adapters: PlatformAdapter[];
  platforms: string[];
  fallbackPollInterval?: number; // default 120_000 (2 min)
  /** Force REST-only mode (no WebSocket). */
  restOnly?: boolean;
  /** Member names that run on this machine (used for auto-claiming tasks). */
  activeMembers?: string[];
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const DEFAULT_POLL_INTERVAL_MS = 120_000; // 2 minutes
const KNOWLEDGE_CAP_BYTES = 100_000;
const DEBOUNCE_MS = 500;
const RECONNECT_DELAY_MS = 5_000;

// ---------------------------------------------------------------------------
// Logging
// ---------------------------------------------------------------------------

function log(msg: string): void {
  const ts = new Date().toISOString().slice(11, 19);
  console.log(`[${ts}] ${msg}`);
}

function warn(msg: string): void {
  const ts = new Date().toISOString().slice(11, 19);
  console.warn(`[${ts}] WARN: ${msg}`);
}

// ---------------------------------------------------------------------------
// Hashing  --  normalized SHA-256
// ---------------------------------------------------------------------------

/**
 * Compute a normalized SHA-256 hash of knowledge content.
 * Normalization: trim trailing whitespace, add single trailing newline.
 * Returns hex string.
 */
export function computeKnowledgeHash(content: string): string {
  const normalized = content.trimEnd() + "\n";
  return createHash("sha256").update(normalized, "utf8").digest("hex");
}

// ---------------------------------------------------------------------------
// Size warnings
// ---------------------------------------------------------------------------

function logSizeWarning(size: number, cap: number): void {
  const pct = size / cap;
  const sizeKB = Math.round(size / 1024);
  const capKB = Math.round(cap / 1024);

  if (pct > 0.9) {
    warn(`Knowledge nearly full (${sizeKB}KB / ${capKB}KB). Oldest entries will be pruned on next sync.`);
  } else if (pct > 0.7) {
    log(`Knowledge: ${sizeKB}KB / ${capKB}KB`);
  }
}

// ---------------------------------------------------------------------------
// Daemon
// ---------------------------------------------------------------------------

export function startKnowledgeDaemon(opts: KnowledgeDaemonOptions): { stop: () => void } {
  const {
    relayUrl,
    privateKey,
    token,
    teamId,
    teamSlug,
    scope,
    adapters,
    platforms,
    restOnly = false,
  } = opts;
  const fallbackPollInterval = opts.fallbackPollInterval ?? DEFAULT_POLL_INTERVAL_MS;

  let stopped = false;
  let lastWrittenHash = "";
  let knowledgeCap = KNOWLEDGE_CAP_BYTES;

  // REST last-resort fallback state (used when WebSocket/longpoll both fail)
  let pollTimeout: ReturnType<typeof setTimeout> | null = null;
  let reconnectTimeout: ReturnType<typeof setTimeout> | null = null;

  // WebSocket state
  let channelClient: ChannelClient | null = null;
  let knowledgeChannel: KnowledgeChannel | null = null;
  let tasksChannel: TasksChannel | null = null;

  const activeMembers = opts.activeMembers ?? [];

  // File watcher
  let watcher: ReturnType<typeof watch> | null = null;
  let debounceTimer: ReturnType<typeof setTimeout> | null = null;

  // REST client for last-resort fallback mode
  const restClient = new TeamrcClient(relayUrl, privateKey, token, teamId);

  // -----------------------------------------------------------------------
  // Knowledge read/write helpers
  // -----------------------------------------------------------------------

  /** Read knowledge from the first adapter that has content. */
  function readLocalKnowledge(): string {
    for (const adapter of adapters) {
      try {
        const content = adapter.readKnowledge();
        if (content) return content;
      } catch {
        // Skip adapters that fail to read
      }
    }
    return "";
  }

  /** Write knowledge to all adapters. Updates lastWrittenHash. */
  function writeKnowledgeToAllAdapters(content: string): void {
    lastWrittenHash = computeKnowledgeHash(content);
    for (let i = 0; i < adapters.length; i++) {
      try {
        adapters[i].writeKnowledge(content);
      } catch (err) {
        warn(`Failed to write knowledge to ${platforms[i]}: ${(err as Error).message}`);
      }
    }
  }

  /**
   * Merge remote content with local, prune if needed, and write to all
   * adapters. Returns the merged content.
   */
  function mergeAndWrite(remoteContent: string): string {
    const local = readLocalKnowledge();
    let merged = mergeKnowledge(remoteContent, local);
    merged = pruneKnowledge(merged, knowledgeCap);
    writeKnowledgeToAllAdapters(merged);
    return merged;
  }

  // -----------------------------------------------------------------------
  // File watcher
  // -----------------------------------------------------------------------

  function setupFileWatcher(onLocalChange: (content: string) => void): void {
    // Watch all unique knowledge file paths across adapters.
    // Each adapter may store knowledge in a different location
    // (e.g. OpenClaw uses ~/.openclaw/ instead of .teamrc/).
    const watchPatterns = [...new Set(
      adapters.map((a) => a.getKnowledgePath(scope)),
    )];

    watcher = watch(watchPatterns, {
      ignoreInitial: true,
      awaitWriteFinish: { stabilityThreshold: 300 },
    });

    watcher.on("change", () => {
      if (debounceTimer) clearTimeout(debounceTimer);
      debounceTimer = setTimeout(() => {
        if (stopped) return;

        const content = readLocalKnowledge();
        if (!content) return;

        const hash = computeKnowledgeHash(content);

        // Anti-echo: skip if this is content we just wrote
        if (hash === lastWrittenHash) return;

        onLocalChange(content);
      }, DEBOUNCE_MS);
    });
  }

  // -----------------------------------------------------------------------
  // WebSocket mode
  // -----------------------------------------------------------------------

  async function startWebSocketMode(): Promise<void> {
    if (stopped) return;

    channelClient = createChannelClient(relayUrl, privateKey, token);

    try {
      await channelClient.connect();
    } catch (err) {
      log(`WebSocket connection failed: ${(err as Error).message}. Falling back to last-resort REST polling.`);
      channelClient = null;
      startRestFallback();
      return;
    }

    if (stopped) {
      channelClient?.disconnect();
      return;
    }

    log("WebSocket connected.");

    try {
      knowledgeChannel = await channelClient.joinKnowledge(teamId, {
        onJoin(hash, size, cap) {
          knowledgeCap = cap;
          logSizeWarning(size, cap);

          // Compare with local knowledge and merge if different
          const local = readLocalKnowledge();
          const localHash = local ? computeKnowledgeHash(local) : "";

          if (localHash && localHash !== hash) {
            if (hash) {
              // Both sides have content but differ -- fetch remote, merge, push merged result
              void fetchAndMergeViaRest().then(() => {
                if (!knowledgeChannel) return;
                const merged = readLocalKnowledge();
                if (merged) {
                  void knowledgeChannel.push(merged).then(
                    () => log("Merged knowledge pushed to relay."),
                    (err) => warn(`Failed to push merged knowledge: ${(err as Error).message}`),
                  );
                }
              });
            } else {
              // Remote is empty, local has content -- push local up
              void knowledgeChannel!.push(local).then(
                () => log("Local knowledge pushed to relay."),
                (err) => warn(`Failed to push local knowledge: ${(err as Error).message}`),
              );
            }
          } else if (hash && !localHash) {
            // Remote has content, local is empty -- pull
            void fetchAndMergeViaRest();
          }
        },

        onUpdate(content, hash, size) {
          if (stopped) return;

          logSizeWarning(size, knowledgeCap);

          // Merge remote content with local
          mergeAndWrite(content);
          log("Knowledge updated from remote.");
        },

        onError(error) {
          warn(`Channel error: ${error.message}`);
        },

        onClose() {
          if (stopped) return;
          log("Channel closed. Reconnecting...");
          knowledgeChannel = null;
          scheduleReconnect();
        },
      });
    } catch (err) {
      warn(`Failed to join knowledge channel: ${(err as Error).message}`);
      channelClient?.disconnect();
      channelClient = null;
      startRestFallback();
      return;
    }

    log(`Joined knowledge channel for team ${teamId}.`);

    // Join tasks channel
    try {
      tasksChannel = await channelClient!.joinTasks(teamId, {
        onJoin(tasks) {
          writeTaskCache(tasks, teamSlug);
          log(`Tasks: ${tasks.length} loaded.`);
        },
        onCreated(task) {
          if (stopped) return;
          log(`Task #${task.number} created -> ${task.assignee}`);
          void refreshTaskCache();
          // Auto-claim: if task assignee is in activeMembers and status is todo
          if (activeMembers.includes(task.assignee) && task.status === "todo") {
            void autoClaimTask(task.number);
          }
        },
        onUpdated(task) {
          if (stopped) return;
          log(`Task #${task.number} -> ${task.status}`);
          void refreshTaskCache();
        },
        onError(error) {
          warn(`Tasks channel error: ${error.message}`);
        },
        onClose() {
          if (stopped) return;
          log("Tasks channel closed.");
          tasksChannel = null;
        },
      });
      log(`Joined tasks channel for team ${teamId}.`);
    } catch (err) {
      warn(`Failed to join tasks channel: ${(err as Error).message}`);
    }

    // Set up file watcher for local changes -> push via channel
    setupFileWatcher((content) => {
      if (!knowledgeChannel) return;

      void knowledgeChannel.push(content).then(
        ({ knowledge_hash, knowledge_size }) => {
          logSizeWarning(knowledge_size, knowledgeCap);
          log("Knowledge pushed to relay.");
        },
        (err) => {
          warn(`Failed to push knowledge: ${(err as Error).message}`);
        },
      );
    });
  }

  /** Fetch current knowledge via REST and merge locally. Used on initial join. */
  async function fetchAndMergeViaRest(): Promise<void> {
    try {
      const team = await restClient.getTeam();
      if (team.knowledge) {
        mergeAndWrite(team.knowledge);
        log("Knowledge synced from relay.");
      }
    } catch (err) {
      if (err instanceof TeamNotFoundError) {
        warn("Team no longer exists on the relay.");
      } else {
        warn(`Failed to fetch knowledge: ${(err as Error).message}`);
      }
    }
  }

  function scheduleReconnect(): void {
    if (stopped) return;
    reconnectTimeout = setTimeout(() => {
      if (stopped) return;
      log("Attempting to reconnect WebSocket...");
      void startWebSocketMode();
    }, RECONNECT_DELAY_MS);
  }

  // -----------------------------------------------------------------------
  // REST last-resort fallback mode
  //
  // Phoenix longpoll handles primary transport fallback (WebSocket ->
  // longpoll) natively. This REST polling mode is a last-resort for when
  // the server is completely unreachable via both WebSocket and longpoll.
  // -----------------------------------------------------------------------

  let lastKnownKnowledgeHash: string | null = null;
  let restPolling = false;

  function startRestFallback(): void {
    if (stopped) return;
    log(`REST last-resort fallback active. Polling every ${fallbackPollInterval / 1000}s.`);

    // Set up file watcher for local changes -> push via REST
    setupFileWatcher((content) => {
      void pushKnowledgeViaRest(content);
    });

    // Initial bidirectional sync: push local if remote is empty, merge if both have content
    void initialRestSync();
    scheduleRestPoll();
  }

  async function initialRestSync(): Promise<void> {
    try {
      const local = readLocalKnowledge();
      const localHash = local ? computeKnowledgeHash(local) : "";

      const head = await restClient.getTeamHead();
      lastKnownKnowledgeHash = head.knowledge_hash;

      if (localHash && localHash !== head.knowledge_hash) {
        if (head.knowledge_hash) {
          // Both sides have content -- fetch, merge, push
          const team = await restClient.getTeam();
          if (team.knowledge) {
            mergeAndWrite(team.knowledge);
          }
          const merged = readLocalKnowledge();
          if (merged) {
            await pushKnowledgeViaRest(merged);
            log("Merged knowledge synced with relay.");
          }
        } else {
          // Remote empty, local has content -- push
          await pushKnowledgeViaRest(local);
          log("Local knowledge pushed to relay.");
        }
      } else if (head.knowledge_hash && !localHash) {
        // Remote has content, local empty -- pull
        await pollKnowledgeRest();
      } else {
        log("Knowledge already in sync.");
      }
    } catch (err) {
      warn(`Initial sync failed: ${(err as Error).message}. Will retry on next poll.`);
    }
  }

  function scheduleRestPoll(): void {
    if (stopped) return;
    pollTimeout = setTimeout(async () => {
      await pollKnowledgeRest();
      scheduleRestPoll();
    }, fallbackPollInterval);
  }

  async function pollKnowledgeRest(): Promise<void> {
    if (stopped || restPolling) return;
    restPolling = true;

    try {
      const head = await restClient.getTeamHead();

      if (head.knowledge_hash === lastKnownKnowledgeHash) {
        restPolling = false;
        return;
      }

      if (lastKnownKnowledgeHash !== null) {
        log("Remote knowledge changes detected.");
      }

      // Fetch full team to get knowledge content
      const team = await restClient.getTeam();
      if (team.knowledge) {
        mergeAndWrite(team.knowledge);
        const size = Buffer.byteLength(team.knowledge, "utf8");
        logSizeWarning(size, knowledgeCap);
        log("Knowledge synced from relay.");
      }

      lastKnownKnowledgeHash = head.knowledge_hash;
    } catch (err) {
      if (err instanceof TeamNotFoundError) {
        warn("Team no longer exists on the relay.");
      } else {
        warn(`REST poll failed: ${(err as Error).message}`);
      }
    } finally {
      restPolling = false;
    }
  }

  async function pushKnowledgeViaRest(content: string): Promise<void> {
    try {
      await restClient.pushKnowledge(content);
      log("Knowledge pushed via REST.");
    } catch (err) {
      warn(`Failed to push knowledge via REST: ${(err as Error).message}`);
    }
  }

  // -----------------------------------------------------------------------
  // Task cache
  // -----------------------------------------------------------------------

  function writeTaskCache(tasks: TaskChannelItem[], slug: string): void {
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
        lines.push(`- **#${t.number}** [${t.assignee}] ${t.description}`);
      }
      lines.push("");
    }

    fs.writeFileSync(path.join(cacheDir, `tasks-${slug}.md`), lines.join("\n"));
  }

  async function refreshTaskCache(): Promise<void> {
    try {
      const tasks = await restClient.listTasks();
      writeTaskCache(tasks, teamSlug);
    } catch (err) {
      warn(`Failed to refresh task cache: ${(err as Error).message}`);
    }
  }

  async function autoClaimTask(taskNumber: number): Promise<void> {
    try {
      await restClient.updateTask(taskNumber, "in_progress");
      log(`Auto-claimed task #${taskNumber}.`);
    } catch (err) {
      warn(`Failed to auto-claim task #${taskNumber}: ${(err as Error).message}`);
    }
  }

  // -----------------------------------------------------------------------
  // Start
  // -----------------------------------------------------------------------

  const modeLabel = restOnly ? "REST polling" : "WebSocket (longpoll fallback, REST last-resort)";
  log(`Knowledge daemon started (${scope} scope, ${modeLabel}).`);

  if (restOnly) {
    startRestFallback();
  } else {
    void startWebSocketMode();
  }

  // -----------------------------------------------------------------------
  // Stop
  // -----------------------------------------------------------------------

  return {
    stop() {
      stopped = true;

      // Clean up WebSocket
      tasksChannel?.leave();
      knowledgeChannel?.leave();
      channelClient?.disconnect();
      channelClient = null;
      knowledgeChannel = null;
      tasksChannel = null;

      // Clean up timers
      if (pollTimeout) clearTimeout(pollTimeout);
      if (reconnectTimeout) clearTimeout(reconnectTimeout);
      if (debounceTimer) clearTimeout(debounceTimer);

      // Clean up file watcher
      if (watcher) void watcher.close();

      log("Knowledge daemon stopped.");
    },
  };
}
