import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";
import type { Command } from "commander";
import * as p from "@clack/prompts";
import { loadKeypair, toToken } from "../auth.js";
import { TeamrcClient } from "../client.js";
import { loadConfig, detectPlatforms, getRelayUrl } from "../config.js";
import { getAdapter } from "../adapters/base.js";
import { readTeamYaml, TEAM_YAML, GLOBAL_TEAM_YAML } from "../team-yaml.js";
import {
  globals,
  requireTTY,
  handleCancel,
  cliCmd,
} from "../utils.js";

export function registerDelete(program: Command): void {
  program
    .command("delete")
    .description("Remove teamrc from this machine")
    .option("-y, --yes", "Skip confirmation prompt (defaults to --scope all)")
    .option("--scope <scope>", "Deletion scope: project, global, or all (used with --yes)")
    .action(async (opts: { yes?: boolean; scope?: string }) => {
      p.intro("teamrc");

      const config = loadConfig();
      if (!config) {
        p.log.info("teamrc is not initialized. Nothing to remove.");
        p.outro("Done.");
        return;
      }

      // Validate --scope if provided
      const validScopes = ["project", "global", "all"];
      if (opts.scope && !validScopes.includes(opts.scope)) {
        p.log.error(`Invalid scope: ${opts.scope}. Valid options: ${validScopes.join(", ")}`);
        process.exit(1);
      }

      // Read both team YAMLs
      let projectTeam;
      try {
        projectTeam = readTeamYaml(TEAM_YAML);
      } catch {
        // Ignore parse errors during delete
      }

      let globalTeam;
      try {
        globalTeam = readTeamYaml(GLOBAL_TEAM_YAML);
      } catch {
        // Ignore parse errors during delete — proceed with detected platforms
      }

      const skipConfirm = opts.yes ?? globals().yes;
      const configDir = path.join(os.homedir(), ".teamrc");
      const projectStateDir = ".teamrc";

      // Determine deletion scope
      type DeleteScope = "project" | "global" | "all";
      let deleteScope: DeleteScope;

      if (opts.scope) {
        deleteScope = opts.scope as DeleteScope;
      } else if (skipConfirm) {
        deleteScope = "all";
      } else if (projectTeam) {
        requireTTY("--yes");

        const scopeOptions: { value: DeleteScope; label: string; hint: string }[] = [
          { value: "project", label: "Project team", hint: "Remove .teamrc.yaml and project agent files" },
        ];
        if (globalTeam) {
          scopeOptions.push({ value: "global", label: "Global team", hint: "Remove ~/.teamrc/team.yaml and global agent files" });
        }
        scopeOptions.push({ value: "all", label: "Everything", hint: "Remove all teamrc config, agents, and token from this machine" });

        const selected = await p.select({
          message: "What would you like to delete?",
          options: scopeOptions,
        });
        handleCancel(selected);
        deleteScope = selected as DeleteScope;
      } else {
        deleteScope = "all";
      }

      // Build deletion plan based on scope
      const planLines: string[] = [];
      let platforms: string[];

      if (deleteScope === "project") {
        platforms = projectTeam?.platforms ?? detectPlatforms();
        for (const pl of platforms) {
          planLines.push(`Remove ${pl} project agents and skills`);
        }
        if (fs.existsSync(TEAM_YAML)) planLines.push(`Delete ${TEAM_YAML}`);
        if (fs.existsSync(projectStateDir)) planLines.push(`Delete ${projectStateDir}/`);
      } else if (deleteScope === "global") {
        platforms = globalTeam?.platforms ?? detectPlatforms();
        for (const pl of platforms) {
          planLines.push(`Remove ${pl} global agents and skills`);
        }
        if (fs.existsSync(GLOBAL_TEAM_YAML)) planLines.push(`Delete ${GLOBAL_TEAM_YAML}`);
      } else {
        const allPlatforms = new Set<string>([
          ...(projectTeam?.platforms ?? []),
          ...(globalTeam?.platforms ?? detectPlatforms()),
        ]);
        platforms = [...allPlatforms];
        for (const pl of platforms) {
          planLines.push(`Remove ${pl} agents and skills`);
        }
        if (fs.existsSync(configDir)) planLines.push(`Delete ${configDir}`);
        if (fs.existsSync(TEAM_YAML)) planLines.push(`Delete ${TEAM_YAML}`);
        if (fs.existsSync(projectStateDir)) planLines.push(`Delete ${projectStateDir}/`);
      }

      if (planLines.length > 0) {
        p.log.info("Will delete:\n" + planLines.map((a) => `  ${a}`).join("\n"));
      }

      // Confirmation
      if (!skipConfirm) {
        if (deleteScope === "all") {
          const teamName = projectTeam?.name ?? globalTeam?.name ?? null;
          if (teamName) {
            requireTTY("--yes");
            const confirmation = await p.text({
              message: `Type "${teamName}" to confirm deletion:`,
              validate: (value) => {
                if (value !== teamName) return `Please type "${teamName}" to confirm.`;
              },
            });
            handleCancel(confirmation);
          } else {
            requireTTY("--yes");
            const shouldDelete = await p.confirm({
              message: "Remove teamrc from this machine?",
              initialValue: false,
            });
            handleCancel(shouldDelete);
            if (!shouldDelete) { p.cancel("Cancelled."); return; }
          }
        } else {
          requireTTY("--yes");
          const scopeLabel = deleteScope === "project" ? "project team" : "global team";
          const shouldDelete = await p.confirm({
            message: `Remove ${scopeLabel}?`,
            initialValue: false,
          });
          handleCancel(shouldDelete);
          if (!shouldDelete) { p.cancel("Cancelled."); return; }
        }
      }

      // Load keypair BEFORE deleting config (needed for relay disconnect)
      let client: TeamrcClient | null = null;
      try {
        const kp = loadKeypair();
        if (kp) {
          const token = toToken(kp.publicKey);
          const relay = projectTeam?.relay ?? globalTeam?.relay;
          const relayUrl = getRelayUrl(undefined, relay);
          client = new TeamrcClient(relayUrl, kp.privateKey, token);
        }
      } catch {
        // Can't load keypair — skip relay disconnect
      }

      const s = p.spinner();
      s.start("Removing...");

      const actionLines: string[] = [];

      // Disconnect from relay (scoped to match deletion scope)
      if (client) {
        try {
          if (deleteScope === "project") {
            const teamId = projectTeam?.teamId;
            if (teamId) {
              await client.disconnect(teamId);
              actionLines.push("Disconnected project team from relay");
            }
          } else if (deleteScope === "global") {
            const teamId = globalTeam?.teamId;
            if (teamId) {
              await client.disconnect(teamId);
              actionLines.push("Disconnected global team from relay");
            }
          } else {
            await client.disconnect();
            actionLines.push("Disconnected all teams from relay");
          }
        } catch {
          actionLines.push("Could not reach relay (local files still removed)");
        }
      }

      // Uninstall from each platform
      for (const pl of platforms) {
        const adapter = getAdapter(pl);
        const actions = adapter.uninstall();
        for (const action of actions) {
          actionLines.push(action);
        }
      }

      if (deleteScope === "project") {
        if (fs.existsSync(TEAM_YAML)) { fs.unlinkSync(TEAM_YAML); actionLines.push(`Deleted ${TEAM_YAML}`); }
        if (fs.existsSync(projectStateDir)) { fs.rmSync(projectStateDir, { recursive: true }); actionLines.push(`Deleted ${projectStateDir}/`); }
      } else if (deleteScope === "global") {
        if (fs.existsSync(GLOBAL_TEAM_YAML)) { fs.unlinkSync(GLOBAL_TEAM_YAML); actionLines.push(`Deleted ${GLOBAL_TEAM_YAML}`); }
      } else {
        if (fs.existsSync(configDir)) { fs.rmSync(configDir, { recursive: true }); actionLines.push(`Deleted ${configDir}`); }
        if (fs.existsSync(TEAM_YAML)) { fs.unlinkSync(TEAM_YAML); actionLines.push(`Deleted ${TEAM_YAML}`); }
        if (fs.existsSync(projectStateDir)) { fs.rmSync(projectStateDir, { recursive: true }); actionLines.push(`Deleted ${projectStateDir}/`); }
      }

      s.stop("Removed.");

      if (actionLines.length > 0 && globals().verbose) {
        p.log.info(actionLines.map((a) => `  ${a}`).join("\n"));
      }

      if (deleteScope === "project") {
        p.outro("Project team removed. Global config unchanged.");
      } else if (deleteScope === "global") {
        p.outro("Global team removed. Project team and token unchanged.");
      } else {
        p.outro(`Done. Run \`${cliCmd("init")}\` or \`${cliCmd("join")}\` to set up again.`);
      }
    });
}
