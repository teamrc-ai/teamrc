import type { Command } from "commander";
import * as p from "@clack/prompts";
import { SyncConflictError } from "../client.js";
import { readTeamYaml, TEAM_YAML, mergeKnowledge, MAX_KNOWLEDGE_SIZE } from "../team-yaml.js";
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

      let team;
      try {
        team = readTeamYaml(TEAM_YAML);
      } catch (e) {
        p.log.error(`Failed to parse .teamrc.yaml: ${e instanceof Error ? e.message : e}`);
        process.exit(1);
      }
      if (!team) {
        p.log.error(`No .teamrc.yaml found. Run \`${cliCmd("init")}\` first.`);
        process.exit(1);
      }
      // Migrate legacy syncHash fields from YAML to state.json
      migrateLegacyYamlHashes(TEAM_YAML);

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
        s.stop("Push failed.");
        if (err instanceof SyncConflictError) {
          p.log.error(`Remote has changes. Run \`${cliCmd("pull")}\` first.`);
        } else {
          p.log.error((err as Error).message);
        }
        process.exit(1);
      }
    });
}
