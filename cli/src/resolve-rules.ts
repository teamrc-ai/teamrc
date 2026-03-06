import type { Rule, Skill, TeamDefinition, TeamMember } from "./adapters/base.js";

export function resolveAgentRules(agent: TeamMember, team: TeamDefinition): Rule[] {
  if (!agent.rules || !team.rules) return [];
  return agent.rules
    .map((id) => team.rules!.find((r) => r.id === id))
    .filter((r): r is Rule => r !== undefined);
}

export function resolveAgentSkills(agent: TeamMember, team: TeamDefinition): Skill[] {
  if (!agent.skills || !team.skills) return [];
  return agent.skills
    .map((id) => team.skills!.find((s) => s.id === id))
    .filter((s): s is Skill => s !== undefined);
}
