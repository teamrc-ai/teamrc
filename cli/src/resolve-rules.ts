import type { Rule, Skill, TeamDefinition, TeamMember } from "./adapters/base.js";

/** Resolve rules for an agent. Only returns explicitly assigned rules. */
export function resolveAgentRules(agent: TeamMember, team: TeamDefinition): Rule[] {
  if (!agent.rules || agent.rules.length === 0 || !team.rules) return [];
  return agent.rules
    .map((id) => team.rules!.find((r) => r.id === id))
    .filter((r): r is Rule => r !== undefined);
}

/** Resolve skills for an agent. Only returns explicitly assigned skills. */
export function resolveAgentSkills(agent: TeamMember, team: TeamDefinition): Skill[] {
  if (!agent.skills || agent.skills.length === 0 || !team.skills) return [];
  return agent.skills
    .map((id) => team.skills!.find((s) => s.id === id))
    .filter((s): s is Skill => s !== undefined);
}
