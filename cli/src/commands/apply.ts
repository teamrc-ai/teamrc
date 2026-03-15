import type { Command } from "commander";
import * as p from "@clack/prompts";
import { getAdapter, slugify, filterActiveMembers } from "../adapters/base.js";
import { readTeamYaml, TEAM_YAML, GLOBAL_TEAM_YAML } from "../team-yaml.js";
import {
  requirePlatforms,
  selectScope,
  effectiveScope,
  cliCmd,
} from "../utils.js";

export function registerApply(program: Command): void {
  program
    .command("apply")
    .description("Re-apply team agents to local platform native format")
    .option("--platform <platform>", "Override platform detection")
    .option("--scope <scope>", "Team scope: project or global")
    .option("--global", "Install as global team")
    .action(async (opts: { platform?: string; scope?: string; global?: boolean }) => {
      p.intro("teamrc");

      const scope = await selectScope(opts);
      const platforms = await requirePlatforms(opts.platform, scope);
      let yamlPath = scope === "global" ? GLOBAL_TEAM_YAML : TEAM_YAML;
      let team;
      try {
        team = readTeamYaml(yamlPath);
      } catch (e) {
        p.log.error(`Failed to parse ${scope === "global" ? "global team.yaml" : ".teamrc.yaml"}: ${e instanceof Error ? e.message : e}`);
        process.exit(1);
      }
      if (!team && scope === "project") {
        // Fall back to global YAML when no project-level team exists
        try {
          team = readTeamYaml(GLOBAL_TEAM_YAML);
          if (team) yamlPath = GLOBAL_TEAM_YAML;
        } catch (e) {
          p.log.error(`Failed to parse global team.yaml: ${e instanceof Error ? e.message : e}`);
          process.exit(1);
        }
      }
      if (!team) {
        p.log.error(`No team YAML found. Run \`${cliCmd("init")}\` or \`${cliCmd("import <platform>")}\` first.`);
        process.exit(1);
      }

      const s = p.spinner();
      s.start(`Applying "${team.name}" to ${platforms.length} platform(s)...`);

      const filtered = filterActiveMembers(team);
      const appliedLines: string[] = [];
      for (const pl of platforms) {
        const adapter = getAdapter(pl, slugify(team.name));
        adapter.writeTeam(filtered, effectiveScope(pl, scope));
        const skillCount = team.skills?.length ?? 0;
        const parts = [`${team.members.length} agents`];
        if (skillCount > 0) parts.push(`${skillCount} skills`);
        appliedLines.push(`  ${pl.padEnd(14)} ${parts.join(", ")}`);
      }
      s.stop("Applied.");

      p.log.info(appliedLines.join("\n"));
      p.outro(`Done. ${team.members.length} agents across ${platforms.length} platform(s).`);
    });
}
