import * as fs from "node:fs";
import { createRequire } from "node:module";
import * as path from "node:path";

/** Validate that an agent name is safe for use in file paths */
export function validateAgentName(name: string): void {
  if (!/^[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}$/.test(name)) {
    throw new Error(`Invalid agent name: ${JSON.stringify(name)}`);
  }
}

export interface Skill {
  id: string;
  title?: string;
  description?: string;
  alwaysApply?: boolean;
  globs?: string[];
  userInvocable?: boolean;
  disableModelInvocation?: boolean;
  argumentHint?: string;
  body: string | { source: string };
}

export interface TeamMember {
  name: string;
  role: string;
  description?: string;
  soul?: string;
  skills?: string[];  // references Skill.id
}

export interface TeamDefinition {
  name: string;
  members: TeamMember[];
  skills?: Skill[];
  teamId?: string;
  relay?: string;
  platforms?: string[];
  cloneToken?: string;
}

export function filterActiveMembers(team: TeamDefinition, activeMembers?: string[]): TeamDefinition {
  if (!activeMembers || activeMembers.length === 0) return team;
  const active = new Set(activeMembers);
  return {
    ...team,
    members: team.members.filter((m) => active.has(m.name)),
  };
}

export const VALID_PLATFORMS = [
  "claude-code",
  "cursor",
  "codex",
  "gemini",
  "openclaw",
  "copilot",
  "amazon-q",
  "windsurf",
  "cline",
] as const;

/** Platforms with implemented adapters (ready to use) */
export const SUPPORTED_PLATFORMS: readonly string[] = [
  "claude-code",
  "cursor",
  "codex",
  "gemini",
  "openclaw",
] as const;

/** Platforms recognized but not yet implemented */
export const UNIMPLEMENTED_PLATFORMS: readonly string[] = [
  "copilot",
  "amazon-q",
  "windsurf",
  "cline",
] as const;

/** Platforms that only support global scope (no per-project config) */
export const GLOBAL_ONLY_PLATFORMS: readonly string[] = ["openclaw"] as const;

/** Platforms that only support project scope (no global config) */
export const PROJECT_ONLY_PLATFORMS: readonly string[] = ["cursor", "codex"] as const;

export type TeamScope = "project" | "global";

/** Strip HTML comment sequences to prevent marker injection */
export function sanitizeMarkerContent(s: string): string {
  return s.replace(/<!--/g, "").replace(/-->/g, "");
}

export interface FileAction {
  type: "create" | "update" | "delete";
  path: string;
  description?: string;
}

export interface PlatformAdapter {
  readTeam(): TeamDefinition | null;
  writeTeam(team: TeamDefinition, scope?: TeamScope): void;
  /** Preview what writeTeam would do without modifying files. */
  planWrite(team: TeamDefinition, scope?: TeamScope): FileAction[];
  readKnowledge(): string;
  writeKnowledge(content: string): void;
  /** Return the absolute path to this adapter's knowledge file. */
  getKnowledgePath(scope?: TeamScope): string;
  /** Remove everything teamrc installed for this platform. Returns list of actions taken.
   *  When scope is provided, only removes files for that scope.
   *  When skillIds is provided, only removes skill dirs for those IDs (avoids deleting other teams' skills in shared roots). */
  uninstall(scope?: TeamScope, skillIds?: string[]): string[];
}

/** Write a native SKILL.md file for a skill in the given base directory */
export function writeSkillDir(baseDir: string, skill: Skill): void {
  if (typeof skill.body !== "string") return; // skip source-referenced skills
  const skillDir = path.join(baseDir, `trc-${skill.id}`);
  if (!fs.existsSync(skillDir)) fs.mkdirSync(skillDir, { recursive: true });

  const lines: string[] = ["---"];
  lines.push(`name: trc-${skill.id}`);
  if (skill.description) lines.push(`description: ${JSON.stringify(skill.description)}`);
  if (skill.disableModelInvocation) lines.push("disable-model-invocation: true");
  if (skill.argumentHint) lines.push(`argument-hint: ${JSON.stringify(skill.argumentHint)}`);
  lines.push("---", "");
  lines.push(skill.body);

  fs.writeFileSync(path.join(skillDir, "SKILL.md"), lines.join("\n") + "\n");
}

/** Remove trc-* skill directories for the given skill IDs under a base directory.
 *  Only removes directories matching the provided IDs, leaving other teams' skills intact. */
