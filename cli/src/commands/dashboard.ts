import type { Command } from "commander";
import * as p from "@clack/prompts";
import { getRelayUrl } from "../config.js";
import { buildDashboardUrl, openBrowser } from "../browser.js";
import {
  requireRelayContext,
} from "../utils.js";

export function registerDashboard(program: Command): void {
  program
    .command("dashboard")
    .description("Open the current team in your browser")
    .option("--ttl <hours>", "Dashboard link expiry in hours", "24")
    .action(async (opts: { ttl: string }) => {
      p.intro("teamrc");

      const ctx = requireRelayContext();
      const ttlHours = parseInt(opts.ttl, 10);

      if (isNaN(ttlHours) || ttlHours < 1) {
        p.log.error("TTL must be a positive number of hours.");
        process.exit(1);
      }

      const s = p.spinner();
      try {
        s.start("Creating dashboard link...");
        const result = await ctx.client.createViewToken(ttlHours);
        const relayUrl = getRelayUrl(undefined, ctx.team.relay);
        const dashboardUrl = buildDashboardUrl(relayUrl, result.team_id, result.view_token);
        const opened = openBrowser(dashboardUrl);
        s.stop("Dashboard link ready.");

        p.note(
          `${dashboardUrl}\n\nTeam:    ${ctx.team.name || "your team"}\nExpires: ${ttlHours} hours`,
          "Dashboard",
        );

        if (opened) {
          p.outro("Opened the team dashboard in your browser.");
        } else {
          p.outro("Open the dashboard URL above in your browser.");
        }
      } catch (err) {
        s.error("Failed to open dashboard.");
        p.log.error((err as Error).message);
        process.exit(1);
      }
    });
}
