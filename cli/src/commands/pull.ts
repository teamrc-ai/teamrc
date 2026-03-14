import type { Command } from "commander";
import * as p from "@clack/prompts";
import { TeamrcClient, remoteTeamToDefinition, TeamNotFoundError } from "../client.js";
import { toToken } from "../auth.js";
import { getRelayUrl } from "../config.js";
import { getAdapter, slugify, type TeamScope } from "../adapters/base.js";
import { readTeamYaml, writeTeamYaml, validateTeamName, TEAM_YAML, GLOBAL_TEAM_YAML, mergeKnowledge, pruneKnowledge, MAX_KNOWLEDGE_SIZE } from "../team-yaml.js";
import { logKnowledgeSize } from "../knowledge-log.js";
import { readSyncState, writeSyncState, migrateLegacyYamlHashes } from "../sync-state.js";
import {
  requirePlatforms,
  requireKeypair,
  requireRelayContext,
  selectScope,
  effectiveScope,
  handleTeamNotFound,
  cliCmd,
} from "../utils.js";

export function registerPull(program: Command): void {
  program
    .command("pull")
    .description("Pull team from relay and apply to local platforms")
    .option("--platform <platform>", "Override platform detection")
    .option("--scope <scope>", "Team scope: project or global")
    .option("--global", "Pull as global team")
    .action(async (opts: { platform?: string; scope?: string; global?: boolean }) => {
      p.intro("teamrc");

      // Check for clone-only teams (no teamId, but has cloneToken)
      const projectYaml = readTeamYaml(TEAM_YAML);
      const globalYaml = readTeamYaml(GLOBAL_TEAM_YAML);
      const localYaml = projectYaml ?? globalYaml;
      const isClone = !localYaml?.teamId && !!localYaml?.cloneToken;

      if (isClone) {
        // Clone pull: read-only fetch via clone token, no knowledge
        const scope = await selectScope(opts);
        const platforms = await requirePlatforms(opts.platform, scope);
        const relayUrl = getRelayUrl(undefined, localYaml!.relay);
        const kp = await requireKeypair();
        const client = new TeamrcClient(relayUrl, kp.privateKey, toToken(kp.publicKey));

        const s = p.spinner();
        try {
          s.start("Pulling from relay (read-only)...");
          const remoteTeam = await client.cloneByToken(localYaml!.cloneToken!);
          validateTeamName(remoteTeam.name);
          const team = remoteTeamToDefinition(remoteTeam);

          // Preserve local metadata
          team.cloneToken = localYaml!.cloneToken;
          team.relay = localYaml!.relay;
          team.platforms = localYaml!.platforms;

          const yamlPath = projectYaml ? TEAM_YAML : GLOBAL_TEAM_YAML;
          writeTeamYaml(yamlPath, team);
          s.stop(`Pulled "${team.name}" (${team.members.length} agents, read-only).`);

          for (const pl of platforms) {
            const a = getAdapter(pl, slugify(team.name));
            a.writeTeam(team, effectiveScope(pl, scope));
            p.log.step(`Applied to ${pl} (${effectiveScope(pl, scope)} scope).`);
          }

          p.outro("Done. Knowledge is not synced for cloned teams.");
        } catch (err) {
          s.error("Pull failed.");
          p.log.error((err as Error).message);
          process.exit(1);
        }
      } else {
        // Full member pull
        const ctx = requireRelayContext();
        const { client } = ctx;
        const scope = opts.global ? "global" : (opts.scope as TeamScope) ?? ctx.scope;
        const platforms = opts.platform
          ? opts.platform.split(",").map((s) => s.trim()).filter(Boolean)
          : ctx.platforms;
        const adapter = ctx.adapters[0];
        const yamlPath = scope === "global" ? GLOBAL_TEAM_YAML : TEAM_YAML;

        // Migrate legacy syncHash fields from YAML to state.json
        migrateLegacyYamlHashes(yamlPath);

        const s = p.spinner();
        try {
          // Check if already up to date via hash comparison
          const head = await client.getTeamHead();
          const pullSyncState = readSyncState();
          if (head.hash === pullSyncState.syncHash) {
            p.log.info("Already up to date.");
            p.outro("Done.");
            return;
          }

          s.start("Pulling from relay...");
          const remoteTeam = await client.getTeam();
          validateTeamName(remoteTeam.name);
          const team = remoteTeamToDefinition(remoteTeam);

          // Preserve local YAML metadata
          team.teamId = ctx.team.teamId;
          team.relay = ctx.team.relay;
          team.platforms = ctx.team.platforms;

          // Merge knowledge (members only)
          if (remoteTeam.knowledge) {
            const localKnowledge = adapter.readKnowledge();
            let merged = mergeKnowledge(remoteTeam.knowledge, localKnowledge);
            const prePruneSize = Buffer.byteLength(merged, "utf8");
            merged = pruneKnowledge(merged);
            const postPruneSize = Buffer.byteLength(merged, "utf8");
            if (postPruneSize < prePruneSize) {
              p.log.warn("Knowledge pruned: oldest entries dropped to fit within 100KB relay limit.");
            }
            if (merged.length <= MAX_KNOWLEDGE_SIZE) {
              adapter.writeKnowledge(merged);
              logKnowledgeSize(p.log, postPruneSize);
            } else {
              p.log.warn("Remote knowledge exceeds maximum size, skipping merge.");
            }
          }

          writeTeamYaml(yamlPath, team);
          writeSyncState({
            syncHash: head.hash,
            syncHashMembers: head.members_hash,
            syncHashSkills: head.skills_hash,
            syncHashKnowledge: head.knowledge_hash,
          });
          s.stop(`Pulled "${team.name}" (${team.members.length} agents).`);

          // Apply to platforms
          for (const pl of platforms) {
            const a = getAdapter(pl, slugify(team.name));
            a.writeTeam(team, effectiveScope(pl, scope));
            p.log.step(`Applied to ${pl} (${effectiveScope(pl, scope)} scope).`);
          }

          p.outro("Done.");
        } catch (err) {
          if (err instanceof TeamNotFoundError) {
            s.stop("Team not found.");
            const recreated = await handleTeamNotFound(ctx);
            if (recreated) {
              p.outro(`New team created. Run \`${cliCmd("pull")}\` again to pull.`);
            } else {
              p.outro("Done.");
            }
            return;
          }
          s.error("Pull failed.");
          p.log.error((err as Error).message);
          process.exit(1);
        }
      }
    });
}
