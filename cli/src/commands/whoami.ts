import type { Command } from "commander";
import * as p from "@clack/prompts";
import { loadConfig, getRelayUrl } from "../config.js";
import { readTeamYaml, TEAM_YAML, GLOBAL_TEAM_YAML } from "../team-yaml.js";
import {
  globals,
  jsonOutput,
} from "../utils.js";

export function registerWhoami(program: Command): void {
  program
    .command("whoami")
    .description("Show current identity and configuration")
    .option("--json", "Output as JSON")
    .action((opts: { json?: boolean }) => {
      const useJson = opts.json ?? globals().json;
      const config = loadConfig();

      if (!config) {
        if (useJson) {
          jsonOutput({ error: "not initialized" });
        } else {
          p.log.warn("teamrc is not initialized.");
        }
        return;
      }

      let whoamiYaml;
      try {
        whoamiYaml = readTeamYaml(TEAM_YAML) ?? readTeamYaml(GLOBAL_TEAM_YAML);
      } catch (e) {
        p.log.error(`Failed to parse team YAML: ${e instanceof Error ? e.message : e}`);
        process.exit(1);
      }
      const whoamiTeamId = whoamiYaml?.teamId ?? "none";
      const whoamiPlatform = whoamiYaml?.platforms?.join(",") ?? "none";
      const whoamiRelayUrl = getRelayUrl(undefined, whoamiYaml?.relay);

      if (useJson) {
        jsonOutput({
          token: config.token.slice(0, 16) + "...",
          machine: config.machineName ?? "unknown",
          account: config.account?.email ?? "not linked",
          teamId: whoamiTeamId,
          relay: whoamiRelayUrl,
          platform: whoamiPlatform,
        });
        return;
      }

      p.log.info([
        `Token:    ${config.token.slice(0, 16)}...`,
        `Machine:  ${config.machineName ?? "unknown"}`,
        `Account:  ${config.account?.email ?? "not linked"}`,
        `Team ID:  ${whoamiTeamId}`,
        `Relay:    ${whoamiRelayUrl}`,
        `Platform: ${whoamiPlatform}`,
      ].join("\n"));
    });
}
