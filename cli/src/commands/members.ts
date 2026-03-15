import type { Command } from "commander";
import * as p from "@clack/prompts";
import { getAdapter, slugify, filterActiveMembers } from "../adapters/base.js";
import { readTeamYaml, readLocalYaml, writeLocalYaml, TEAM_YAML, GLOBAL_TEAM_YAML, LOCAL_YAML, GLOBAL_LOCAL_YAML } from "../team-yaml.js";
import { detectPlatforms } from "../config.js";
import {
  isNonInteractive,
  handleCancel,
  selectScope,
  effectiveScope,
  cliCmd,
} from "../utils.js";

export function registerMembers(program: Command): void {
  program
    .command("members")
    .description("Set which agents are active in this project")
    .argument("[names...]", "Agent names (comma-separated or space-separated)")
    .option("--global", "Set for global team")
    .action(async (names: string[], opts: { global?: boolean }) => {
      p.intro("teamrc");

      const scope = opts.global ? "global" as const : "project" as const;
      const yamlPath = scope === "global" ? GLOBAL_TEAM_YAML : TEAM_YAML;
      const localPath = scope === "global" ? GLOBAL_LOCAL_YAML : LOCAL_YAML;

      let team;
      try {
        team = readTeamYaml(yamlPath);
      } catch (e) {
        p.log.error(`Failed to parse team YAML: ${e instanceof Error ? e.message : e}`);
        process.exit(1);
      }
      if (!team && scope === "project") {
        try {
          team = readTeamYaml(GLOBAL_TEAM_YAML);
        } catch { /* skip */ }
      }
      if (!team) {
        p.log.error(`No team found. Run \`${cliCmd("init")}\` first.`);
        process.exit(1);
      }

      const allNames = team.members.map((m) => m.name);
      const localConfig = readLocalYaml(localPath);
      const currentActive = localConfig.activeMembers ?? allNames;

      // Parse names — support both "a,b,c" and "a b c"
      let selected: string[];
      const flatNames = names.flatMap((n) => n.split(",")).map((s) => s.trim()).filter(Boolean);

      if (flatNames.length > 0) {
        // Validate all names
        for (const n of flatNames) {
          if (!allNames.includes(n)) {
            p.log.error(`"${n}" is not a team member. Members: ${allNames.join(", ")}`);
            process.exit(1);
          }
        }
        selected = flatNames;
      } else {
        // Interactive picker with current selection pre-checked
        if (isNonInteractive()) {
          p.log.error("Provide member names or run interactively.");
          process.exit(1);
        }

        const choices = await p.multiselect({
          message: "Which agents should be active in this project?",
          options: team.members.map((m) => ({
            value: m.name,
            label: m.name,
            hint: m.role,
          })),
          initialValues: currentActive,
          required: true,
        });
        handleCancel(choices);
        selected = choices as string[];
      }

      // If all members selected, clear activeMembers (default = all)
      const isAll = selected.length === allNames.length && allNames.every((n) => selected.includes(n));
      if (isAll) {
        writeLocalYaml(localPath, {});
      } else {
        writeLocalYaml(localPath, { activeMembers: selected });
      }

      // Re-apply to platforms
      const platforms = team.platforms ?? detectPlatforms(scope);
      const filtered = filterActiveMembers(team, isAll ? undefined : selected);
      for (const pl of platforms) {
        const adapter = getAdapter(pl, slugify(team.name));
        adapter.writeTeam(filtered, effectiveScope(pl, scope));
      }

      const label = isAll ? "all members" : selected.join(", ");
      p.log.step(`Active: ${label}`);
      p.log.step(`Applied to ${platforms.length} platform(s).`);
      p.outro("Done.");
    });
}
