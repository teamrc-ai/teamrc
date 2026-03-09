import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";
import YAML from "yaml";
import { validateAgentName, VALID_PLATFORMS, type TeamDefinition, type TeamMember, type Skill } from "./adapters/base.js";
import { validateRelayUrl } from "./config.js";

export const TEAM_YAML = ".teamrc.yaml";
export const GLOBAL_TEAM_YAML = path.join(os.homedir(), ".teamrc", "team.yaml");

const MAX_YAML_SIZE = 256 * 1024; // 256 KB
const MAX_MEMBERS = 100;
const MAX_SKILLS = 200;
const TEAM_NAME_RE = /^[a-zA-Z0-9][a-zA-Z0-9 _-]{0,63}$/;
const SKILL_ID_RE = /^[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}$/;

export function validateSkillId(id: string): void {
  if (!SKILL_ID_RE.test(id)) {
    throw new Error(`Invalid skill ID: ${JSON.stringify(id)}. Must be 1-64 alphanumeric characters, hyphens, or underscores.`);
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
    if (Array.isArray(m.skills)) member.skills = m.skills.map((s: unknown) => String(s));
    return member;
  });

  const rawSkills = data.skills || [];
  if (Array.isArray(rawSkills) && rawSkills.length > MAX_SKILLS) {
    throw new Error(`.teamrc.yaml skills must have at most ${MAX_SKILLS} entries`);
  }
  const parsedSkills: Skill[] = Array.isArray(rawSkills)
    ? rawSkills.map((s: Record<string, unknown>) => {
        const id = String(s.id || "");
        validateSkillId(id);
        return {
          id,
          ...(s.title ? { title: String(s.title) } : {}),
          ...(s.description ? { description: String(s.description) } : {}),
          ...(Array.isArray(s.globs) ? { globs: s.globs.filter((g: unknown): g is string => typeof g === "string") } : {}),
          ...(s.alwaysApply !== undefined ? { alwaysApply: Boolean(s.alwaysApply) } : {}),
          ...(s.userInvocable !== undefined ? { userInvocable: Boolean(s.userInvocable) } : {}),
          body: parseBody(s.body),
        };
      })
    : [];

  const teamName = data.name || "";
  if (teamName) validateTeamName(teamName);

  // Parse new multi-project fields
  const teamId = data.teamId ? String(data.teamId) : undefined;
  const cloneToken = data.cloneToken ? String(data.cloneToken) : undefined;
  const relay = data.relay ? String(data.relay) : undefined;
  if (relay) validateRelayUrl(relay);
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
    skills: parsedSkills,
    ...(teamId ? { teamId } : {}),
    ...(cloneToken ? { cloneToken } : {}),
    ...(relay ? { relay } : {}),
    ...(platforms ? { platforms } : {}),
  };
}

export function writeTeamYaml(filePath: string, team: TeamDefinition): void {
  const data: Record<string, unknown> = {
    name: team.name,
    ...(team.teamId ? { teamId: team.teamId } : {}),
    ...(team.cloneToken ? { cloneToken: team.cloneToken } : {}),
    ...(team.relay ? { relay: team.relay } : {}),
    ...(team.platforms ? { platforms: team.platforms } : {}),
    members: team.members.map((m) => {
      const entry: Record<string, unknown> = { name: m.name, role: m.role };
      if (m.soul) entry.soul = m.soul;
      if (m.skills && m.skills.length > 0) entry.skills = m.skills;
      return entry;
    }),
  };

  if (team.skills && team.skills.length > 0) {
    data.skills = team.skills.map((s) => {
      const entry: Record<string, unknown> = { id: s.id };
      if (s.title) entry.title = s.title;
      if (s.description) entry.description = s.description;
      if (s.alwaysApply !== undefined) entry.alwaysApply = s.alwaysApply;
      if (s.globs) entry.globs = s.globs;
      if (s.userInvocable !== undefined) entry.userInvocable = s.userInvocable;
      entry.body = s.body;
      return entry;
    });
  }

  const yaml = YAML.stringify(data);
  fs.writeFileSync(filePath, yaml);
}

/** Merge knowledge strings using append-only dedup by line content */
export function mergeKnowledge(local: string, remote: string): string {
  if (!local) return remote;
  if (!remote) return local;

  const localLines = new Set(
    local.split("\n").map((l) => l.trim()).filter(Boolean),
  );
  const newLines = remote
    .split("\n")
    .filter((l) => l.trim() && !localLines.has(l.trim()));

  if (newLines.length === 0) return local;
  return local.trimEnd() + "\n" + newLines.join("\n") + "\n";
}

export const MAX_KNOWLEDGE_SIZE = 512 * 1024; // 512 KB

const MAX_SOURCE_SIZE = 1024 * 1024; // 1 MB

export function resolveBody(
  body: string | { source: string } | undefined,
  basePath: string,
): string {
  if (body === undefined) return "";
  if (typeof body === "string") return body;
  if (body.source) {
    if (typeof body.source !== "string") return "";
    const resolved = path.resolve(basePath, body.source);
    const realBase = path.resolve(basePath);
    if (!resolved.startsWith(realBase + path.sep) && resolved !== realBase) {
      throw new Error(`Path traversal blocked: source "${body.source}" resolves outside project directory`);
    }
    if (!fs.existsSync(resolved)) return "";
    const realResolved = fs.realpathSync(resolved);
    const realBaseResolved = fs.realpathSync(realBase);
    if (!realResolved.startsWith(realBaseResolved + path.sep) && realResolved !== realBaseResolved) {
      throw new Error(`Path traversal blocked: source "${body.source}" resolves outside project directory via symlink`);
    }
    const stat = fs.statSync(resolved);
    if (stat.size > MAX_SOURCE_SIZE) {
      throw new Error(`Source file "${body.source}" exceeds maximum size of ${MAX_SOURCE_SIZE} bytes`);
    }
    return fs.readFileSync(resolved, "utf-8");
  }
  return "";
}
