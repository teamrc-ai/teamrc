import type { Skill, TeamDefinition, TeamMember } from "./adapters/base.js";

/** Resolve skills for an agent. Only returns explicitly assigned skills. */
export function resolveAgentSkills(agent: TeamMember, team: TeamDefinition): Skill[] {
  if (!agent.skills || agent.skills.length === 0 || !team.skills) return [];
  return agent.skills
    .map((id) => team.skills!.find((s) => s.id === id))
    .filter((s): s is Skill => s !== undefined);
}
