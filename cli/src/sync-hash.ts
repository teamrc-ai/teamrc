import { createHash } from "node:crypto";
import type { TeamMember, Skill, TeamDefinition } from "./adapters/base.js";

export interface TeamHashes {
  hash: string;
  membersHash: string;
  skillsHash: string;
  knowledgeHash: string;
}

/**
 * Recursively sort object keys and remove null/undefined/empty values.
 * Arrays are preserved as-is (order matters), but arrays of strings
 * inside specific fields (like `globs`, `skills`) are sorted.
 */
export function canonicalize(value: unknown): unknown {
  if (value === null || value === undefined) {
    return undefined;
  }

  if (Array.isArray(value)) {
    return value.map((item) => canonicalize(item)).filter((item) => item !== undefined);
  }

  if (typeof value === "object") {
    const sorted: Record<string, unknown> = {};
    const keys = Object.keys(value as Record<string, unknown>).sort();
    for (const key of keys) {
      const v = (value as Record<string, unknown>)[key];
      const canonical = canonicalize(v);
      if (canonical !== undefined && canonical !== null) {
        // Omit empty strings only if they represent "no value"
        // but keep them for fields like `body` where empty string is valid
        sorted[key] = canonical;
      }
    }
    // Return undefined if the object is empty after cleaning
    if (Object.keys(sorted).length === 0) return undefined;
    return sorted;
  }

  return value;
}

function sha256(input: string): string {
  return createHash("sha256").update(input, "utf-8").digest("hex");
}

function canonicalJson(value: unknown): string {
  return JSON.stringify(value);
}

/**
 * Canonicalize a member for hashing.
 * Sorts keys, removes null/undefined, sorts `skills` array.
 */
function canonicalizeMember(member: TeamMember): Record<string, unknown> {
  const obj: Record<string, unknown> = {};
  if (member.description !== undefined && member.description !== null && member.description !== "") {
    obj.description = member.description;
  }
  obj.name = member.name;
  obj.role = member.role;
  if (member.skills && member.skills.length > 0) {
    obj.skills = [...member.skills].sort();
  }
  if (member.soul !== undefined && member.soul !== null && member.soul !== "") {
    obj.soul = member.soul;
  }
  // Return with sorted keys
  return canonicalize(obj) as Record<string, unknown>;
}

/**
 * Canonicalize a skill for hashing.
 * Sorts keys, removes null/undefined, sorts `globs` array.
 */
function canonicalizeSkill(skill: Skill): Record<string, unknown> {
  const obj: Record<string, unknown> = {};
  if (skill.alwaysApply !== undefined && skill.alwaysApply !== null) {
    obj.alwaysApply = skill.alwaysApply;
  }
  // body: include string bodies, skip source-referenced bodies
  if (typeof skill.body === "string" && skill.body !== "") {
    obj.body = skill.body;
  }
  if (skill.description !== undefined && skill.description !== null && skill.description !== "") {
    obj.description = skill.description;
  }
  if (skill.globs && skill.globs.length > 0) {
    obj.globs = [...skill.globs].sort();
  }
  obj.id = skill.id;
  if (skill.title !== undefined && skill.title !== null && skill.title !== "") {
    obj.title = skill.title;
  }
  if (skill.userInvocable !== undefined && skill.userInvocable !== null) {
    obj.userInvocable = skill.userInvocable;
  }
  // Keys are already in sorted order above (alphabetical), but canonicalize to be safe
  return canonicalize(obj) as Record<string, unknown>;
}

export function computeMembersHash(members: TeamMember[]): string {
  const sorted = [...members].sort((a, b) => a.name.localeCompare(b.name));
  const canonical = sorted.map(canonicalizeMember);
  return sha256(canonicalJson(canonical));
}

export function computeSkillsHash(skills: Skill[]): string {
  const sorted = [...skills].sort((a, b) => a.id.localeCompare(b.id));
  const canonical = sorted.map(canonicalizeSkill);
  return sha256(canonicalJson(canonical));
}

export function computeKnowledgeHash(knowledge: string | undefined): string {
  if (!knowledge) {
    return sha256("");
  }
  // Normalize trailing newline: strip trailing whitespace, add exactly one newline
  const normalized = knowledge.trimEnd() + "\n";
  return sha256(normalized);
}

export function computeFullHash(
  membersHash: string,
  skillsHash: string,
  knowledgeHash: string,
): string {
  return sha256(`${membersHash}:${skillsHash}:${knowledgeHash}`);
}

export function computeTeamHashes(team: TeamDefinition, knowledge?: string): TeamHashes {
  const membersHash = computeMembersHash(team.members);
  const skillsHash = computeSkillsHash(team.skills ?? []);
  const knowledgeHash = computeKnowledgeHash(knowledge);
  const hash = computeFullHash(membersHash, skillsHash, knowledgeHash);
  return { hash, membersHash, skillsHash, knowledgeHash };
}
