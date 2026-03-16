import * as fs from "node:fs";
import type { Command } from "commander";
import * as p from "@clack/prompts";
import { loadKeypair, toToken } from "../auth.js";
import { TeamrcClient } from "../client.js";
import { loadConfig, detectPlatforms, getRelayUrl } from "../config.js";
import { getAdapter, slugify, collectTeamSkillIds } from "../adapters/base.js";
import { readTeamYaml, TEAM_YAML, GLOBAL_TEAM_YAML } from "../team-yaml.js";
import {
  globals,
  requireTTY,
  handleCancel,
} from "../utils.js";

export function registerDelete(program: Command): void {
  program
    .command("delete")
    .description("Remove teamrc from this machine")
    .option("-y, --yes", "Skip confirmation prompt (requires --scope)")
    .option("--scope <scope>", "Deletion scope: project or global")
    .action(async (opts: { yes?: boolean; scope?: string }) => {
      p.intro("teamrc");

      const config = loadConfig();
      if (!config) {
        p.log.info("teamrc is not initialized. Nothing to remove.");
        p.outro("Done.");
        return;
      }

      // Validate --scope if provided
      const validScopes = ["project", "global"];
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
        // Ignore parse errors during delete  --  proceed with detected platforms
      }

      const skipConfirm = opts.yes ?? globals().yes;
      const projectStateDir = ".teamrc";

      // Determine deletion scope
      type DeleteScope = "project" | "global";
      let deleteScope: DeleteScope;

      if (opts.scope) {
        deleteScope = opts.scope as DeleteScope;
      } else if (skipConfirm) {
        p.log.error("--scope is required when using --yes. Valid options: project, global");
        process.exit(1);
      } else {
        requireTTY("--yes --scope <scope>");

        const scopeOptions: { value: DeleteScope; label: string; hint: string }[] = [];
        if (projectTeam) {
          scopeOptions.push({ value: "project", label: "Project team", hint: "Remove .teamrc.yaml and project agent files" });
        }
        if (globalTeam) {
          scopeOptions.push({ value: "global", label: "Global team", hint: "Remove ~/.teamrc/team.yaml and global agent files" });
        }

        if (scopeOptions.length === 0) {
          p.log.info("No project or global team found. Nothing to remove.");
          p.outro("Done.");
          return;
        }

        if (scopeOptions.length === 1) {
          deleteScope = scopeOptions[0].value;
        } else {
          const selected = await p.select({
            message: "What would you like to delete?",
            options: scopeOptions,
          });
          handleCancel(selected);
          deleteScope = selected as DeleteScope;
        }
      }

      // Build deletion plan based on scope
      // Merge explicit platforms with scope-aware detection so we clean up
      // everything installed (e.g. openclaw detected via ~/.openclaw for global)
      const planLines: string[] = [];
      let platforms: string[];

      if (deleteScope === "project") {
        platforms = [...new Set([...(projectTeam?.platforms ?? []), ...detectPlatforms("project")])];
        for (const pl of platforms) {
          planLines.push(`Remove ${pl} project agents and skills`);
        }
        if (fs.existsSync(TEAM_YAML)) planLines.push(`Delete ${TEAM_YAML}`);
        if (fs.existsSync(projectStateDir)) planLines.push(`Delete ${projectStateDir}/`);
      } else {
        platforms = [...new Set([...(globalTeam?.platforms ?? []), ...detectPlatforms("global")])];
        for (const pl of platforms) {
          planLines.push(`Remove ${pl} global agents and skills`);
        }
        if (fs.existsSync(GLOBAL_TEAM_YAML)) planLines.push(`Delete ${GLOBAL_TEAM_YAML}`);
      }

      if (planLines.length > 0) {
        p.log.info("Will delete:\n" + planLines.map((a) => `  ${a}`).join("\n"));
      }

      // Confirmation
      if (!skipConfirm) {
        requireTTY("--yes");
        const scopeLabel = deleteScope === "project" ? "project team" : "global team";
        const shouldDelete = await p.confirm({
          message: `Remove ${scopeLabel}?`,
          initialValue: false,
        });
        handleCancel(shouldDelete);
        if (!shouldDelete) { p.cancel("Cancelled."); return; }
      }

      // Load keypair BEFORE deleting config (needed for relay disconnect)
      let kp: { privateKey: Uint8Array; publicKey: Uint8Array } | null = null;
      try {
        kp = loadKeypair();
      } catch {
        // Can't load keypair  --  skip relay disconnect
      }

      const s = p.spinner();
      s.start("Removing...");

      const actionLines: string[] = [];

      // Disconnect from relay (scoped to match deletion scope)
      if (kp) {
        const token = toToken(kp.publicKey);
        const scopedTeam = deleteScope === "project" ? projectTeam : globalTeam;
        const relay = scopedTeam?.relay;
        const relayUrl = getRelayUrl(undefined, relay);
        try {
          if (deleteScope === "project") {
            const teamId = projectTeam?.teamId;
            if (teamId) {
              const client = new TeamrcClient(relayUrl, kp.privateKey, token, teamId);
              await client.disconnect(teamId);
              actionLines.push("Disconnected project team from relay");
            }
          } else {
            const teamId = globalTeam?.teamId;
            if (teamId) {
              const client = new TeamrcClient(relayUrl, kp.privateKey, token, teamId);
              await client.disconnect(teamId);
              actionLines.push("Disconnected global team from relay");
            }
          }
        } catch {
          actionLines.push("Could not reach relay (local files still removed)");
        }
      }

      // Uninstall from each platform
      const uninstallScope = deleteScope;
      const selectedTeam = deleteScope === "project" ? projectTeam : globalTeam;
      const deleteTeamName = selectedTeam?.name;
      const deleteTeamSlug = deleteTeamName ? slugify(deleteTeamName) : undefined;
      const teamSkillIds = selectedTeam ? collectTeamSkillIds(selectedTeam) : undefined;
      for (const pl of platforms) {
        const adapter = getAdapter(pl, deleteTeamSlug);
        const actions = adapter.uninstall(uninstallScope, teamSkillIds);
        for (const action of actions) {
          actionLines.push(action);
        }
      }

      if (deleteScope === "project") {
        if (fs.existsSync(TEAM_YAML)) { fs.unlinkSync(TEAM_YAML); actionLines.push(`Deleted ${TEAM_YAML}`); }
        if (fs.existsSync(projectStateDir)) { fs.rmSync(projectStateDir, { recursive: true }); actionLines.push(`Deleted ${projectStateDir}/`); }
      } else {
        if (fs.existsSync(GLOBAL_TEAM_YAML)) { fs.unlinkSync(GLOBAL_TEAM_YAML); actionLines.push(`Deleted ${GLOBAL_TEAM_YAML}`); }
      }

      s.stop("Removed.");

      if (actionLines.length > 0 && globals().verbose) {
        p.log.info(actionLines.map((a) => `  ${a}`).join("\n"));
      }

      if (deleteScope === "project") {
        p.outro("Project team removed. Global config unchanged.");
      } else {
        p.outro("Global team removed. Project team and token unchanged.");
      }
    });
}
