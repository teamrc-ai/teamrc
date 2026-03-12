import type { Command } from "commander";
import * as p from "@clack/prompts";
import { getAdapter, VALID_PLATFORMS } from "../adapters/base.js";
import { writeTeamYaml, TEAM_YAML } from "../team-yaml.js";

export function registerImport(program: Command): void {
  program
    .command("import")
    .description("Import team from platform files into .teamrc.yaml")
    .argument("<platform>", "Platform to import from (claude-code, cursor, codex, gemini, openclaw)")
    .action(async (platform: string) => {
      p.intro("teamrc");

      if (!VALID_PLATFORMS.includes(platform as typeof VALID_PLATFORMS[number])) {
        p.log.error(`Unknown platform: ${platform}. Valid options: ${VALID_PLATFORMS.join(", ")}`);
        process.exit(1);
      }

      const adapter = getAdapter(platform);
      const team = adapter.readTeam();
      if (!team) {
        p.log.error(`Platform "${platform}" has no teamrc files to import.`);
        process.exit(1);
      }

      writeTeamYaml(TEAM_YAML, team);
      p.log.success(`Imported "${team.name}" (${team.members.length} agents) from ${platform}.`);
      p.log.step(`Wrote ${TEAM_YAML}`);
      p.outro("This is a local copy. Run `teamrc init` to create a synced team.");
    });
}
