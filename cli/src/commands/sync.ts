import type { Command } from "commander";
import * as p from "@clack/prompts";
import { remoteTeamToDefinition, SyncConflictError } from "../client.js";
import { computeTeamHashes } from "../sync-hash.js";
import { getAdapter, type TeamScope } from "../adapters/base.js";
import { readTeamYaml, writeTeamYaml, validateTeamName, TEAM_YAML, mergeKnowledge, MAX_KNOWLEDGE_SIZE } from "../team-yaml.js";
import { readSyncState, writeSyncState, migrateLegacyYamlHashes } from "../sync-state.js";
import {
  requireTeamContext,
  effectiveScope,
} from "../utils.js";

export function registerSync(program: Command): void {
  program
    .command("sync")
    .description("Push local changes to relay and pull remote updates")
    .option("--platform <platform>", "Override platform detection")
    .option("--scope <scope>", "Team scope: project or global")
    .option("--global", "Pull as global team")
    .action(async (opts: { platform?: string; scope?: string; global?: boolean }) => {
      p.intro("teamrc");

      const ctx = requireTeamContext();
      const { client } = ctx;
      const scope = opts.global ? "global" : (opts.scope as TeamScope) ?? ctx.scope;
      const platforms = opts.platform
        ? opts.platform.split(",").map((s) => s.trim()).filter(Boolean)
        : ctx.platforms;
      const adapter = ctx.adapters[0];

      const s = p.spinner();
      try {
        // 1. Read local state
        const team = readTeamYaml(TEAM_YAML);
        if (!team) {
          s.stop("No .teamrc.yaml found.");
          process.exit(1);
        }
        // Migrate legacy syncHash fields from YAML to state.json
        migrateLegacyYamlHashes(TEAM_YAML);
        const knowledge = adapter.readKnowledge();
        const localHashes = computeTeamHashes(team, knowledge || undefined);
        const syncState = readSyncState();
        const lastSyncHash = syncState.syncHash;

        // 2. Get server hashes
        s.start("Checking sync state...");
        const serverHead = await client.getTeamHead();

        if (localHashes.hash === serverHead.hash) {
          // a. Already in sync
          s.stop("Already in sync.");
          p.outro("Done.");
          return;
        }

        if (!lastSyncHash) {
          // b. Never synced — push unconditionally (no base_hash)
          s.start("First sync: pushing to relay...");
          await client.pushTeam(team, knowledge || undefined);
          const newHead = await client.getTeamHead();
          writeSyncState({
            syncHash: newHead.hash,
            syncHashMembers: newHead.members_hash,
            syncHashSkills: newHead.skills_hash,
            syncHashKnowledge: newHead.knowledge_hash,
          });
          s.stop("Pushed (first sync).");
          p.outro("Synced.");
          return;
        }

        const localChanged = localHashes.hash !== lastSyncHash;
        const serverChanged = serverHead.hash !== lastSyncHash;

        if (!serverChanged && localChanged) {
          // c. Server unchanged, local changed — push with base_hash
          // Merge knowledge (append-only) so local edits don't overwrite remote knowledge
          s.start("Pushing local changes...");
          let pushKnowledge = knowledge || undefined;
          if (localHashes.knowledgeHash !== serverHead.knowledge_hash) {
            const remoteTeam = await client.getTeam();
            if (remoteTeam.knowledge) {
              const merged = mergeKnowledge(remoteTeam.knowledge, knowledge);
              if (merged.length <= MAX_KNOWLEDGE_SIZE) {
                pushKnowledge = merged;
                adapter.writeKnowledge(merged);
              }
            }
          }
          await client.pushTeam(team, pushKnowledge, undefined, lastSyncHash);
          const newHead = await client.getTeamHead();
          writeSyncState({
            syncHash: newHead.hash,
            syncHashMembers: newHead.members_hash,
            syncHashSkills: newHead.skills_hash,
            syncHashKnowledge: newHead.knowledge_hash,
          });
          s.stop("Pushed local changes.");
          p.outro("Synced.");
          return;
        }

        if (serverChanged && !localChanged) {
          // d. Local unchanged, server changed — pull
          s.start("Pulling remote changes...");
          const remoteTeam = await client.getTeam();
          validateTeamName(remoteTeam.name);
          const remoteDef = remoteTeamToDefinition(remoteTeam);

          remoteDef.teamId = ctx.team.teamId;
          remoteDef.relay = ctx.team.relay;
          remoteDef.platforms = ctx.team.platforms;

          if (remoteTeam.knowledge) {
            const localKnowledge = adapter.readKnowledge();
            const merged = mergeKnowledge(remoteTeam.knowledge, localKnowledge);
            if (merged.length <= MAX_KNOWLEDGE_SIZE) {
              adapter.writeKnowledge(merged);
            } else {
              p.log.warn("Remote knowledge exceeds maximum size, skipping merge.");
            }
          }

          writeTeamYaml(TEAM_YAML, remoteDef);
          writeSyncState({
            syncHash: serverHead.hash,
            syncHashMembers: serverHead.members_hash,
            syncHashSkills: serverHead.skills_hash,
            syncHashKnowledge: serverHead.knowledge_hash,
          });
          for (const pl of platforms) {
            const a = getAdapter(pl);
            a.writeTeam(remoteDef, effectiveScope(pl, scope));
          }
          s.stop("Pulled and applied remote changes.");
          p.outro("Synced.");
          return;
        }

        // e. Both changed — diverged
        const onlyKnowledgeDiffers =
          localHashes.membersHash === serverHead.members_hash &&
          localHashes.skillsHash === serverHead.skills_hash &&
          localHashes.knowledgeHash !== serverHead.knowledge_hash;

        if (onlyKnowledgeDiffers) {
          // Push knowledge, then pull
          s.start("Syncing knowledge...");
          try {
            await client.pushTeam(team, knowledge || undefined, undefined, lastSyncHash);
          } catch (err) {
            if (err instanceof SyncConflictError) {
              // Fall through to pull
            } else {
              throw err;
            }
          }
          const remoteTeam = await client.getTeam();
          validateTeamName(remoteTeam.name);
          const remoteDef = remoteTeamToDefinition(remoteTeam);
          remoteDef.teamId = ctx.team.teamId;
          remoteDef.relay = ctx.team.relay;
          remoteDef.platforms = ctx.team.platforms;

          const newHead = await client.getTeamHead();

          if (remoteTeam.knowledge) {
            const localKnowledge = adapter.readKnowledge();
            const merged = mergeKnowledge(remoteTeam.knowledge, localKnowledge);
            if (merged.length <= MAX_KNOWLEDGE_SIZE) {
              adapter.writeKnowledge(merged);
            } else {
              p.log.warn("Remote knowledge exceeds maximum size, skipping merge.");
            }
          }

          writeTeamYaml(TEAM_YAML, remoteDef);
          writeSyncState({
            syncHash: newHead.hash,
            syncHashMembers: newHead.members_hash,
            syncHashSkills: newHead.skills_hash,
            syncHashKnowledge: newHead.knowledge_hash,
          });
          for (const pl of platforms) {
            const a = getAdapter(pl);
            a.writeTeam(remoteDef, effectiveScope(pl, scope));
          }
          s.stop("Synced knowledge and pulled.");
          p.outro("Synced.");
          return;
        }

        // Members/skills differ on both sides — pull first, warn user
        s.start("Both sides changed. Pulling remote first...");
        p.log.warn("Both local and remote have changes. Pulling remote changes first. Run `teamrc push` to push local changes.");
        const remoteTeam = await client.getTeam();
        validateTeamName(remoteTeam.name);
        const remoteDef = remoteTeamToDefinition(remoteTeam);

        remoteDef.teamId = ctx.team.teamId;
        remoteDef.relay = ctx.team.relay;
        remoteDef.platforms = ctx.team.platforms;

        if (remoteTeam.knowledge) {
          const localKnowledge = adapter.readKnowledge();
          const merged = mergeKnowledge(remoteTeam.knowledge, localKnowledge);
          if (merged.length <= MAX_KNOWLEDGE_SIZE) {
            adapter.writeKnowledge(merged);
          } else {
            p.log.warn("Remote knowledge exceeds maximum size, skipping merge.");
          }
        }

        writeTeamYaml(TEAM_YAML, remoteDef);
        writeSyncState({
          syncHash: serverHead.hash,
          syncHashMembers: serverHead.members_hash,
          syncHashSkills: serverHead.skills_hash,
          syncHashKnowledge: serverHead.knowledge_hash,
        });
        for (const pl of platforms) {
          const a = getAdapter(pl);
          a.writeTeam(remoteDef, effectiveScope(pl, scope));
        }
        s.stop("Pulled remote changes.");
        p.outro("Synced. Run `teamrc push` to push local changes.");
      } catch (err) {
        s.stop("Sync failed.");
        p.log.error((err as Error).message);
        process.exit(1);
      }
    });
}
