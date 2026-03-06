import * as fs from "node:fs";
import YAML from "yaml";
import { validateAgentName, type TeamDefinition, type TeamMember, type Rule, type Skill } from "./adapters/base.js";

const MAX_YAML_SIZE = 256 * 1024; // 256 KB
const MAX_MEMBERS = 100;
const TEAM_NAME_RE = /^[a-zA-Z0-9][a-zA-Z0-9 _-]{0,63}$/;

export function validateTeamName(name: string): void {
  if (!TEAM_NAME_RE.test(name)) {
    throw new Error(`Invalid team name: ${JSON.stringify(name)}. Must be 1-64 alphanumeric characters, spaces, hyphens, or underscores.`);
  }
}

export function readTeamYaml(filePath: string): TeamDefinition | null {
  if (!fs.existsSync(filePath)) return null;

  const stat = fs.statSync(filePath);
  if (stat.size > MAX_YAML_SIZE) {
    throw new Error(`agent-team.yaml exceeds maximum size of ${MAX_YAML_SIZE} bytes`);
  }

  const content = fs.readFileSync(filePath, "utf-8");
  const data = YAML.parse(content);

  if (!data || typeof data !== "object") return null;

  const rawMembers = data.members || [];
  if (!Array.isArray(rawMembers) || rawMembers.length > MAX_MEMBERS) {
    throw new Error(`agent-team.yaml members must be an array with at most ${MAX_MEMBERS} entries`);
  }

  const members: TeamMember[] = rawMembers.map((m: Record<string, unknown>) => {
    const name = String(m.name || "");
    validateAgentName(name);
    const member: TeamMember = { name, role: String(m.role || "") };
    if (m.soul) member.soul = String(m.soul);
    if (Array.isArray(m.rules)) member.rules = m.rules as string[];
    if (Array.isArray(m.skills)) member.skills = m.skills as string[];
    return member;
  });

  const rawRules = data.rules || [];
  const rules: Rule[] = Array.isArray(rawRules)
    ? rawRules.map((r: Record<string, unknown>) => ({
        id: String(r.id || ""),
        ...(r.title ? { title: String(r.title) } : {}),
        ...(r.globs ? { globs: r.globs as string[] } : {}),
        ...(r.alwaysApply !== undefined ? { alwaysApply: Boolean(r.alwaysApply) } : {}),
        body: r.body as string | { source: string },
      }))
    : [];

  const rawSkills = data.skills || [];
  const skills: Skill[] = Array.isArray(rawSkills)
    ? rawSkills.map((s: Record<string, unknown>) => ({
        id: String(s.id || ""),
        ...(s.title ? { title: String(s.title) } : {}),
        ...(s.description ? { description: String(s.description) } : {}),
        ...(s.body !== undefined ? { body: s.body as string | { source: string } } : {}),
      }))
    : [];

  const teamName = data.name || "";
  if (teamName) validateTeamName(teamName);

  return {
    name: teamName,
    members,
    rules,
    skills,
  };
}

export function writeTeamYaml(filePath: string, team: TeamDefinition): void {
  const data: Record<string, unknown> = {
    name: team.name,
    members: team.members.map((m) => {
      const entry: Record<string, unknown> = { name: m.name, role: m.role };
      if (m.soul) entry.soul = m.soul;
      if (m.rules && m.rules.length > 0) entry.rules = m.rules;
      if (m.skills && m.skills.length > 0) entry.skills = m.skills;
      return entry;
    }),
  };

  if (team.rules && team.rules.length > 0) {
    data.rules = team.rules.map((r) => {
      const entry: Record<string, unknown> = { id: r.id };
      if (r.title) entry.title = r.title;
      if (r.globs) entry.globs = r.globs;
      if (r.alwaysApply !== undefined) entry.alwaysApply = r.alwaysApply;
      entry.body = r.body;
      return entry;
    });
  }

  if (team.skills && team.skills.length > 0) {
    data.skills = team.skills.map((s) => {
      const entry: Record<string, unknown> = { id: s.id };
      if (s.title) entry.title = s.title;
      if (s.description) entry.description = s.description;
      if (s.body) entry.body = s.body;
      return entry;
    });
  }

  const yaml = YAML.stringify(data);
  fs.writeFileSync(filePath, yaml);
}
