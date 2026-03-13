import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";
import type { Command } from "commander";
import * as p from "@clack/prompts";
import { toToken } from "../auth.js";
import { TeamrcClient } from "../client.js";
import { getRelayUrl } from "../config.js";
import { getAdapter, slugify } from "../adapters/base.js";
import { templateToTeamDefinition } from "../catalog.js";
import { writeTeamYaml, readTeamYaml, validateTeamName, TEAM_YAML, GLOBAL_TEAM_YAML } from "../team-yaml.js";
import { sanitizeTeamDefinition } from "../client.js";
import { saveConfig } from "../config.js";
import { generateTeamName } from "../names.js";
import {
  globals,
  isNonInteractive,
  handleCancel,
  requirePlatforms,
  requireKeypair,
  selectScope,
  effectiveScope,
  selectTemplate,
  promptTeamName,
  deviceAuthFlow,
  cliCmd,
} from "../utils.js";

export function registerInit(program: Command): void {
  program
    .command("init")
    .description("Initialize teamrc: detect platform, create agents, connect to relay")
    .option("--relay <url>", "Relay server URL")
    .option("--platform <platform>", "Override platform detection")
    .option("--global", "Install as global team (all projects)")
    .option("--name <name>", "Team name")
    .option("--team <id>", "Team template (fullstack, backend, frontend, security, devops, custom, ...)")
    .option("--no-knowledge", "Skip creating the team knowledge file")
    .option("--local", "Create team locally without connecting to relay")
    .action(async (opts: { relay?: string; platform?: string; global?: boolean; name?: string; team?: string; knowledge?: boolean; local?: boolean }) => {
      p.intro("teamrc");

      const scope = await selectScope(opts);
      const platforms = await requirePlatforms(opts.platform, scope);

      // Guard: refuse to re-init if a team already exists in this scope
      const yamlPath = scope === "global" ? GLOBAL_TEAM_YAML : TEAM_YAML;
      let existingYaml;
      try {
        existingYaml = readTeamYaml(yamlPath);
      } catch {
        // Corrupt YAML is treated as not existing — init will overwrite it
      }
      if (existingYaml) {
        p.log.error(`Already initialized: "${existingYaml.name}" (${yamlPath}).`);
        p.log.info(`To add platforms, run: ${cliCmd("apply --platform <platforms>")}`);
        p.log.info(`To start over, run: ${cliCmd("delete")}`);
        process.exit(1);
      }

      const kp = await requireKeypair();
      const token = toToken(kp.publicKey);
      const relayUrl = getRelayUrl(opts.relay);

      // If there's an existing YAML without a teamId (e.g. from clone), adopt it.
      // For global scope, also check the project-level YAML in the current directory.
      if (!existingYaml && scope === "global") {
        try {
          const projectYaml = readTeamYaml(TEAM_YAML);
          if (projectYaml && !projectYaml.teamId && !isNonInteractive()) {
            const useProject = await p.confirm({
              message: `Found .teamrc.yaml in this directory ("${projectYaml.name}"). Use it for your global team?`,
              initialValue: true,
            });
            if (!p.isCancel(useProject) && useProject) {
              existingYaml = projectYaml;
            }
          }
        } catch {
          // Ignore parse errors for project YAML when targeting global
        }
      }

      let team;
      if (existingYaml && !existingYaml.teamId) {
        if (opts.name) {
          validateTeamName(opts.name);
          existingYaml.name = opts.name;
        }
        validateTeamName(existingYaml.name);
        // Strip clone token — this will be a new team
        delete existingYaml.cloneToken;
        // Sanitize: cap lengths, strip frontmatter injection, drop source-body skills
        team = sanitizeTeamDefinition(existingYaml);
        const memberNames = team.members.map((m) => m.name).join(", ");
        p.log.info(`Found existing team "${team.name}" (${team.members.length} agents: ${memberNames}).`);
      } else {
        // Select a team template
        const template = await selectTemplate(opts.team);
        // Generate a unique default name with Heroku-style suffix
        const baseName = template.id === "custom" ? "my-team" : template.teamName;
        const defaultName = opts.name ?? generateTeamName(baseName);
        const teamName = await promptTeamName(defaultName);
        team = templateToTeamDefinition(template, teamName);

        if (template.id !== "custom") {
          const memberNames = template.members.map((m) => m.name).join(", ");
          p.log.info(`${template.members.length} agents: ${memberNames}`);
        }
      }

      // Determine whether to connect to relay
      const firstAdapter = getAdapter(platforms[0], slugify(team.name));
      let useRelay: boolean;
      if (opts.local) {
        useRelay = false;
      } else if (opts.relay || isNonInteractive()) {
        useRelay = true;
      } else {
        p.log.message(
          `teamrc.ai lets you pull this team onto other machines\n` +
          `and share it with teammates. Your agent names, roles,\n` +
          `and instructions will be stored on our server.\n\n` +
          `You can always connect later with ${cliCmd("push")}.`
        );
        const syncConfirm = await p.confirm({
          message: "Connect to teamrc.ai?",
          initialValue: true,
        });
        handleCancel(syncConfirm);
        useRelay = syncConfirm as boolean;
      }

      if (!useRelay) {
        // Local-only: write files without relay
        team.platforms = platforms;

        for (const pl of platforms) {
          const adapter = getAdapter(pl, slugify(team.name));
          adapter.writeTeam(team, effectiveScope(pl, scope));
        }
        p.log.step(`Applied to: ${platforms.join(", ")}`);

        if (opts.knowledge !== false) {
          if (!firstAdapter.readKnowledge()) {
            firstAdapter.writeKnowledge(`# Team Knowledge\n\nShared findings and decisions across team members.\n`);
          }
        }

        writeTeamYaml(yamlPath, team);
        p.log.step(`Wrote ${yamlPath}`);
        saveConfig({ token });

        // Ensure .teamrc/ is gitignored for project-level teams
        if (scope !== "global") {
          const gitignorePath = path.join(process.cwd(), ".gitignore");
          const teamrcIgnoreEntry = ".teamrc/";
          if (fs.existsSync(gitignorePath)) {
            const gitignoreContent = fs.readFileSync(gitignorePath, "utf-8");
            if (!gitignoreContent.split("\n").some((line) => line.trim() === teamrcIgnoreEntry)) {
              fs.appendFileSync(gitignorePath, `\n# teamrc sync state\n${teamrcIgnoreEntry}\n`);
            }
          } else {
            fs.writeFileSync(gitignorePath, `${teamrcIgnoreEntry}\n`);
          }
        }

        p.outro("Customize agents and skills in .teamrc.yaml, then run teamrc apply");
        return;
      }

      // Create team on relay first — don't write local files until relay succeeds
      const s = p.spinner();
      const client = new TeamrcClient(relayUrl, kp.privateKey, token);
      try {
        s.start("Creating team on relay...");
        const relayTeam = await client.createTeam(
          team.name,
          team.members.map((m) => ({ name: m.name, role: m.role, platform: platforms.join(","), ...(m.skills?.length ? { skills: m.skills } : {}) })),
          team.skills,
        );
        s.stop("Team created.");

        // Relay succeeded — now write local files
        team.teamId = relayTeam.id;
        team.platforms = platforms;
        team.relay = relayUrl;
        client.setTeamId(relayTeam.id);

        // Apply to each platform's native format
        const platformSummary: string[] = [];
        for (const pl of platforms) {
          const adapter = getAdapter(pl, slugify(team.name));
          adapter.writeTeam(team, effectiveScope(pl, scope));
          platformSummary.push(pl);
        }
        p.log.step(`Applied to: ${platformSummary.join(", ")}`);

        // Create team knowledge file (unless --no-knowledge)
        if (opts.knowledge !== false) {
          if (!firstAdapter.readKnowledge()) {
            firstAdapter.writeKnowledge(`# Team Knowledge\n\nShared findings and decisions across team members.\n`);
          }

          // Push knowledge to relay so other machines can pull it
          const initKnowledge = firstAdapter.readKnowledge();
          if (initKnowledge) {
            await client.pushTeam(team, initKnowledge);
          }
        }

        // Write YAML
        writeTeamYaml(yamlPath, team);
        p.log.step(`Wrote ${yamlPath}`);
        saveConfig({ token });

        // Ensure .teamrc/ is gitignored for project-level teams
        if (scope !== "global") {
          const gitignorePath = path.join(process.cwd(), ".gitignore");
          const teamrcIgnoreEntry = ".teamrc/";
          if (fs.existsSync(gitignorePath)) {
            const gitignoreContent = fs.readFileSync(gitignorePath, "utf-8");
            if (!gitignoreContent.split("\n").some((line) => line.trim() === teamrcIgnoreEntry)) {
              fs.appendFileSync(gitignorePath, `\n# teamrc sync state\n${teamrcIgnoreEntry}\n`);
            }
          } else {
            fs.writeFileSync(gitignorePath, `${teamrcIgnoreEntry}\n`);
          }
        }

        // Show ownership token and offer to link account (auto-claims on login)
        if (relayTeam.owner_claim_secret) {
          const dim = (s: string) => `\x1b[2m${s}\x1b[0m`;
          const yellow = (s: string) => `\x1b[33m${s}\x1b[0m`;
          p.log.warn(
            `${yellow("Save this to claim ownership:")}  ${relayTeam.owner_claim_secret}\n` +
            `${dim(`Run \`${cliCmd("claim <token>")}\` anytime, or link your account now to claim automatically.`)}`,
          );

          if (!isNonInteractive()) {
            const shouldLink = await p.confirm({
              message: "Link your account? (claims ownership automatically)",
              initialValue: true,
            });
            if (!p.isCancel(shouldLink) && shouldLink) {
              const machineName = os.hostname();
              const success = await deviceAuthFlow(client, machineName, relayUrl);
              if (success) {
                try {
                  await client.claimOwnership(relayTeam.owner_claim_secret);
                  p.log.step("Ownership claimed.");
                } catch {
                  p.log.warn(`Account linked, but ownership claim failed. Run \`${cliCmd("claim <token>")}\` later.`);
                }
              }
            }
          }
        } else {
          // No claim secret means the server auto-assigned ownership (token is linked)
          p.log.step("You own this team.");
        }

        // Create invite for sharing
        let inviteInfo: { invite_code: string; expires_at: string } | null = null;
        try {
          inviteInfo = await client.createInvite(24);
        } catch {
          // invite creation may not be available
        }

        if (inviteInfo) {
          p.note(
            `npx @teamrc/cli join ${inviteInfo.invite_code}\nInvite code expires in 24 hours.`,
            "Share with teammates",
          );
        }

        p.log.info(`Tip: Run \`${cliCmd("dashboard")}\` to open this team in your browser.`);
        p.outro("Customize agents and skills in .teamrc.yaml, then run teamrc apply");
      } catch (err) {
        s.error("Failed to create team on relay.");
        p.log.warn(`Relay error: ${(err as Error).message}`);
        p.log.info("No local files were created.");
        p.outro(`Check your relay connection and re-run \`${cliCmd("init")}\`.`);
      }
    });
}
