import type { Command } from "commander";
import * as p from "@clack/prompts";
import { computeTeamHashes } from "../sync-hash.js";
import {
  globals,
  requireTeamContext,
  jsonOutput,
} from "../utils.js";

export function registerDiff(program: Command): void {
  program
    .command("diff")
    .description("Show differences between local agents and relay")
    .option("--json", "Output as JSON")
    .action(async (opts: { json?: boolean }) => {
      const useJson = opts.json ?? globals().json;
      const ctx = requireTeamContext();
      const { client } = ctx;
      const adapter = ctx.adapters[0];

      const s = p.spinner();
      try {
        if (!useJson) {
          p.intro("teamrc");
          s.start("Comparing local and relay...");
        }

        // Compute local hashes from current state
        const localKnowledge = adapter.readKnowledge();
        const localHashes = computeTeamHashes(ctx.team, localKnowledge);

        // Fetch remote hashes (lightweight HEAD request)
        const remoteHead = await client.getTeamHead();

        // Fast path: hashes match, everything in sync
        if (localHashes.hash === remoteHead.hash) {
          if (useJson) {
            jsonOutput({ added: [], removed: [], changed: [], knowledgeDiff: false, skillsAdded: [], skillsRemoved: [] });
            return;
          }
          s.stop(`Comparing local <-> relay for "${ctx.team.name}"`);
          p.log.success("No differences between local and relay.");
          p.outro("Everything in sync.");
          return;
        }

        // Hashes differ — identify which sections changed
        const membersDiffer = localHashes.membersHash !== remoteHead.members_hash;
        const skillsDiffer = localHashes.skillsHash !== remoteHead.skills_hash;
        const knowledgeDiffers = localHashes.knowledgeHash !== remoteHead.knowledge_hash;

        // Fetch full remote team for detailed diff
        const remoteTeam = await client.getTeam();

        // --- Members diff ---
        const localAgents = new Map(ctx.team.members.map((m) => [m.name, m.role]));
        const remoteAgents = new Map(remoteTeam.members.map((m) => [m.name, m.role]));
        const added: string[] = [];
        const removed: string[] = [];
        const changed: string[] = [];

        if (membersDiffer) {
          for (const [name, role] of localAgents) {
            if (!remoteAgents.has(name)) {
              added.push(name);
            } else if (remoteAgents.get(name) !== role) {
              changed.push(name);
            }
          }
          for (const [name] of remoteAgents) {
            if (!localAgents.has(name)) {
              removed.push(name);
            }
          }
        }

        // --- Skills diff ---
        const localSkills = new Map((ctx.team.skills || []).map((sk) => [sk.id, sk]));
        const remoteSkills = new Map((remoteTeam.skills || []).map((sk) => [sk.id, sk]));
        const skillsAdded: string[] = [];
        const skillsRemoved: string[] = [];

        if (skillsDiffer) {
          for (const [id] of localSkills) {
            if (!remoteSkills.has(id)) skillsAdded.push(id);
          }
          for (const [id] of remoteSkills) {
            if (!localSkills.has(id)) skillsRemoved.push(id);
          }
        }

        // --- Team name diff ---
        const teamNameDiff = ctx.team.name !== remoteTeam.name
          ? { local: ctx.team.name, remote: remoteTeam.name }
          : null;

        if (useJson) {
          const result: Record<string, unknown> = {
            added, removed, changed,
            knowledgeDiff: knowledgeDiffers,
            skillsAdded, skillsRemoved,
          };
          if (teamNameDiff) result.teamName = teamNameDiff;
          jsonOutput(result);
          return;
        }

        s.stop(`Comparing local <-> relay for "${ctx.team.name}"`);

        const totalDiffs = added.length + removed.length + changed.length + (teamNameDiff ? 1 : 0) +
          (knowledgeDiffers ? 1 : 0) + skillsAdded.length + skillsRemoved.length;

        // Members changed but no individual field diffs found (e.g. soul/skills changed)
        if (membersDiffer && added.length === 0 && removed.length === 0 && changed.length === 0) {
          p.log.info("Members\n  ~ members hash differs (soul or skill assignments changed)");
        }

        // Skills changed but same set of IDs (e.g. body/description changed)
        if (skillsDiffer && skillsAdded.length === 0 && skillsRemoved.length === 0) {
          p.log.info("Skills\n  ~ skills hash differs (content changed)");
        }

        const diffLines: string[] = [];
        if (teamNameDiff) {
          diffLines.push(`  ~ team name: "${teamNameDiff.local}" (local) vs "${teamNameDiff.remote}" (relay)`);
        }
        for (const name of added) {
          diffLines.push(`  + ${name} (${localAgents.get(name)})  local only`);
        }
        for (const name of changed) {
          diffLines.push(`  ~ ${name}: "${localAgents.get(name)}" -> "${remoteAgents.get(name)}"`);
        }
        for (const name of removed) {
          diffLines.push(`  - ${name} (${remoteAgents.get(name)})  relay only`);
        }

        if (diffLines.length > 0) p.log.info("Members\n" + diffLines.join("\n"));

        if (skillsAdded.length || skillsRemoved.length) {
          const skillLines: string[] = [];
          for (const id of skillsAdded) skillLines.push(`  + ${id}  local only`);
          for (const id of skillsRemoved) skillLines.push(`  - ${id}  relay only`);
          p.log.info("Skills\n" + skillLines.join("\n"));
        }

        if (knowledgeDiffers) {
          const localLen = localKnowledge.trim().length;
          const remoteLen = (remoteTeam.knowledge || "").trim().length;
          if (!localKnowledge.trim()) {
            p.log.info(`Knowledge\n  + relay has knowledge (${remoteLen} chars), local is empty`);
          } else if (!(remoteTeam.knowledge || "").trim()) {
            p.log.info(`Knowledge\n  + local has knowledge (${localLen} chars), relay is empty`);
          } else {
            p.log.info(`Knowledge\n  ~ local (${localLen} chars) differs from relay (${remoteLen} chars)`);
          }
        }

        const effectiveDiffs = (membersDiffer ? 1 : 0) + (skillsDiffer ? 1 : 0) +
          (knowledgeDiffers ? 1 : 0) + (teamNameDiff ? 1 : 0);
        p.outro(`${effectiveDiffs} section(s) differ. Run teamrc sync to resolve.`);
      } catch (err) {
        if (!useJson) s.error("Failed to fetch relay state.");
        if (useJson) {
          jsonOutput({ error: (err as Error).message });
        } else {
          p.log.error((err as Error).message);
        }
        process.exit(1);
      }
    });
}
