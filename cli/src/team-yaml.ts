import * as fs from "node:fs";
import YAML from "yaml";
import { validateAgentName, VALID_PLATFORMS, type TeamDefinition, type TeamMember, type Rule, type Skill } from "./adapters/base.js";

/** Current team YAML filename */
export const TEAM_YAML = ".teamrc.yaml";
/** Legacy filename (deprecated) */
const LEGACY_TEAM_YAML = ".teamrc.yaml";

/** Resolve team YAML path: prefers .teamrc.yaml, falls back to .teamrc.yaml with deprecation warning */
export function resolveTeamYamlPath(): string {
  if (fs.existsSync(TEAM_YAML)) return TEAM_YAML;
  if (fs.existsSync(LEGACY_TEAM_YAML)) {
    console.warn(`Deprecation: Rename ${LEGACY_TEAM_YAML} to ${TEAM_YAML}`);
    return LEGACY_TEAM_YAML;
  }
  return TEAM_YAML;
}

const MAX_YAML_SIZE = 256 * 1024; // 256 KB
const MAX_MEMBERS = 100;
const MAX_RULES = 200;
const MAX_SKILLS = 200;
const TEAM_NAME_RE = /^[a-zA-Z0-9][a-zA-Z0-9 _-]{0,63}$/;
const RULE_ID_RE = /^[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}$/;

export function validateRuleId(id: string): void {
  if (!RULE_ID_RE.test(id)) {
    throw new Error(`Invalid rule/skill ID: ${JSON.stringify(id)}. Must be 1-64 alphanumeric characters, hyphens, or underscores.`);
  }
}

function parseBody(raw: unknown): string | { source: string } {
  if (typeof raw === "string") return raw;
  if (raw && typeof raw === "object" && "source" in raw && typeof (raw as Record<string, unknown>).source === "string") {
    return { source: (raw as Record<string, unknown>).source as string };
  }
  return "";
}

export function validateTeamName(name: string): void {
  if (!TEAM_NAME_RE.test(name)) {
    throw new Error(`Invalid team name: ${JSON.stringify(name)}. Must be 1-64 alphanumeric characters, spaces, hyphens, or underscores.`);
  }
}

export function readTeamYaml(filePath: string): TeamDefinition | null {
  if (!fs.existsSync(filePath)) return null;

  const stat = fs.statSync(filePath);
  if (stat.size > MAX_YAML_SIZE) {
    throw new Error(`.teamrc.yaml exceeds maximum size of ${MAX_YAML_SIZE} bytes`);
  }

  const content = fs.readFileSync(filePath, "utf-8");
  const data = YAML.parse(content);

  if (!data || typeof data !== "object") return null;

  const rawMembers = data.members || [];
  if (!Array.isArray(rawMembers) || rawMembers.length > MAX_MEMBERS) {
    throw new Error(`.teamrc.yaml members must be an array with at most ${MAX_MEMBERS} entries`);
  }

  const members: TeamMember[] = rawMembers.map((m: Record<string, unknown>) => {
    const name = String(m.name || "");
    validateAgentName(name);
    const member: TeamMember = { name, role: String(m.role || "") };
    if (m.soul) member.soul = String(m.soul);
    if (Array.isArray(m.rules)) member.rules = m.rules.map((r: unknown) => String(r));
    if (Array.isArray(m.skills)) member.skills = m.skills.map((s: unknown) => String(s));
    return member;
  });

  const rawRules = data.rules || [];
  if (Array.isArray(rawRules) && rawRules.length > MAX_RULES) {
    throw new Error(`.teamrc.yaml rules must have at most ${MAX_RULES} entries`);
  }
  const rules: Rule[] = Array.isArray(rawRules)
    ? rawRules.map((r: Record<string, unknown>) => {
        const id = String(r.id || "");
        validateRuleId(id);
        return {
          id,
          ...(r.title ? { title: String(r.title) } : {}),
          ...(Array.isArray(r.globs) ? { globs: r.globs.filter((g: unknown): g is string => typeof g === "string") } : {}),
          ...(r.alwaysApply !== undefined ? { alwaysApply: Boolean(r.alwaysApply) } : {}),
          body: parseBody(r.body),
        };
      })
    : [];

  const rawSkills = data.skills || [];
  if (Array.isArray(rawSkills) && rawSkills.length > MAX_SKILLS) {
    throw new Error(`.teamrc.yaml skills must have at most ${MAX_SKILLS} entries`);
  }
  const skills: Skill[] = Array.isArray(rawSkills)
    ? rawSkills.map((s: Record<string, unknown>) => {
        const id = String(s.id || "");
        validateRuleId(id);
        return {
          id,
          ...(s.title ? { title: String(s.title) } : {}),
          ...(s.description ? { description: String(s.description) } : {}),
          ...(s.body !== undefined ? { body: parseBody(s.body) } : {}),
        };
      })
    : [];

  const teamName = data.name || "";
  if (teamName) validateTeamName(teamName);

  // Parse new multi-project fields
  const teamId = data.teamId ? String(data.teamId) : undefined;
  const relay = data.relay ? String(data.relay) : undefined;
  const noSync = data.noSync === true ? true : undefined;

  let platforms: string[] | undefined;
  if (Array.isArray(data.platforms)) {
    const validSet = new Set<string>(VALID_PLATFORMS);
    platforms = data.platforms
      .map((p: unknown) => String(p))
      .filter((p: string) => {
        if (!validSet.has(p)) {
          throw new Error(`Unknown platform in .teamrc.yaml: ${JSON.stringify(p)}. Valid: ${VALID_PLATFORMS.join(", ")}`);
        }
        return true;
      });
  }

  return {
    name: teamName,
    members,
    rules,
    skills,
    ...(teamId ? { teamId } : {}),
    ...(relay ? { relay } : {}),
    ...(platforms ? { platforms } : {}),
    ...(noSync ? { noSync } : {}),
  };
}

export function writeTeamYaml(filePath: string, team: TeamDefinition): void {
  const data: Record<string, unknown> = {
    name: team.name,
    ...(team.teamId ? { teamId: team.teamId } : {}),
    ...(team.relay ? { relay: team.relay } : {}),
    ...(team.platforms ? { platforms: team.platforms } : {}),
    ...(team.noSync ? { noSync: team.noSync } : {}),
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
