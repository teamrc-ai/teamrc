import * as os from "node:os";
import type { Command } from "commander";
import * as p from "@clack/prompts";
import { toToken } from "../auth.js";
import { TeamrcClient, remoteTeamToDefinition } from "../client.js";
import { getRelayUrl, saveConfig } from "../config.js";
import { getAdapter, slugify, filterActiveMembers } from "../adapters/base.js";
import { writeTeamYaml, TEAM_YAML, GLOBAL_TEAM_YAML, mergeKnowledge, pruneKnowledge, MAX_KNOWLEDGE_SIZE } from "../team-yaml.js";
import {
  isNonInteractive,
  handleCancel,
  requirePlatforms,
  requireKeypair,
  selectScope,
  effectiveScope,
  deviceAuthFlow,
  cliCmd,
} from "../utils.js";

export function registerJoin(program: Command): void {
  program
    .command("join")
    .description("Join an existing team and create local agents")
    .argument("<invite-code>", "Team invitation code")
    .option("--relay <url>", "Relay server URL")
    .option("--platform <platform>", "Override platform detection")
    .option("--global", "Join as global team")
    .option("--no-knowledge", "Skip creating the team knowledge file")
    .option("--members <names>", "Comma-separated active members for this project")
    .action(async (inviteCode: string, opts: { relay?: string; platform?: string; global?: boolean; knowledge?: boolean; members?: string }) => {
      p.intro("teamrc");

      const scope = await selectScope(opts);
      const platforms = await requirePlatforms(opts.platform, scope);

      const kp = await requireKeypair();
      const token = toToken(kp.publicKey);
      const relayUrl = getRelayUrl(opts.relay);
      const client = new TeamrcClient(relayUrl, kp.privateKey, token);

      const s = p.spinner();
      try {
        s.start("Joining team...");
        const joinedTeam = await client.joinByInvite(inviteCode);
        s.stop(`Joined "${joinedTeam.name}" (${joinedTeam.members.length} members)`);

        const teamDef = remoteTeamToDefinition(joinedTeam);

        // Show members
        if (joinedTeam.members.length > 0) {
          const memberLines = joinedTeam.members.map(
            (m) => `  ${m.name.padEnd(14)} ${m.role}`,
          );
          p.log.info("Members:\n" + memberLines.join("\n"));
        }

        // Validate and set --members
        if (opts.members) {
          const names = opts.members.split(",").map((s) => s.trim()).filter(Boolean);
          const memberNames = teamDef.members.map((m) => m.name);
          for (const n of names) {
            if (!memberNames.includes(n)) {
              p.log.error(`"${n}" is not a team member. Members: ${memberNames.join(", ")}`);
              process.exit(1);
            }
          }
          teamDef.activeMembers = names;
        }

        // Apply to each platform
        const s2 = p.spinner();
        s2.start("Applying to detected platforms...");
        const filtered = filterActiveMembers(teamDef);
        const appliedLines: string[] = [];
        for (const pl of platforms) {
          const adapter = getAdapter(pl, slugify(teamDef.name));
          adapter.writeTeam(filtered, effectiveScope(pl, scope));
          const skillCount = filtered.skills?.length ?? 0;
          const detail = skillCount > 0
            ? `${filtered.members.length} agents, ${skillCount} skills`
            : `${filtered.members.length} agents`;
          appliedLines.push(`  ${pl.padEnd(14)} ${detail}`);
        }
        s2.stop("Applied.");
        p.log.info(appliedLines.join("\n"));

        // Create team knowledge file and merge from relay (unless --no-knowledge)
        if (opts.knowledge !== false) {
          const joinAdapter = getAdapter(platforms[0], slugify(teamDef.name));
          if (!joinAdapter.readKnowledge()) {
            joinAdapter.writeKnowledge(`# Team Knowledge\n\nShared findings and decisions across team members.\n`);
          }

          if (joinedTeam.knowledge) {
            const localKnowledge = joinAdapter.readKnowledge();
            let merged = mergeKnowledge(joinedTeam.knowledge, localKnowledge);
            merged = pruneKnowledge(merged);
            if (merged.length <= MAX_KNOWLEDGE_SIZE) {
              joinAdapter.writeKnowledge(merged);
            } else {
              p.log.warn("Remote knowledge exceeds maximum size, skipping merge.");
            }
          }
        }

        if (scope === "global") {
          teamDef.teamId = joinedTeam.id;
          teamDef.platforms = platforms;
          teamDef.relay = relayUrl;
          writeTeamYaml(GLOBAL_TEAM_YAML, teamDef);
          p.log.step(`Wrote ${GLOBAL_TEAM_YAML}`);
          saveConfig({ token });
        } else {
          teamDef.teamId = joinedTeam.id;
          teamDef.platforms = platforms;
          teamDef.relay = relayUrl;
          writeTeamYaml(TEAM_YAML, teamDef);
          p.log.step(`Wrote ${TEAM_YAML}`);
          saveConfig({ token });
        }

        if (!isNonInteractive()) {
          const shouldLink = await p.confirm({
            message: "Link your account? (optional, for recovery & dashboard)",
            initialValue: false,
          });
          handleCancel(shouldLink);
          if (shouldLink) {
            const machineName = os.hostname();
            await deviceAuthFlow(client, machineName, relayUrl);
          } else {
            p.log.info(`Tip: Run \`${cliCmd("login")}\` anytime to link your account.`);
          }
        }

        p.log.info(`Tip: Run \`${cliCmd("dashboard")}\` to manage this team in your browser.`);
        p.outro("Next: Run teamrc daemon to start live sync");
      } catch (err) {
        s.error("Failed to join team.");
        p.log.error((err as Error).message);
        process.exit(1);
      }
    });
}
