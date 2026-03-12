import type { Command } from "commander";
import * as p from "@clack/prompts";
import { remoteTeamToDefinition } from "../client.js";
import { writeTeamYaml, validateTeamName, TEAM_YAML, GLOBAL_TEAM_YAML } from "../team-yaml.js";
import {
  requireTeamContext,
} from "../utils.js";

export function registerExport(program: Command): void {
  program
    .command("export")
    .description("Export team from relay to .teamrc.yaml")
    .action(async () => {
      p.intro("teamrc");

      const ctx = requireTeamContext();
      const { client } = ctx;
      const yamlPath = ctx.scope === "global" ? GLOBAL_TEAM_YAML : TEAM_YAML;

      const s = p.spinner();
      try {
        s.start("Fetching team from relay...");
        const remoteTeam = await client.getTeam();
        validateTeamName(remoteTeam.name);
        const team = remoteTeamToDefinition(remoteTeam);
        writeTeamYaml(yamlPath, team);
        s.stop(`Exported "${team.name}" (${team.members.length} agents) to ${yamlPath}.`);
        p.outro("Done.");
      } catch (err) {
        s.error("Failed to fetch team from relay.");
        p.log.error((err as Error).message);
        process.exit(1);
      }
    });
}
