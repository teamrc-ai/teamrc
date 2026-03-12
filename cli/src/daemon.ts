import * as path from "node:path";
import { watch } from "chokidar";
import type { PlatformAdapter, TeamDefinition } from "./adapters/base.js";
import type { TeamrcClient, TeamrcTeam } from "./client.js";
import { remoteTeamToDefinition } from "./client.js";
import { readTeamYaml, writeTeamYaml, TEAM_YAML, validateTeamName, mergeKnowledge, MAX_KNOWLEDGE_SIZE } from "./team-yaml.js";

const DEFAULT_POLL_INTERVAL_MS = 2 * 60 * 1000; // 2 minutes

export interface DaemonOptions {
  client: TeamrcClient;
  adapters: PlatformAdapter[];
  platforms: string[];
  pollInterval?: number;
  watchYaml?: boolean;
}

export function startDaemon(opts: DaemonOptions): { stop: () => void } {
  const { client, adapters, platforms } = opts;
  const pollInterval = opts.pollInterval ?? DEFAULT_POLL_INTERVAL_MS;
  const watchYaml = opts.watchYaml ?? true;

  let lastKnownHash: string | null = null;
  let stopped = false;

  function log(msg: string): void {
    const ts = new Date().toISOString().slice(11, 19);
    console.log(`[${ts}] ${msg}`);
  }

  function warn(msg: string): void {
    const ts = new Date().toISOString().slice(11, 19);
    console.warn(`[${ts}] WARN: ${msg}`);
  }

  /** Apply a team definition to all platforms */
  function applyToAllPlatforms(team: TeamDefinition): void {
    for (let i = 0; i < adapters.length; i++) {
      try {
        adapters[i].writeTeam(team);
      } catch (err) {
        warn(`Failed to apply to ${platforms[i]}: ${(err as Error).message}`);
      }
    }
  }

  /** Poll relay for updates using hash-based change detection */
  async function pollRelay(): Promise<void> {
    if (stopped) return;

    try {
      const localYaml = readTeamYaml(TEAM_YAML);
      if (!localYaml?.teamId) return;

      // Cheap check: fetch only the hash from the server
      const head = await client.getTeamHead();

      // If hash hasn't changed since last poll, skip
      if (head.hash === lastKnownHash) {
        return;
      }

      if (lastKnownHash !== null) {
        // Only log on subsequent polls (not the first one)
        log("Remote changes detected, pulling...");
      }

      // Full fetch since hash differs
      const remoteTeam: TeamrcTeam = await client.getTeam();

      // Convert to definition
      validateTeamName(remoteTeam.name);
      const remoteDef = remoteTeamToDefinition(remoteTeam);

      // Preserve local YAML metadata
      remoteDef.teamId = localYaml.teamId;
      remoteDef.relay = localYaml.relay;
      remoteDef.platforms = localYaml.platforms;

      // Store sync hashes so sync/push/pull know the last-synced state
      remoteDef.syncHash = head.hash;
      remoteDef.syncHashMembers = head.members_hash;
      remoteDef.syncHashSkills = head.skills_hash;
      remoteDef.syncHashKnowledge = head.knowledge_hash;

      // Merge knowledge
      if (remoteTeam.knowledge && adapters.length > 0) {
        const localKnowledge = adapters[0].readKnowledge();
        const merged = mergeKnowledge(remoteTeam.knowledge, localKnowledge);
        if (merged.length <= MAX_KNOWLEDGE_SIZE) {
          adapters[0].writeKnowledge(merged);
        } else {
          warn("Remote knowledge exceeds maximum size, skipping merge.");
        }
      }

      // Write YAML and apply — only update hash after successful write
      writeTeamYaml(TEAM_YAML, remoteDef);
      applyToAllPlatforms(remoteDef);
      lastKnownHash = head.hash;

      log(`Applied remote changes (${remoteDef.members.length} agents).`);
    } catch (err) {
      warn(`Poll failed: ${(err as Error).message}`);
    }
  }

  // Set up YAML file watcher for auto-apply on local edits
  let watcher: ReturnType<typeof watch> | null = null;

  if (watchYaml) {
    const yamlPath = path.resolve(TEAM_YAML);
    watcher = watch(yamlPath, {
      ignoreInitial: true,
      awaitWriteFinish: { stabilityThreshold: 300, pollInterval: 100 },
    });

    watcher.on("change", () => {
      const team = readTeamYaml(TEAM_YAML);
      if (!team) return;
      log(".teamrc.yaml changed. Applying to platforms...");
      applyToAllPlatforms(team);
    });
  }

  // Poll interval
  const pollTimer = setInterval(() => {
    void pollRelay();
  }, pollInterval);

  log(`Daemon started. Polling every ${pollInterval / 1000}s.${watchYaml ? " Watching .teamrc.yaml." : ""}`);

  // Initial poll
  void pollRelay();

  return {
    stop() {
      stopped = true;
      clearInterval(pollTimer);
      if (watcher) void watcher.close();
      log("Daemon stopped.");
    },
  };
}
