import type { Command } from "commander";
import * as p from "@clack/prompts";
import { SyncConflictError } from "../client.js";
import { TEAM_YAML, GLOBAL_TEAM_YAML, mergeKnowledge, MAX_KNOWLEDGE_SIZE } from "../team-yaml.js";
import { readSyncState, writeSyncState, migrateLegacyYamlHashes } from "../sync-state.js";
import {
  requireTeamContext,
  cliCmd,
} from "../utils.js";

export function registerPush(program: Command): void {
  program
    .command("push")
    .description("Push team definition and knowledge to relay")
    .action(async () => {
      p.intro("teamrc");

      const ctx = requireTeamContext();
      const { client } = ctx;
      const adapter = ctx.adapters[0];
      const team = ctx.team;
      const yamlPath = ctx.scope === "global" ? GLOBAL_TEAM_YAML : TEAM_YAML;
      // Migrate legacy syncHash fields from YAML to state.json
      migrateLegacyYamlHashes(yamlPath);

      const s = p.spinner();
      try {
        s.start("Pushing to relay...");
        const knowledge = adapter.readKnowledge();
        const pushSyncState = readSyncState();
        const baseHash = pushSyncState.syncHash;

        // Merge knowledge (append-only) so local edits don't overwrite remote knowledge
        let pushKnowledge = knowledge || undefined;
        const remoteTeam = await client.getTeam();
        if (remoteTeam.knowledge) {
          const merged = mergeKnowledge(remoteTeam.knowledge, knowledge);
          if (merged.length <= MAX_KNOWLEDGE_SIZE) {
            pushKnowledge = merged;
            adapter.writeKnowledge(merged);
          }
        }

        await client.pushTeam(team, pushKnowledge, undefined, baseHash);

        // Update sync hashes after successful push
        const newHead = await client.getTeamHead();
        writeSyncState({
          syncHash: newHead.hash,
          syncHashMembers: newHead.members_hash,
          syncHashSkills: newHead.skills_hash,
          syncHashKnowledge: newHead.knowledge_hash,
        });

        s.stop("Pushed team definition and knowledge.");
        p.outro("Done.");
      } catch (err) {
        s.error("Push failed.");
        if (err instanceof SyncConflictError) {
          p.log.error(`Remote has changes. Run \`${cliCmd("pull")}\` first.`);
        } else {
          p.log.error((err as Error).message);
        }
        process.exit(1);
      }
    });
}