export function cleanupSkillDirs(baseDir: string, skillIds: string[]): number {
  if (!fs.existsSync(baseDir) || skillIds.length === 0) return 0;
  let count = 0;
  for (const id of skillIds) {
    const dirPath = path.join(baseDir, `trc-${id}`);
    if (fs.existsSync(dirPath)) {
      fs.rmSync(dirPath, { recursive: true, force: true });
      count++;
    }
  }
  return count;
}

/** List skill IDs from existing trc-* directories under a base directory */
export function listSkillDirIds(baseDir: string): string[] {
  if (!fs.existsSync(baseDir)) return [];
  return fs.readdirSync(baseDir)
    .filter((d) => d.startsWith("trc-") && fs.statSync(path.join(baseDir, d)).isDirectory())
    .map((d) => d.slice(4));
}

/** Manifest file name for tracking which skill IDs a team installed in a directory */
function skillManifestPath(baseDir: string, teamSlug: string): string {
  return path.join(baseDir, `.trc-manifest-${teamSlug}.json`);
}

/** Read the skill manifest for a team from a skills directory.
 *  Returns the list of skill IDs this team previously installed, or empty if no manifest. */
export function readSkillManifest(baseDir: string, teamSlug: string): string[] {
  const p = skillManifestPath(baseDir, teamSlug);
  if (!fs.existsSync(p)) return [];
  try {
    const data = JSON.parse(fs.readFileSync(p, "utf-8"));
    return Array.isArray(data.skillIds) ? data.skillIds : [];
  } catch {
    return [];
  }
}

/** Write the skill manifest for a team to a skills directory. */
export function writeSkillManifest(baseDir: string, teamSlug: string, skillIds: string[]): void {
  if (!fs.existsSync(baseDir)) fs.mkdirSync(baseDir, { recursive: true });
  fs.writeFileSync(skillManifestPath(baseDir, teamSlug), JSON.stringify({ skillIds }) + "\n");
}

/** Remove the skill manifest for a team from a skills directory. */
export function removeSkillManifest(baseDir: string, teamSlug: string): void {
  const p = skillManifestPath(baseDir, teamSlug);
  if (fs.existsSync(p)) fs.unlinkSync(p);
}

/** List trc-* files in a directory, filtered by extension */
export function listTrcFiles(dir: string, ext: string = ".md"): string[] {
  if (!fs.existsSync(dir)) return [];
  return fs.readdirSync(dir).filter((f) => f.startsWith("trc-") && f.endsWith(ext));
}

/** Delete all trc-* files in a directory, filtered by extension. Returns count deleted. */
export function deleteTrcFiles(dir: string, ext: string = ".md"): number {
  if (!fs.existsSync(dir)) return 0;
  const files = fs.readdirSync(dir).filter((f) => f.startsWith("trc-") && f.endsWith(ext));
  for (const f of files) fs.unlinkSync(path.join(dir, f));
  return files.length;
}

/** Upsert a marker-delimited block in a file. Creates the file if it doesn't exist. */
export function upsertMarkerBlock(
  filePath: string,
  marker: string,
  markerEnd: string,
  block: string,
  newFilePrefix?: string,
): void {
  let content = "";
  if (fs.existsSync(filePath)) {
    content = fs.readFileSync(filePath, "utf-8");
  }

  if (!content) {
    fs.writeFileSync(filePath, (newFilePrefix ?? "") + block + "\n");
    return;
  }

  const escaped = marker.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const escapedEnd = markerEnd.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const regex = new RegExp(`${escaped}[\\s\\S]*?${escapedEnd}`);

  if (regex.test(content)) {
    fs.writeFileSync(filePath, content.replace(regex, block));
  } else {
    fs.writeFileSync(filePath, content.trimEnd() + "\n\n" + block + "\n");
  }
}

/** Remove a marker-delimited block from a file. Deletes the file if empty after removal. */
export function removeMarkerBlock(
  filePath: string,
  marker: string,
  markerEnd: string,
): boolean {
  if (!fs.existsSync(filePath)) return false;
  const content = fs.readFileSync(filePath, "utf-8");

  const escaped = marker.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const escapedEnd = markerEnd.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const regex = new RegExp(`\\n?${escaped}[\\s\\S]*?${escapedEnd}\\n?`);

  if (!regex.test(content)) return false;

  const updated = content.replace(regex, "").trim();
  if (updated) {
    fs.writeFileSync(filePath, updated + "\n");
  } else {
    fs.unlinkSync(filePath);
  }
  return true;
}

/** Resolve agents directory  --  check project first, fall back to global */
export function resolveAgentsDir(
  projectDir: string,
  globalDir: string,
): { dir: string; scope: TeamScope } {
  if (listTrcFiles(projectDir).length > 0) {
    return { dir: projectDir, scope: "project" };
  }
  return { dir: globalDir, scope: "global" };
}

