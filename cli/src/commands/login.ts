import * as os from "node:os";
import type { Command } from "commander";
import * as p from "@clack/prompts";
import { toToken } from "../auth.js";
import { TeamrcClient } from "../client.js";
import { getRelayUrl } from "../config.js";
import {
  requireKeypair,
  deviceAuthFlow,
} from "../utils.js";

export function registerLogin(program: Command): void {
  program
    .command("login")
    .description("Link this machine to your teamrc account")
    .option("--name <machine-name>", "Machine name (defaults to hostname)")
    .action(async (opts: { name?: string }) => {
      p.intro("teamrc");

      const kp = await requireKeypair();
      const token = toToken(kp.publicKey);
      const relayUrl = getRelayUrl();
      const client = new TeamrcClient(relayUrl, kp.privateKey, token);
      const machineName = opts.name ?? os.hostname();

      const success = await deviceAuthFlow(client, machineName, relayUrl);
      if (success) {
        p.outro("Account linked.");
      } else {
        p.outro("Login failed. Run `teamrc login` to try again.");
        process.exit(1);
      }
    });
}
