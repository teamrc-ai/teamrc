import type { Command } from "commander";
import * as p from "@clack/prompts";
import { toToken } from "../auth.js";
import { TeamrcClient, remoteTeamToDefinition } from "../client.js";
import { getRelayUrl } from "../config.js";
import { getAdapter } from "../adapters/base.js";
import { writeTeamYaml, validateTeamName, TEAM_YAML, GLOBAL_TEAM_YAML } from "../team-yaml.js";
import {
  requirePlatforms,
  requireKeypair,
  selectScope,
  effectiveScope,
} from "../utils.js";

export function registerClone(program: Command): void {
  program
    .command("clone")
    .description("Clone a team locally from an invite code or clone token without joining")
    .argument("<code>", "Invite code (trc_inv_...) or clone token (trc_cl_...)")
    .option("--relay <url>", "Relay server URL")
    .option("--platform <platform>", "Override platform detection")
    .option("--scope <scope>", "Team scope: project or global")
    .option("--global", "Clone as global team")
    .option("--name <name>", "Override team name")
    .action(async (code: string, opts: { relay?: string; platform?: string; scope?: string; global?: boolean; name?: string }) => {
      p.intro("teamrc");

      const scope = await selectScope(opts);
      const platforms = await requirePlatforms(opts.platform, scope);

      const kp = await requireKeypair();
      const token = toToken(kp.publicKey);
      const relayUrl = getRelayUrl(opts.relay);
      const client = new TeamrcClient(relayUrl, kp.privateKey, token);

      const s = p.spinner();
      try {
        s.start("Fetching team...");
        let previewTeam;
        if (code.startsWith("trc_cl_")) {
          previewTeam = await client.cloneByToken(code);
        } else {
          previewTeam = await client.previewByInvite(code);
        }
        const teamDef = remoteTeamToDefinition(previewTeam);
        s.stop(`Found "${teamDef.name}" (${teamDef.members.length} agents).`);

        if (opts.name) {
          validateTeamName(opts.name);
          teamDef.name = opts.name;
        }

        // Save clone token + relay for future pulls
        if (code.startsWith("trc_cl_")) {
          teamDef.cloneToken = code;
          teamDef.relay = relayUrl;
        }

        // Write canonical YAML
        writeTeamYaml(scope === "global" ? GLOBAL_TEAM_YAML : TEAM_YAML, teamDef);
        p.log.step(`Wrote ${scope === "global" ? GLOBAL_TEAM_YAML : TEAM_YAML}`);

        // Apply to each platform
        for (const pl of platforms) {
          const adapter = getAdapter(pl);
          adapter.writeTeam(teamDef, effectiveScope(pl, scope));
          p.log.step(`${pl} configured.`);
        }

        p.log.success(`Cloned "${teamDef.name}" (${teamDef.members.length} agents) locally.`);
        if (code.startsWith("trc_cl_")) {
          p.outro("Cloned. Run `teamrc pull` to fetch updates.");
        } else {
          p.outro("Cloned locally. To join and sync with the original team, use `teamrc join <invite-code>`.");
        }
      } catch (err) {
        s.error("Failed to clone team.");
        p.log.error((err as Error).message);
        process.exit(1);
      }
    });
}
