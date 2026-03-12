import type { Command } from "commander";
import * as p from "@clack/prompts";
import { loadConfig } from "../config.js";
import {
  requireTeamContext,
  cliCmd,
} from "../utils.js";

export function registerShare(program: Command): void {
  program
    .command("share")
    .description("Make your team publicly cloneable (requires linked account)")
    .option("--off", "Make team private (disable cloning)")
    .action(async (opts: { off?: boolean }) => {
      p.intro("teamrc");

      const config = loadConfig();
      if (!config?.account?.email) {
        p.log.error(`${cliCmd("share")} requires a linked account. Run \`${cliCmd("login")}\` first.`);
        process.exit(1);
      }

      const ctx = requireTeamContext();
      const { client } = ctx;
      const visibility = opts.off ? "private" : "public";

      const s = p.spinner();
      try {
        s.start(opts.off ? "Making team private..." : "Making team public...");
        const result = await client.setVisibility(visibility);
        s.stop(opts.off ? "Team is now private." : "Team is now public.");

        if (result.clone_token) {
          p.note(
            `npx @teamrc/cli clone ${result.clone_token}\n\nAnyone with this command can clone your team definition.\nNo invite needed — read-only, no sync.`,
            "Clone command",
          );
        }

        p.outro(opts.off ? "Cloning disabled." : `Share the clone command above. Use \`${cliCmd("share --off")}\` to disable.`);
      } catch (err) {
        s.error("Failed to update visibility.");
        p.log.error((err as Error).message);
        process.exit(1);
      }
    });
}
