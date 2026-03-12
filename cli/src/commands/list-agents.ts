import type { Command } from "commander";
import * as p from "@clack/prompts";
import { listAgentCategories, loadAgent } from "../catalog.js";
import {
  globals,
  jsonOutput,
  cliCmd,
} from "../utils.js";

export function registerListAgents(program: Command): void {
  program
    .command("list-agents")
    .description("List available agents from the catalog")
    .option("--json", "Output as JSON")
    .action(async (opts: { json?: boolean }) => {
      const useJson = opts.json ?? globals().json;
      const categories = listAgentCategories();

      if (useJson) {
        const data = categories.map((cat) => ({
          category: cat.id,
          label: cat.label,
          agents: cat.agents.map((name) => {
            try {
              const a = loadAgent(name);
              return { name: a.name, role: a.role };
            } catch {
              return { name, role: "" };
            }
          }),
        }));
        jsonOutput(data);
        return;
      }

      p.intro("teamrc");

      let totalAgents = 0;
      for (const cat of categories) {
        const lines: string[] = [];
        for (const name of cat.agents) {
          try {
            const a = loadAgent(name);
            lines.push(`  ${a.name.padEnd(28)} ${a.role}`);
          } catch {
            lines.push(`  ${name}`);
          }
          totalAgents++;
        }
        p.log.message(`${cat.label}\n${lines.join("\n")}\n`);
      }

      p.outro(`${totalAgents} agents. Use \`${cliCmd("add-member <name>")}\` to add one to your team.`);
    });
}
