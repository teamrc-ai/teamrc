import * as fs from "node:fs";
import * as path from "node:path";
import { watch } from "chokidar";
import { hashContent, validateAgentName, type PlatformAdapter } from "./adapters/base.js";
import type { TeamrcClient, SyncChange } from "./client.js";
import { resolveChange } from "./merge.js";
import { readTeamYaml, resolveTeamYamlPath } from "./team-yaml.js";

const POLL_INTERVAL_MS = 2 * 60 * 1000; // 2 minutes
const MAX_CONTENT_SIZE = 1024 * 1024; // 1 MB per file
const MAX_CHANGES_PER_SYNC = 100;

export type SyncMode = "all" | "knowledge" | "none";

export interface DaemonOptions {
  adapter: PlatformAdapter;
  client: TeamrcClient;
  platform: string;
  pollInterval?: number;
  syncMode?: SyncMode;
}

export function startDaemon(opts: DaemonOptions): { stop: () => void } {
  const { adapter, client, platform } = opts;
  const pollInterval = opts.pollInterval ?? POLL_INTERVAL_MS;
  const syncMode: SyncMode = opts.syncMode ?? "knowledge";

  // Cache of hashes for files we've written ourselves (self-trigger prevention)
  // Maps hash → write timestamp for lazy age-based expiry
  const selfWrittenHashes = new Map<string, number>();

  // Last known hashes for change detection
  let lastHashes: Record<string, string> = adapter.getHashes();

  // Timestamp of last successful sync with relay
  let lastSyncTimestamp = Math.floor(Date.now() / 1000);

  // Track local modification timestamps per key
  const localModTimes = new Map<string, number>();

  let stopped = false;
  let syncing = false;
  let syncQueued = false;

  function log(msg: string): void {
    const ts = new Date().toISOString().slice(11, 19);
    console.log(`[${ts}] ${msg}`);
  }

  function warn(msg: string): void {
    const ts = new Date().toISOString().slice(11, 19);
    console.warn(`[${ts}] WARN: ${msg}`);
  }

  // Read file content and compute hash, returns null if file doesn't exist
  function readAndHash(filePath: string): { content: string; hash: string } | null {
    try {
      const content = fs.readFileSync(filePath, "utf-8");
      return { content, hash: hashContent(content) };
    } catch {
      return null;
    }
  }

  // Push local changes to relay (with mutex to prevent overlapping syncs)
  async function pushChanges(): Promise<void> {
    if (syncing) {
      syncQueued = true;
      return;
    }
    syncing = true;

    try {
      await doPushChanges();
    } finally {
      syncing = false;
      if (syncQueued) {
        syncQueued = false;
        void pushChanges();
      }
    }
  }

  async function doPushChanges(): Promise<void> {
    // Clean up stale self-written hashes (older than 60s)
    const cleanupThreshold = Date.now() - 60_000;
    for (const [hash, time] of selfWrittenHashes) {
      if (time < cleanupThreshold) selfWrittenHashes.delete(hash);
    }

    const currentHashes = adapter.getHashes();
    const changedFiles: Record<string, string> = {};
    const now = Math.floor(Date.now() / 1000);

    for (const [key, hash] of Object.entries(currentHashes)) {
      if (lastHashes[key] !== hash) {
        // Filter by syncMode
        if (syncMode === "knowledge" && !key.startsWith("knowledge:")) continue;
        if (syncMode === "none") continue;

        const content = adapter.readFile(key);
        if (content !== null) {
          changedFiles[key] = content;
          localModTimes.set(key, now);
        }
      }
    }

    if (Object.keys(changedFiles).length === 0) {
      lastHashes = currentHashes;
      return;
    }

    try {
      const result = await client.sync(platform, currentHashes, changedFiles);
      lastSyncTimestamp = Math.floor(Date.now() / 1000);
      lastHashes = currentHashes;
      try {
        applyRemoteChanges(result.changes);
      } catch (err) {
        warn(`Failed to apply remote changes: ${(err as Error).message}`);
      }
      log(`Pushed ${Object.keys(changedFiles).length} file(s), received ${Object.keys(result.changes).length} change(s).`);
    } catch (err) {
      warn(`Push failed: ${(err as Error).message}`);
    }
  }

  // Apply changes received from the relay using merge strategies
  function applyRemoteChanges(changes: Record<string, SyncChange>): void {
    const entries = Object.entries(changes);
    if (entries.length > MAX_CHANGES_PER_SYNC) {
      warn(`Relay sent ${entries.length} changes (max ${MAX_CHANGES_PER_SYNC}). Truncating.`);
    }

    for (const [key, remoteChange] of entries.slice(0, MAX_CHANGES_PER_SYNC)) {
      if (remoteChange.content.length > MAX_CONTENT_SIZE) {
        warn(`Skipping ${key}: content exceeds ${MAX_CONTENT_SIZE} bytes.`);
        continue;
      }

      // Filter by syncMode
      if (syncMode === "knowledge" && !key.startsWith("knowledge:")) {
        log(`Skipping ${key} (sync mode: knowledge)`);
        continue;
      }
      if (syncMode === "none") {
        log(`Remote change: ${key} (sync mode: none, not applying)`);
        continue;
      }

      // Validate agent names from relay
      if (key.startsWith("agent:")) {
        try {
          validateAgentName(key.replace("agent:", ""));
        } catch {
          warn(`Skipping invalid agent key: ${key}`);
          continue;
        }
      }
      const localContent = adapter.readFile(key);
      const localModTime = localModTimes.get(key) ?? 0;

      const result = resolveChange(key, localContent, remoteChange, localModTime);

      if (result.warning) {
        warn(result.warning);
      }

      if (result.action === "keep-local") {
        continue;
      }

      // Write the resolved content
      adapter.writeFile(key, result.content);
      const hash = hashContent(result.content);
      selfWrittenHashes.set(hash, Date.now());
      lastHashes[key] = hash;

      // Update local mod time to match remote after accepting
      if (result.action === "accept-remote") {
        localModTimes.set(key, remoteChange.updated_at);
      } else {
        // merged — treat as a new local modification
        localModTimes.set(key, Math.floor(Date.now() / 1000));
      }
    }
  }

  // Poll relay for remote changes
  async function pollRelay(): Promise<void> {
    if (stopped) return;

    try {
      const changed = await client.syncCheck(lastSyncTimestamp);
      if (!changed) return;

      log("Remote changes detected, syncing...");
      const currentHashes = adapter.getHashes();
      const result = await client.sync(platform, currentHashes);
      lastSyncTimestamp = Math.floor(Date.now() / 1000);
      lastHashes = currentHashes;

      const changeCount = Object.keys(result.changes).length;
      if (changeCount > 0) {
        try {
          applyRemoteChanges(result.changes);
        } catch (err) {
          warn(`Failed to apply remote changes: ${(err as Error).message}`);
        }
        log(`Applied ${changeCount} remote change(s).`);
      }
    } catch (err) {
      warn(`Poll failed (relay unreachable?): ${(err as Error).message}`);
    }
  }

  // File watcher — only watch paths that exist (or whose parent dir exists)
  const yamlPath = path.resolve(resolveTeamYamlPath());
  const adapterPaths = adapter.watchPaths().filter((p) =>
    fs.existsSync(p) || fs.existsSync(path.dirname(p)),
  );
  const watchPaths = [...adapterPaths, yamlPath];

  const watcher = watch(watchPaths, {
    ignoreInitial: true,
    awaitWriteFinish: { stabilityThreshold: 300, pollInterval: 100 },
  });

  async function handleYamlChange(): Promise<void> {
    const team = readTeamYaml(yamlPath);
    if (!team) return;

    log(".teamrc.yaml changed. Applying to platform...");
    adapter.writeTeam(team);

    // Push changes to relay
    void pushChanges();
  }

  watcher.on("change", (filePath: string) => {
    if (path.resolve(filePath) === yamlPath) {
      void handleYamlChange();
      return;
    }

    const file = readAndHash(filePath);
    if (!file) return;

    // Check if this was a self-triggered write (generous 30s window for slow filesystems)
    const writeTime = selfWrittenHashes.get(file.hash);
    if (writeTime !== undefined && Date.now() - writeTime < 30_000) {
      selfWrittenHashes.delete(file.hash);
      return;
    }

    log(`File changed: ${filePath}`);
    void pushChanges();
  });

  watcher.on("add", (filePath: string) => {
    if (path.resolve(filePath) === yamlPath) {
      void handleYamlChange();
      return;
    }

    log(`File added: ${filePath}`);
    void pushChanges();
  });

  // Poll interval
  const pollTimer = setInterval(() => {
    void pollRelay();
  }, pollInterval);

  log(`Daemon started. Watching ${watchPaths.length} path(s), polling every ${pollInterval / 1000}s.`);
  log(`Paths: ${watchPaths.join(", ")}`);

  // Initial sync
  void pollRelay();

  return {
    stop() {
      stopped = true;
      clearInterval(pollTimer);
      void watcher.close();
      log("Daemon stopped.");
    },
  };
}
