import type { Command } from "commander";
import * as p from "@clack/prompts";
import { getAdapter, slugify } from "../adapters/base.js";
import { listAgentCategories, loadAgent, loadSkill, agentRecommendedSkills } from "../catalog.js";
import { writeTeamYaml, TEAM_YAML, GLOBAL_TEAM_YAML } from "../team-yaml.js";
import {
  isNonInteractive,
  handleCancel,
  requireTeamContext,
  effectiveScope,
} from "../utils.js";

export function registerAddMember(program: Command): void {
  program
    .command("add-member")
    .description("Add a catalog agent (or custom agent) to the current team")
    .argument("[agent-name]", "Agent name from catalog (e.g. backend-dev)")
    .action(async (agentName?: string) => {
      p.intro("teamrc");

      const ctx = requireTeamContext();
      const { team, scope, client, platforms } = ctx;
      const yamlPath = scope === "global" ? GLOBAL_TEAM_YAML : TEAM_YAML;

      // Resolve agent name — from argument or interactive picker
      let name = agentName;
      if (!name) {
        if (isNonInteractive()) {
          p.log.error("Agent name is required in non-interactive mode.\n  Usage: teamrc add-member <agent-name>");
          process.exit(1);
        }

        const categories = listAgentCategories();
        const existingNames = new Set(team.members.map((m) => m.name));

        // Build flat option list grouped by category
        const options: Array<{ value: string; label: string; hint?: string }> = [];
        for (const cat of categories) {
          const available = cat.agents.filter((a) => !existingNames.has(a));
          if (available.length === 0) continue;
          for (const a of available) {
            try {
              const agent = loadAgent(a);
              options.push({ value: a, label: a, hint: `${agent.role} [${cat.label}]` });
            } catch {
              options.push({ value: a, label: a, hint: cat.label });
            }
          }
        }

        if (options.length === 0) {
          p.log.warn("All catalog agents are already on this team.");
          p.outro("Nothing to add.");
          return;
        }

        const selected = await p.select({
          message: "Select an agent to add",
          options,
        });
        handleCancel(selected);
        name = selected as string;
      }

      // Duplicate check
      if (team.members.find((m) => m.name === name)) {
        p.log.warn(`Agent "${name}" is already on this team.`);
        p.outro("Nothing to add.");
        return;
      }

      // Load agent from catalog
      let agent;
      try {
        agent = loadAgent(name);
      } catch {
        p.log.error(`Agent "${name}" not found in catalog.`);
        process.exit(1);
      }

      // Get recommended skills for this agent
      const recommendedSkillIds = agentRecommendedSkills(name);

      // Ensure referenced skills exist in team.skills
      const existingSkillIds = new Set((team.skills ?? []).map((s) => s.id));
      const newSkills = [];
      for (const skillId of recommendedSkillIds) {
        if (!existingSkillIds.has(skillId)) {
          try {
            const skill = loadSkill(skillId);
            newSkills.push({
              id: skill.id,
              title: skill.title,
              ...(skill.description ? { description: skill.description } : {}),
              ...(skill.alwaysApply !== undefined ? { alwaysApply: skill.alwaysApply } : {}),
              ...(skill.globs ? { globs: skill.globs } : {}),
              ...(skill.userInvocable !== undefined ? { userInvocable: skill.userInvocable } : {}),
              body: skill.body,
            });
          } catch {
            // Skill not in catalog — skip
          }
        }
      }

      // Build new member
      const newMember = {
        name: agent.name,
        role: agent.role,
        soul: agent.soul,
        ...(recommendedSkillIds.length > 0 ? { skills: recommendedSkillIds } : {}),
      };

      // Mutate team (in memory only — write after push succeeds)
      team.members.push(newMember);
      if (newSkills.length > 0) {
        if (!team.skills) team.skills = [];
        team.skills.push(...newSkills);
      }

      // Push to relay first — don't persist locally until relay accepts
      const s = p.spinner();
      try {
        s.start("Pushing to relay...");
        const knowledge = ctx.adapters[0]?.readKnowledge();
        await client.pushTeam(team, knowledge || undefined);
        s.stop("Pushed.");
      } catch (err) {
        s.error("Push failed.");
        p.log.error((err as Error).message);
        process.exit(1);
      }

      // Write YAML and apply to platforms only after successful push
      writeTeamYaml(yamlPath, team);
      for (const pl of platforms) {
        const adapter = getAdapter(pl, slugify(team.name));
        adapter.writeTeam(team, effectiveScope(pl, scope));
      }

      // Summary
      const parts = [`Added ${agent.name} (${agent.role})`];
      if (recommendedSkillIds.length > 0) {
        parts.push(`Includes ${recommendedSkillIds.length} skill(s): ${recommendedSkillIds.join(", ")}`);
      }
      p.log.success(parts.join("\n  "));
      p.outro(`Applied to ${platforms.length} platform(s).`);
    });
}
