import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";
import { randomBytes } from "node:crypto";
import YAML from "yaml";
import { validateAgentName, slugify, VALID_PLATFORMS, type TeamDefinition, type TeamMember, type Skill } from "./adapters/base.js";
import { validateRelayUrl } from "./config.js";

export const TEAM_YAML = ".teamrc.yaml";
export const GLOBAL_TEAM_YAML = path.join(os.homedir(), ".teamrc", "team.yaml");

const MAX_YAML_SIZE = 256 * 1024; // 256 KB
const MAX_MEMBERS = 20;
const MAX_SKILLS = 50;
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
    if (m.description) member.description = String(m.description);
    if (m.soul) member.soul = String(m.soul);
    if (Array.isArray(m.skills)) member.skills = m.skills.map((s: unknown) => String(s));
    return member;
  });

  // Check for slug collisions (different names that map to the same filename)
  const slugMap = new Map<string, string>();
  for (const m of members) {
    const slug = slugify(m.name);
    const existing = slugMap.get(slug);
    if (existing) {
      throw new Error(`.teamrc.yaml members "${existing}" and "${m.name}" produce the same filename (trc-${slug}). Use more distinct names.`);
    }
    slugMap.set(slug, m.name);
  }

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
          ...(s.disableModelInvocation !== undefined ? { disableModelInvocation: Boolean(s.disableModelInvocation) } : {}),
          ...(s.argumentHint ? { argumentHint: String(s.argumentHint) } : {}),
          body: parseBody(s.body),
        };
      })
    : [];

  // Check for slug collisions among skill IDs (different IDs that map to the same filename)
  const skillSlugMap = new Map<string, string>();
  for (const s of parsedSkills) {
    const slug = slugify(s.id);
    const existing = skillSlugMap.get(slug);
    if (existing) {
      throw new Error(`.teamrc.yaml skills "${existing}" and "${s.id}" produce the same filename (SKILL-${slug}.md). Use more distinct IDs.`);
    }
    skillSlugMap.set(slug, s.id);
  }

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
      if (m.description) entry.description = m.description;
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
      if (s.disableModelInvocation !== undefined) entry.disableModelInvocation = s.disableModelInvocation;
      if (s.argumentHint) entry.argumentHint = s.argumentHint;
      entry.body = s.body;
      return entry;
    });
  }

  const yaml = YAML.stringify(data);
  // Atomic write: write to temp file, then rename (atomic on POSIX)
  const dir = path.dirname(filePath);
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  const tmpPath = `${filePath}.${randomBytes(4).toString("hex")}.tmp`;
  fs.writeFileSync(tmpPath, yaml, { mode: 0o600 });
  fs.renameSync(tmpPath, filePath);
}

/** Merge knowledge strings using append-only dedup. Remote (relay) is the
 *  source of truth for line order; new local lines are appended at the bottom. */
export function mergeKnowledge(remote: string, local: string): string {
  if (!remote) return local;
  if (!local) return remote;

  const remoteLines = new Set(
    remote.split("\n").map((l) => l.trim()).filter(Boolean),
  );
  const newLines = local
    .split("\n")
    .filter((l) => l.trim() && !remoteLines.has(l.trim()));

  if (newLines.length === 0) return remote;
  return remote.trimEnd() + "\n" + newLines.join("\n") + "\n";
}

export interface KnowledgeSection {
  heading: string;  // text after "## "
  body: string;     // full text including "## " line and all lines until next section
}

export interface ParsedKnowledge {
  preamble: string;    // everything before first "## ", up to 10KB
  sections: KnowledgeSection[];  // ordered oldest (top) → newest (bottom)
}

const MAX_PREAMBLE_BYTES = 10 * 1024; // 10 KB