/** Strip newlines from text for safe inline use */
export function sanitizeText(s: string): string {
  return s.replace(/[\n\r]/g, " ").trim();
}

/** Slugify a name for use in file paths */
export function slugify(name: string): string {
  return name
    .toLowerCase()
    .replace(/[^a-z0-9-]/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "");
}

/** Build the knowledge file name for a given team slug */
export function knowledgeFileName(teamSlug: string): string {
  return `knowledge-${teamSlug || "team"}.md`;
}

/** Delete the knowledge file for a specific team slug. If slug is empty/falsy,
 *  deletes nothing (fail closed) to avoid wiping unrelated teams' files.
 *  Returns list of deleted paths. */
export function deleteKnowledgeFiles(dir: string, teamSlug: string): string[] {
  if (!fs.existsSync(dir)) return [];
  if (!teamSlug) return [];
  const deleted: string[] = [];
  const full = path.join(dir, knowledgeFileName(teamSlug));
  if (fs.existsSync(full)) {
    fs.unlinkSync(full);
    deleted.push(full);
  }
  return deleted;
}

/** Escape a string for use in YAML double-quoted values */
export function escapeYamlString(s: string): string {
  return s.replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, "\\n");
}

/** Constant skill ID for the team knowledge skill */
export const TEAM_KNOWLEDGE_SKILL_ID = "team-knowledge";

/** Create the team-knowledge skill for inclusion in new teams */
export function createTeamKnowledgeSkill(): Skill {
  return {
    id: TEAM_KNOWLEDGE_SKILL_ID,
    title: "Team Knowledge",
    description: "Auto-loads shared team knowledge into every session",
    alwaysApply: true,
    body: "Before starting work, read the team knowledge file for shared context from prior work sessions.\nBefore finishing, append any useful findings as a `## <topic>` entry (3-5 lines). Do not delete existing entries.",
  };
}

/** Enrich the team-knowledge skill body with the actual knowledge file path and content.
 *  Returns team unchanged if the skill is not present. */
export function enrichTeamKnowledgeSkill(
  team: TeamDefinition,
  knowledgePath: string,
  knowledgeContent: string,
): TeamDefinition {
  if (!team.skills) return team;
  const idx = team.skills.findIndex((s) => s.id === TEAM_KNOWLEDGE_SKILL_ID);
  if (idx === -1) return team;

  const skill = team.skills[idx];
  const baseBody = typeof skill.body === "string" ? skill.body : "";
  const parts = [baseBody, "", `**Knowledge file:** \`${knowledgePath}\``];
  if (knowledgeContent.trim()) {
    parts.push("", "---", "", knowledgeContent.trim());
  }

  const enrichedSkill = { ...skill, body: parts.join("\n") };
  const enrichedSkills = [...team.skills];
  enrichedSkills[idx] = enrichedSkill;

  return { ...team, skills: enrichedSkills };
}

/** IDs for built-in teamrc skills (prefixed with trc- by writeSkillDir) */
export const BUILTIN_SKILL_IDS = [
  "save-knowledge",
  "save-core",
  "knowledge",
  "status",
] as const;

/** Create built-in teamrc skills that get installed alongside every team.
 *  These are on-demand slash commands, not alwaysApply rules. */
