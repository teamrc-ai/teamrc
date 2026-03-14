import type { Command } from "commander";
import * as p from "@clack/prompts";
import {
  requireRelayContext,
  CLI_NAME,
} from "../utils.js";
import { loadKeypair, toToken } from "../auth.js";
import { slugify } from "../adapters/base.js";

export function registerDaemon(program: Command): void {
  program
    .command("daemon")
    .description("Start the knowledge sync daemon (WebSocket + REST fallback)")
    .option("--scope <scope>", "Scope: project or global", "project")
    .option("--rest-only", "Force REST polling (no WebSocket)")
    .option("--poll-interval <seconds>", "REST poll interval in seconds", "120")
    .action(async (opts: { scope: string; restOnly?: boolean; pollInterval: string }) => {
      const pollSec = parseInt(opts.pollInterval, 10);
      if (isNaN(pollSec) || pollSec < 5) {
        p.log.error("--poll-interval must be at least 5 seconds.");
        process.exit(1);
      }

      if (opts.scope !== "project" && opts.scope !== "global") {
        p.log.error("--scope must be 'project' or 'global'.");
        process.exit(1);
      }

      const ctx = requireRelayContext();
      const { client } = ctx;
      const kp = loadKeypair();
      if (!kp) {
        p.log.error(`No keypair found. Run \`${CLI_NAME} init\` first.`);
        process.exit(1);
      }

      const teamName = ctx.team.name || "team";
      const teamSlug = slugify(teamName);
      const teamId = ctx.team.teamId;
      if (!teamId) {
        p.log.error("No team ID found. Push your team first.");
        process.exit(1);
      }

      const relay = ctx.team.relay;
      if (!relay) {
        p.log.error("No relay URL configured.");
        process.exit(1);
      }

      const modeLabel = opts.restOnly ? "REST polling" : "WebSocket + REST fallback";
      p.intro(`${CLI_NAME} daemon`);
      p.log.info([
        `Team: "${teamName}" (${teamId})`,
        `Platforms: ${ctx.platforms.join(", ")}`,
        `Mode: ${modeLabel}`,
        `Poll interval: ${pollSec}s`,
      ].join("\n"));

      const { startKnowledgeDaemon } = await import("../daemon.js");
      const daemon = startKnowledgeDaemon({
        relayUrl: relay,
        privateKey: kp.privateKey,
        token: toToken(kp.publicKey),
        teamId,
        teamSlug,
        scope: opts.scope as "project" | "global",
        adapters: ctx.adapters,
        platforms: ctx.platforms,
        fallbackPollInterval: pollSec * 1000,
        restOnly: opts.restOnly,
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
