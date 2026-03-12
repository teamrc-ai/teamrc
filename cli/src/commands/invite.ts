import type { Command } from "commander";
import * as p from "@clack/prompts";
import {
  requireTeamContext,
} from "../utils.js";

export function registerInvite(program: Command): void {
  program
    .command("invite")
    .description("Create an invite code for the current team")
    .option("--ttl <hours>", "Invite expiry in hours", "24")
    .action(async (opts: { ttl: string }) => {
      p.intro("teamrc");

      const ctx = requireTeamContext();
      const { client } = ctx;
      const ttlHours = parseInt(opts.ttl, 10);

      if (isNaN(ttlHours) || ttlHours < 1) {
        p.log.error("TTL must be a positive number of hours.");
        process.exit(1);
      }

      const s = p.spinner();
      try {
        s.start("Creating invite...");
        const result = await client.createInvite(ttlHours);
        s.stop("Invite created.");

        const teamName = ctx.team.name || "your team";
        p.note(
          `npx @teamrc/cli join ${result.invite_code}\n\nTeam:    ${teamName}\nExpires: ${ttlHours} hours`,
          "Invite",
        );

        p.outro("Share this command with your teammates. For your own browser session, use `teamrc dashboard`.");
      } catch (err) {
        s.error("Failed to create invite.");
        p.log.error((err as Error).message);
        process.exit(1);
      }
    });
}