export function parseKnowledge(content: string): ParsedKnowledge {
  if (!content) return { preamble: "", sections: [] };

  // Find the first "## " heading (must be at start of a line)
  const sectionPattern = /^## /m;
  const firstMatch = sectionPattern.exec(content);

  let preamble: string;
  let rest: string;

  if (!firstMatch) {
    preamble = content;
    rest = "";
  } else {
    preamble = content.slice(0, firstMatch.index);
    rest = content.slice(firstMatch.index);
  }

  // Cap preamble at 10KB, truncating at a line boundary
  if (Buffer.byteLength(preamble, "utf8") > MAX_PREAMBLE_BYTES) {
    const lines = preamble.split("\n");
    let truncated = "";
    for (const line of lines) {
      const candidate = truncated ? truncated + "\n" + line : line;
      if (Buffer.byteLength(candidate, "utf8") > MAX_PREAMBLE_BYTES) break;
      truncated = candidate;
    }
    preamble = truncated ? truncated + "\n" : "";
  }

  // Parse sections
  const sections: KnowledgeSection[] = [];
  if (rest) {
    // Split on "## " at start of line, keeping the delimiter
    const parts = rest.split(/^(?=## )/m);
    for (const part of parts) {
      if (!part) continue;
      const newlineIdx = part.indexOf("\n");
      const headingLine = newlineIdx === -1 ? part : part.slice(0, newlineIdx);
      const heading = headingLine.replace(/^## /, "");
      sections.push({ heading, body: part });
    }
  }

  return { preamble, sections };
}

export function pruneKnowledge(content: string, maxBytes: number = 100_000): string {
  if (!content) return "";

  const totalBytes = Buffer.byteLength(content, "utf8");
  if (totalBytes <= maxBytes) return content;

  const parsed = parseKnowledge(content);
  const targetBytes = Math.floor(maxBytes * 0.8);

  let currentBytes = Buffer.byteLength(parsed.preamble, "utf8");

  // Drop sections from the front (oldest first) until we fit
  let startIdx = 0;
  for (let i = 0; i < parsed.sections.length; i++) {
    const projectedTotal = currentBytes + parsed.sections.slice(i).reduce(
      (sum, s) => sum + Buffer.byteLength(s.body, "utf8"), 0,
    );

    if (projectedTotal <= targetBytes) {
      startIdx = i;
      break;
    }
    startIdx = i + 1;
  }

  const remainingSections = parsed.sections.slice(startIdx);
  return parsed.preamble + remainingSections.map((s) => s.body).join("");
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
    // Eliminate TOCTOU race: skip existsSync pre-check, use try/catch on realpathSync
    let realResolved: string;
    try {
      realResolved = fs.realpathSync(resolved);
    } catch {
      return ""; // file doesn't exist
    }
    const realBaseResolved = fs.realpathSync(realBase);
    if (!realResolved.startsWith(realBaseResolved + path.sep) && realResolved !== realBaseResolved) {
      throw new Error(`Path traversal blocked: source "${body.source}" resolves outside project directory via symlink`);
    }
    const stat = fs.statSync(realResolved);
    if (stat.size > MAX_SOURCE_SIZE) {
      throw new Error(`Source file "${body.source}" exceeds maximum size of ${MAX_SOURCE_SIZE} bytes`);
    }
    return fs.readFileSync(realResolved, "utf-8");
  }
  return "";
}

// ---------------------------------------------------------------------------
// Local config (.teamrc/local.yaml) — per-machine, gitignored
// ---------------------------------------------------------------------------

export const LOCAL_YAML = ".teamrc/local.yaml";
export const GLOBAL_LOCAL_YAML = path.join(os.homedir(), ".teamrc", "local.yaml");

export interface LocalConfig {
  activeMembers?: string[];
}

export function readLocalYaml(filePath?: string): LocalConfig {
  const p = filePath ?? LOCAL_YAML;
  if (!fs.existsSync(p)) return {};
  try {
    const content = fs.readFileSync(p, "utf-8");
    const data = YAML.parse(content);
    if (!data || typeof data !== "object") return {};
    return {
      ...(Array.isArray(data.activeMembers) ? { activeMembers: data.activeMembers.map((m: unknown) => String(m)) } : {}),
    };
  } catch {
    return {};
  }
}

export function writeLocalYaml(filePath: string, config: LocalConfig): void {
  if (config.activeMembers?.length) {
    const dir = path.dirname(filePath);
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    const yaml = YAML.stringify({ activeMembers: config.activeMembers });
    fs.writeFileSync(filePath, yaml);
  } else if (fs.existsSync(filePath)) {
    // Clean up file when reverting to defaults (all members active)
    fs.unlinkSync(filePath);
  }
}
