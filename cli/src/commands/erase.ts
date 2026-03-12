import type { Command } from "commander";
import * as p from "@clack/prompts";
import { loadKeypair, toToken } from "../auth.js";
import { TeamrcClient } from "../client.js";
import { loadConfig, getRelayUrl } from "../config.js";
import { readTeamYaml, TEAM_YAML, GLOBAL_TEAM_YAML } from "../team-yaml.js";
import {
  globals,
  requireTTY,
  handleCancel,
} from "../utils.js";

export function registerErase(program: Command): void {
  program
    .command("erase")
    .description("Permanently erase this machine's token and all associated team data from the relay")
    .option("-y, --yes", "Skip confirmation prompt")
    .action(async (opts: { yes?: boolean }) => {
      p.intro("teamrc");

      const kp = loadKeypair();
      if (!kp) {
        p.log.error("No keypair found. Nothing to erase.");
        process.exit(1);
      }
      const token = toToken(kp.publicKey);
      const config = loadConfig();
      if (!config) {
        p.log.error("Not initialized. Nothing to erase.");
        process.exit(1);
      }

      // Read YAML early so we can use its relay field
      let eraseYaml;
      try {
        eraseYaml = readTeamYaml(TEAM_YAML) ?? readTeamYaml(GLOBAL_TEAM_YAML);
      } catch {
        // ignore parse errors
      }
      const relayUrl = getRelayUrl(undefined, eraseYaml?.relay);
      const client = new TeamrcClient(relayUrl, kp.privateKey, token);

      // Fetch current status to show what will be erased
      let teamCount = 0;
      let teamName: string | null = null;
      try {
        const remoteTeam = await client.getTeam();
        teamName = remoteTeam.name;
        teamCount = 1;
      } catch {
        // May have multiple teams or none
      }

      // Also try YAML for team name
      if (!teamName) {
        teamName = eraseYaml?.name ?? null;
      }

      p.log.warn(
        "This will permanently erase this machine's token and all\n" +
        "associated team data from the relay. This cannot be undone.",
      );
      if (teamName) {
        p.log.info(`Team: ${teamName}`);
      }
      p.log.info(`Token: ${token.slice(0, 16)}...`);

      const skipConfirm = opts.yes ?? globals().yes;
      if (!skipConfirm) {
        if (teamName) {
          requireTTY("--yes");
          const confirmation = await p.text({
            message: `Type "${teamName}" to confirm erasure:`,
            validate: (value) => {
              if (value !== teamName) return `Please type "${teamName}" to confirm.`;
            },
          });
          handleCancel(confirmation);
        } else {
          requireTTY("--yes");
          const shouldErase = await p.confirm({
            message: "Erase all data for this token from the relay?",
            initialValue: false,
          });
          handleCancel(shouldErase);
          if (!shouldErase) {
            p.cancel("Cancelled.");
            return;
          }
        }
      }

      const s = p.spinner();
      try {
        s.start("Erasing from relay...");
        const result = await client.eraseToken();
        s.stop("Erased.");

        p.log.success(`Removed ${result.teams_removed} team(s) from relay.`);
        p.outro("Local files are unchanged. Run `teamrc delete` to also remove local config.");
      } catch (err) {
        s.error("Erase failed.");
        p.log.error((err as Error).message);
        process.exit(1);
      }
    });
}
