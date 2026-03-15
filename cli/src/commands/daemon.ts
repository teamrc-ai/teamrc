import type { Command } from "commander";
import * as p from "@clack/prompts";
import {
  CLI_NAME,
  globals,
  cliCmd,
} from "../utils.js";
import { loadConfig } from "../config.js";
import { loadKeypair, toToken } from "../auth.js";
import { getAdapter, slugify } from "../adapters/base.js";
import { readTeamYaml, readLocalYaml, TEAM_YAML, GLOBAL_TEAM_YAML, LOCAL_YAML, GLOBAL_LOCAL_YAML } from "../team-yaml.js";
import { getRelayUrl, detectPlatforms } from "../config.js";
import type { TeamDefinition } from "../adapters/base.js";

export function registerDaemon(program: Command): void {
  program
    .command("daemon")
    .description("Start the knowledge sync daemon (WebSocket + REST fallback)")
    .option("--rest-only", "Force REST polling (no WebSocket)")
    .option("--poll-interval <seconds>", "REST poll interval in seconds", "120")
    .option("--experimental", "Enable experimental features (task sync)")
    .option("--auto-spawn", "Auto-spawn Claude Code agents for claimed tasks (requires --experimental)")
    .option("--spawn-timeout <seconds>", "Timeout for spawned agents in seconds", "600")
    .action(async (opts: { restOnly?: boolean; pollInterval: string; experimental?: boolean; autoSpawn?: boolean; spawnTimeout: string }) => {
      const pollSec = parseInt(opts.pollInterval, 10);
      if (isNaN(pollSec) || pollSec < 5) {
        p.log.error("--poll-interval must be at least 5 seconds.");
        process.exit(1);
      }

      if (opts.autoSpawn && !opts.experimental) {
        p.log.error("--auto-spawn requires --experimental.");
        process.exit(1);
      }



      const spawnTimeoutSec = parseInt(opts.spawnTimeout, 10);
      if (isNaN(spawnTimeoutSec) || spawnTimeoutSec < 30) {
        p.log.error("--spawn-timeout must be at least 30 seconds.");
        process.exit(1);
      }

      const config = loadConfig();
      if (!config) {
        p.log.error(`Not initialized. Run \`${cliCmd("init")}\` first.`);
        process.exit(1);
      }

      const kp = loadKeypair();
      if (!kp) {
        p.log.error(`No keypair found. Run \`${cliCmd("init")}\` first.`);
        process.exit(1);
      }

      // Detect available scopes
      let projectTeam: TeamDefinition | null = null;
      let globalTeam: TeamDefinition | null = null;
      try { projectTeam = readTeamYaml(TEAM_YAML); } catch { /* skip */ }
      try { globalTeam = readTeamYaml(GLOBAL_TEAM_YAML); } catch { /* skip */ }

      const hasProject = !!(projectTeam?.teamId);
      const hasGlobal = !!(globalTeam?.teamId);

      let scope: "project" | "global";
      let team: TeamDefinition;

      if (hasProject && hasGlobal) {
        const choice = await p.select({
          message: "Both project and global teams found. Which one should the daemon sync?",
          options: [
            { value: "project", label: `Project: ${projectTeam!.name}` },
            { value: "global", label: `Global: ${globalTeam!.name}` },
          ],
        });
        if (p.isCancel(choice)) {
          p.cancel("Cancelled.");
          process.exit(0);
        }
        scope = choice as "project" | "global";
        team = scope === "project" ? projectTeam! : globalTeam!;
      } else if (hasProject) {
        scope = "project";
        team = projectTeam!;
      } else if (hasGlobal) {
        scope = "global";
        team = globalTeam!;
      } else {
        p.log.error(`No team found. Run \`${cliCmd("init")}\` first.`);
        process.exit(1);
      }

      if (opts.autoSpawn && scope === "global") {
        p.log.error("--auto-spawn requires a project-scoped team. Tasks need a repo to work in.");
        process.exit(1);
      }

      const teamName = team.name || "team";
      const teamSlug = slugify(teamName);
      const teamId = team.teamId!;

      const relay = getRelayUrl(undefined, team.relay);
      const platforms = team.platforms ?? detectPlatforms(scope);
      const adapters = platforms.map((pl) => getAdapter(pl, teamSlug));
      const token = toToken(kp.publicKey);

      const modeLabel = opts.restOnly ? "REST polling" : "WebSocket + REST fallback";
      p.intro(`${CLI_NAME} daemon`);
      p.log.info([
        `Team: "${teamName}" (${teamId})`,
        `Scope: ${scope}`,
        `Platforms: ${platforms.join(", ")}`,
        `Mode: ${modeLabel}`,
        `Poll interval: ${pollSec}s`,
        opts.experimental
          ? `Experimental: task sync enabled`
          : `Experimental: off (use --experimental to enable task sync)`,
        ...(opts.autoSpawn ? [`Auto-spawn: enabled (timeout ${spawnTimeoutSec}s)`] : []),
      ].join("\n"));

      const localConfig = readLocalYaml(scope === "global" ? GLOBAL_LOCAL_YAML : LOCAL_YAML);

      const { startKnowledgeDaemon } = await import("../daemon.js");
      const daemon = startKnowledgeDaemon({
        relayUrl: relay,
        privateKey: kp.privateKey,
        token,
        teamId,
        teamSlug,
        scope,
        adapters,
        platforms,
        fallbackPollInterval: pollSec * 1000,
        restOnly: opts.restOnly,
        activeMembers: localConfig.activeMembers,
        enableTasks: opts.experimental,
        autoSpawn: opts.autoSpawn,
        spawnTimeoutMs: spawnTimeoutSec * 1000,
      });

      // Keep the process alive until signal
      await new Promise<void>((resolve) => {
        const shutdown = () => {
          daemon.stop();
          p.outro("Daemon stopped.");
          resolve();
        };
        process.on("SIGINT", shutdown);
        process.on("SIGTERM", shutdown);
      });
    });
}
