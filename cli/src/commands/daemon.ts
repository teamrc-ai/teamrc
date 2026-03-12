import type { Command } from "commander";
import * as p from "@clack/prompts";
import {
  requireTeamContext,
  CLI_NAME,
} from "../utils.js";

export function registerDaemon(program: Command): void {
  program
    .command("daemon")
    .description("Start the background sync daemon")
    .option("--poll-interval <ms>", "Poll interval in milliseconds", "120000")
    .action(async (opts: { pollInterval: string }) => {
      const pollMs = parseInt(opts.pollInterval, 10);
      if (isNaN(pollMs) || pollMs < 5000) {
        p.log.error("--poll-interval must be at least 5000ms.");
        process.exit(1);
      }

      const ctx = requireTeamContext();
      const { client } = ctx;

      p.intro(`${CLI_NAME} daemon`);
      p.log.info([
        `Watching "${ctx.team.name || "team"}" on ${ctx.platforms.join(", ")}`,
        `Poll interval: ${pollMs / 1000}s`,
      ].join("\n"));

      const { startDaemon } = await import("../daemon.js");
      const daemon = startDaemon({
        client,
        adapters: ctx.adapters,
        platforms: ctx.platforms,
        pollInterval: pollMs,
      });

      const shutdown = () => {
        daemon.stop();
        p.outro("Daemon stopped.");
        process.exit(0);
      };
      process.on("SIGINT", shutdown);
      process.on("SIGTERM", shutdown);
    });
}