export function createBuiltInSkills(knowledgePath: string): Skill[] {
  return [
    {
      id: "save-knowledge",
      title: "Save Knowledge",
      description: "Save a finding or decision to the team knowledge file so other team members and future sessions benefit from it",
      disableModelInvocation: true,
      argumentHint: "<topic> <details>",
      body: `Save a finding to the team knowledge file at \`${knowledgePath}\`.

1. Read the current knowledge file
2. Append a new \`## <topic>\` section at the end of the file with the provided details (3-5 lines)
3. If a section with the same heading already exists, append to that section instead of creating a duplicate
4. Write the updated file
5. Report the current file size and how close it is to the 100KB relay cap
6. If size > 90%, warn that oldest sections will be automatically pruned on next sync

Sections are pruned oldest-first (FIFO) when the file exceeds 100KB. The preamble (content before the first \`## \` heading) is never pruned.`,
    },
    {
      id: "save-core",
      title: "Save Core Knowledge",
      description: "Save permanent knowledge to the preamble section that is never pruned  --  use for test commands, architecture decisions, and key conventions",
      disableModelInvocation: true,
      argumentHint: "<details>",
      body: `Save permanent knowledge to the preamble of the team knowledge file at \`${knowledgePath}\`.

The preamble is everything before the first \`## \` heading. It is capped at 10KB and is **never pruned**  --  use it for essential, permanent information like:
- Test commands
- Architecture decisions
- Key conventions
- Important file paths

1. Read the current knowledge file
2. Add the provided information to the preamble (before the first \`## \` heading)
3. Keep the preamble concise  --  it should stay well under 10KB
4. Write the updated file
5. Report the current preamble size`,
    },
    {
      id: "knowledge",
      title: "Team Knowledge",
      description: "Display team knowledge contents, search for topics, and show size status. Use when you need to check what the team has documented or refresh knowledge mid-session.",
      argumentHint: "[search-term]",
      body: `Read and display the team knowledge file at \`${knowledgePath}\`.

1. Read the file
2. Display a summary:
   - Number of \`## \` sections
   - Total file size and percentage of 100KB relay cap
   - Preamble size
3. List all \`## \` headings
4. If arguments were provided, search sections for matching content and display matches in full
5. If size > 70% of cap, note that oldest sections will be pruned when cap is reached
6. If size > 90%, warn urgently`,
    },
    {
      id: "status",
      title: "Team Status",
      description: "Show current teamrc team status including members, skills, knowledge size, and sync info",
      disableModelInvocation: true,
      body: `Show the current teamrc team status.

1. Read \`.teamrc.yaml\` and display:
   - Team name and ID
   - Members (name and role)
   - Skills (name and whether alwaysApply)
2. Read the knowledge file at \`${knowledgePath}\` and display:
   - File path
   - Total size and percentage of 100KB cap
   - Preamble size
   - Number of sections
3. If size > 70% of cap, warn about upcoming pruning
4. If size > 90%, warn urgently`,
    },
  ];
}

/** Resolve skills for an agent. Returns explicitly assigned skills,
 *  plus alwaysApply team-level skills when includeAlwaysApply is set.
 *  Use includeAlwaysApply for platforms without native rule systems (Codex, Gemini, OpenClaw). */
export function resolveAgentSkills(
  agent: TeamMember,
  team: TeamDefinition,
  opts?: { includeAlwaysApply?: boolean },
): Skill[] {
  if (!team.skills) return [];
  const assigned = (agent.skills || [])
    .map((id) => team.skills!.find((s) => s.id === id))
    .filter((s): s is Skill => s !== undefined);
  if (!opts?.includeAlwaysApply) return assigned;
  const alwaysOn = team.skills.filter(
    (s) => s.alwaysApply && !assigned.some((a) => a.id === s.id),
  );
  return [...alwaysOn, ...assigned];
}

/** Collect all skill IDs from a team definition, including built-in skill IDs.
 *  Used to scope cleanupSkillDirs to only this team's skills. */
export function collectTeamSkillIds(team: TeamDefinition): string[] {
  const ids: string[] = [];
  if (team.skills) {
    for (const skill of team.skills) {
      ids.push(skill.id);
    }
  }
  for (const id of BUILTIN_SKILL_IDS) {
    ids.push(id);
  }
  return ids;
}

export function getAdapter(platform: string, teamSlug?: string): PlatformAdapter {
  const require = createRequire(import.meta.url);

  switch (platform) {
    case "claude-code": {
      const mod = require("./claude-code.js") as {
        ClaudeCodeAdapter: new (teamSlug?: string) => PlatformAdapter;
      };
      return new mod.ClaudeCodeAdapter(teamSlug);
    }
    case "openclaw": {
      const mod = require("./openclaw.js") as {
        OpenClawAdapter: new (teamSlug?: string) => PlatformAdapter;
      };
      return new mod.OpenClawAdapter(teamSlug);
    }
    case "cursor": {
      const mod = require("./cursor.js") as {
        CursorAdapter: new (teamSlug?: string) => PlatformAdapter;
      };
      return new mod.CursorAdapter(teamSlug);
    }
    case "codex": {
      const mod = require("./codex.js") as {
        CodexAdapter: new (teamSlug?: string) => PlatformAdapter;
      };
      return new mod.CodexAdapter(teamSlug);
    }
    case "gemini": {
      const mod = require("./gemini.js") as {
        GeminiAdapter: new (teamSlug?: string) => PlatformAdapter;
      };
      return new mod.GeminiAdapter(teamSlug);
    }
    case "copilot":
    case "amazon-q":
    case "windsurf":
    case "cline":
      throw new Error(`Platform "${platform}" adapter not yet implemented`);
    default:
      throw new Error(`Unknown platform: ${platform}`);
  }
}
