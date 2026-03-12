import type { Command } from "commander";
import * as p from "@clack/prompts";
import { loadConfig } from "../config.js";
import {
  requireTeamContext,
} from "../utils.js";

export function registerClaim(program: Command): void {
  program
    .command("claim")
    .description("Claim ownership of a team using its ownership token")
    .argument("<secret>", "Ownership token (trc_ocs_...)")
    .action(async (secret: string) => {
      p.intro("teamrc");

      if (!secret.startsWith("trc_ocs_")) {
        p.log.error("Invalid ownership token. Expected format: trc_ocs_...");
        process.exit(1);
      }

      const config = loadConfig();
      if (!config?.account?.email) {
        p.log.error("You must link your account first. Run `teamrc login`.");
        process.exit(1);
      }

      const ctx = requireTeamContext();
      const { client } = ctx;

      const s = p.spinner();
      try {
        s.start("Claiming ownership...");
        await client.claimOwnership(secret);
        s.stop("Ownership claimed.");

        p.log.info(`You are now the owner of "${ctx.team.name}".`);
        p.outro("Use `teamrc share` to make this team publicly cloneable.");
      } catch (err) {
        s.error("Failed to claim ownership.");
        p.log.error((err as Error).message);
        process.exit(1);
      }
    });
}
