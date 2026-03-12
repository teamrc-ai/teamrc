import type { Command } from "commander";
import * as p from "@clack/prompts";
import { resolveTeam, listTeams } from "../catalog.js";
import {
  globals,
  jsonOutput,
  cliCmd,
} from "../utils.js";

export function registerListTemplates(program: Command): void {
  program
    .command("list-templates")
    .description("List available team templates from the catalog")
    .option("--json", "Output as JSON")
    .action(async (opts: { json?: boolean }) => {
      const useJson = opts.json ?? globals().json;
      const teamIds = listTeams();

      const teams = teamIds.map((id) => {
        const t = resolveTeam(id);
        return {
          id,
          label: t.label,
          description: t.description,
          agents: t.members.length,
          skills: t.skills.length,
          members: t.members.map((m) => m.name),
        };
      });

      if (useJson) {
        jsonOutput(teams);
        return;
      }

      p.intro("teamrc");
      p.log.info("Available team templates:\n");

      for (const t of teams) {
        const memberList = t.members.join(", ");
        p.log.message(
          `  ${t.id.padEnd(16)} ${t.label}\n` +
          `  ${"".padEnd(16)} ${t.description}\n` +
          `  ${"".padEnd(16)} ${t.agents} agents, ${t.skills} skills: ${memberList}\n`,
        );
      }

      p.outro(`${teams.length} templates. Use \`${cliCmd("init --team <name>")}\` to create a team.`);
    });
}
