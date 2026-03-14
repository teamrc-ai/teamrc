import * as os from "node:os";
import type { Command } from "commander";
import * as p from "@clack/prompts";
import { loadKeypair, toToken } from "../auth.js";
import { SyncConflictError, TeamNotFoundError, TeamrcClient } from "../client.js";
import { getRelayUrl } from "../config.js";
import { TEAM_YAML, GLOBAL_TEAM_YAML, writeTeamYaml, mergeKnowledge, pruneKnowledge, MAX_KNOWLEDGE_SIZE } from "../team-yaml.js";
import { logKnowledgeSize } from "../knowledge-log.js";
import { readSyncState, writeSyncState, migrateLegacyYamlHashes } from "../sync-state.js";
import {
  requireTeamContext,
  handleTeamNotFound,
  isNonInteractive,
  deviceAuthFlow,
  cliCmd,
} from "../utils.js";

export function registerPush(program: Command): void {
  program
    .command("push")
    .description("Push team definition and knowledge to relay")
    .action(async () => {
      p.intro("teamrc");

      const ctx = requireTeamContext();
      const { team } = ctx;
      const adapter = ctx.adapters[0];
      const yamlPath = ctx.scope === "global" ? GLOBAL_TEAM_YAML : TEAM_YAML;

      if (!ctx.client) {
        // "Connect" flow — register local team with relay
        const kp = loadKeypair();
        if (!kp) {
          p.log.error(`No keypair found. Run \`${cliCmd("init")}\` first.`);
          process.exit(1);
        }
        const token = toToken(kp.publicKey);
        const relayUrl = getRelayUrl();
        const client = new TeamrcClient(relayUrl, kp.privateKey, token);

        const s = p.spinner();
        try {
          s.start("Creating team on relay...");
          const relayTeam = await client.createTeam(
            team.name,
            team.members.map((m) => ({ name: m.name, role: m.role, ...(m.skills?.length ? { skills: m.skills } : {}) })),
            team.skills,
          );
          s.stop("Team created on relay.");

          team.teamId = relayTeam.id;
          team.relay = relayUrl;
          client.setTeamId(relayTeam.id);

          // Push knowledge if it exists
          const knowledge = adapter.readKnowledge();
          if (knowledge) {
            await client.pushTeam(team, knowledge);
          }

          writeTeamYaml(yamlPath, team);
          p.log.step(`Updated ${yamlPath} with relay connection.`);

          // Show ownership token or confirm auto-assignment
          if (relayTeam.owner_claim_secret) {
            const dim = (s: string) => `\x1b[2m${s}\x1b[0m`;
            const yellow = (s: string) => `\x1b[33m${s}\x1b[0m`;
            p.log.warn(
              `${yellow("Save this to claim ownership:")}  ${relayTeam.owner_claim_secret}\n` +
              `${dim(`Run \`${cliCmd("claim <token>")}\` anytime, or link your account now to claim automatically.`)}`,
            );

            if (!isNonInteractive()) {
              const shouldLink = await p.confirm({
                message: "Link your account? (claims ownership automatically)",
                initialValue: true,
              });
              if (!p.isCancel(shouldLink) && shouldLink) {
                const machineName = os.hostname();
                const success = await deviceAuthFlow(client, machineName, relayUrl);
                if (success) {
                  try {
                    await client.claimOwnership(relayTeam.owner_claim_secret);
                    p.log.step("Ownership claimed.");
                  } catch {
                    p.log.warn(`Account linked, but ownership claim failed. Run \`${cliCmd("claim <token>")}\` later.`);
                  }
                }
              }
            }
          } else {
            p.log.step("You own this team.");
          }

          // Create invite
          let inviteInfo: { invite_code: string; expires_at: string } | null = null;
          try {
            inviteInfo = await client.createInvite(24);
          } catch {
            // invite creation may not be available
          }
          if (inviteInfo) {
            p.note(
              `npx @teamrc/cli join ${inviteInfo.invite_code}\nInvite code expires in 24 hours.`,
              "Share with teammates",
            );
          }

          p.outro("Connected to relay.");
        } catch (err) {
          s.error("Failed to create team on relay.");
          p.log.warn(`Relay error: ${(err as Error).message}`);
          p.outro(`Check your relay connection and try again.`);
        }
        return;
      }

      // Existing push flow for already-connected teams (client guaranteed non-null after guard above)
      const client = ctx.client!;

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
          let merged = mergeKnowledge(remoteTeam.knowledge, knowledge);
          const prePruneSize = Buffer.byteLength(merged, "utf8");
          merged = pruneKnowledge(merged);
          const postPruneSize = Buffer.byteLength(merged, "utf8");
          if (postPruneSize < prePruneSize) {
            p.log.warn("Knowledge pruned: oldest entries dropped to fit within 100KB relay limit.");
          }
          if (merged.length <= MAX_KNOWLEDGE_SIZE) {
            pushKnowledge = merged;
            adapter.writeKnowledge(merged);
            logKnowledgeSize(p.log, postPruneSize);
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
        if (err instanceof TeamNotFoundError) {
          s.stop("Team not found.");
          const recreated = await handleTeamNotFound(ctx as typeof ctx & { client: TeamrcClient });
          if (recreated) {
            p.outro("New team created and pushed.");
          } else {
            p.outro("Done.");
          }
          return;
        }
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
