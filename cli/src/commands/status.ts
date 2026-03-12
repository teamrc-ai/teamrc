import * as os from "node:os";
import type { Command } from "commander";
import * as p from "@clack/prompts";
import { loadKeypair } from "../auth.js";
import { TeamrcClient } from "../client.js";
import { computeTeamHashes } from "../sync-hash.js";
import { loadConfig, detectPlatforms, getRelayUrl } from "../config.js";
import { getAdapter } from "../adapters/base.js";
import { readTeamYaml, TEAM_YAML, GLOBAL_TEAM_YAML } from "../team-yaml.js";
import { readSyncState, migrateLegacyYamlHashes } from "../sync-state.js";
import {
  globals,
  jsonOutput,
  cliCmd,
} from "../utils.js";

export function registerStatus(program: Command): void {
  program
    .command("status")
    .description("Show current configuration and sync state")
    .option("--json", "Output as JSON")
    .action(async (opts: { json?: boolean }) => {
      const useJson = opts.json ?? globals().json;
      const config = loadConfig();

      if (!config) {
        if (useJson) {
          jsonOutput({ error: "not initialized" });
        } else {
          p.intro("teamrc");
          p.log.warn("teamrc is not initialized.");
          p.outro(`Run \`${cliCmd("init")}\` to get started.`);
        }
        return;
      }

      let yamlTeam;
      try {
        yamlTeam = readTeamYaml(TEAM_YAML);
      } catch (e) {
        p.log.error(`Failed to parse .teamrc.yaml: ${e instanceof Error ? e.message : e}`);
        process.exit(1);
      }
      let globalYaml = null;
      if (!yamlTeam) {
        try {
          globalYaml = readTeamYaml(GLOBAL_TEAM_YAML);
        } catch (e) {
          p.log.error(`Failed to parse global team.yaml: ${e instanceof Error ? e.message : e}`);
          process.exit(1);
        }
      }
      const activeTeam = yamlTeam ?? globalYaml;
      const teamId = activeTeam?.teamId ?? null;
      const platformStr = activeTeam?.platforms?.join(",") ?? detectPlatforms()[0] ?? "claude-code";
      const activePlatform = platformStr.split(",")[0];
      const adapter = getAdapter(activePlatform);
      const statusRelayUrl = getRelayUrl(undefined, activeTeam?.relay);

      // Migrate legacy syncHash fields from YAML to state.json
      const activeYamlPath = yamlTeam ? TEAM_YAML : (globalYaml ? GLOBAL_TEAM_YAML : TEAM_YAML);
      migrateLegacyYamlHashes(activeYamlPath);

      // Check relay state and compute sync status
      let relayConnected = false;
      let syncStatus = "unknown";
      let serverHash: string | null = null;
      let localHash: string | null = null;
      if (teamId && activeTeam) {
        const kp = loadKeypair();
        if (kp) {
          const client = new TeamrcClient(statusRelayUrl, kp.privateKey, config.token, teamId);

          // Compute local hashes
          const knowledge = adapter.readKnowledge();
          const localHashes = computeTeamHashes(activeTeam, knowledge || undefined);
          localHash = localHashes.hash;

          try {
            const head = await client.getTeamHead();
            relayConnected = true;
            serverHash = head.hash;

            const statusSyncState = readSyncState();
            const lastSyncHash = statusSyncState.syncHash;
            if (localHashes.hash === head.hash) {
              syncStatus = "in sync";
            } else if (!lastSyncHash) {
              syncStatus = "never synced";
            } else if (head.hash === lastSyncHash && localHashes.hash !== lastSyncHash) {
              syncStatus = "local changes";
            } else if (localHashes.hash === lastSyncHash && head.hash !== lastSyncHash) {
              syncStatus = "remote changes";
            } else {
              syncStatus = "diverged";
            }
          } catch {
            // relay unreachable
          }
        }
      }

      if (useJson) {
        jsonOutput({
          machine: config.machineName ?? os.hostname(),
          token: config.token.slice(0, 12) + "...",
          relay: { url: statusRelayUrl, connected: relayConnected },
          account: config.account?.email ?? null,
          platform: platformStr,
          teamId,
          localTeam: activeTeam ?? null,
          syncHash: localHash,
          serverHash,
          syncStatus,
        });
        return;
      }

      p.intro("teamrc");

      // Machine identity block
      const identityLines = [
        `Machine   ${config.machineName ?? os.hostname()}`,
        `Identity  ${config.token.slice(0, 12)}...`,
        `Relay     ${statusRelayUrl}  ${relayConnected ? "connected" : "unreachable"}`,
      ];
      if (config.account?.email) {
        identityLines.push(`Account   ${config.account.email}`);
      }
      p.log.info(identityLines.join("\n"));

      // Local team info
      if (activeTeam) {
        const memberLines = activeTeam.members.map(
          (m) => `  ${m.name.padEnd(14)} ${m.role}`,
        );
        const hashLine = localHash
          ? `Hash       ${localHash.slice(0, 12)}... (${syncStatus})`
          : `Hash       none`;
        p.note(
          [
            `Team ID    ${teamId ?? "none"}`,
            `Platforms  ${platformStr}`,
            hashLine,
            `Members    ${activeTeam.members.length} agents`,
            ...memberLines,
          ].join("\n"),
          `Local team: ${activeTeam.name}`,
        );
      } else {
        p.log.warn("No local team agents found.");
      }

      p.outro("Done.");
    });
}
