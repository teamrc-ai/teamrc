import type { Command } from "commander";
import * as p from "@clack/prompts";
import { loadConfig, getRelayUrl } from "../config.js";
import {
  requireRelayContext,
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

      const ctx = requireRelayContext();
      const { client } = ctx;
      const teamName = ctx.team.name;
      const visibility = opts.off ? "private" : "public";

      const s = p.spinner();
      try {
        s.start(opts.off ? "Making team private..." : "Making team public...");
        const result = await client.setVisibility(visibility);
        s.stop(opts.off ? "Team is now private." : "Team is now public.");

        if (opts.off) {
          p.note(
            `Your team is no longer publicly visible or clonable.`,
            `Team "${teamName}" is now private`,
          );
          p.outro(`Use \`${cliCmd("share")}\` to make it public again.`);
        } else if (result.clone_token) {
          const baseUrl = getRelayUrl(undefined, ctx.team.relay).replace(/\/api\/?$/, "");
          const shareUrl = `${baseUrl}/t/${result.clone_token}`;

          p.note(
            [
              `Share URL:    ${shareUrl}`,
              `Clone cmd:    npx @teamrc/cli clone ${result.clone_token}`,
            ].join("\n"),
            `Team "${teamName}" is now public and clonable`,
          );

          p.outro(`Use \`${cliCmd("share --off")}\` to disable.`);
        }
      } catch (err) {
        s.error("Failed to update visibility.");
        p.log.error((err as Error).message);
        process.exit(1);
      }
    });
}
