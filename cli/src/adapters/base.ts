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
  body: string | { source: string };
}

export interface TeamMember {
  name: string;
  role: string;
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
  /** Remove everything teamrc installed for this platform. Returns list of actions taken.
   *  When scope is provided, only removes files for that scope. */
  uninstall(scope?: TeamScope): string[];
}

/** Write a native SKILL.md file for a skill in the given base directory */
export function writeSkillDir(baseDir: string, skill: Skill): void {
  if (typeof skill.body !== "string") return; // skip source-referenced skills
  const skillDir = path.join(baseDir, `trc-${skill.id}`);
  if (!fs.existsSync(skillDir)) fs.mkdirSync(skillDir, { recursive: true });

  const lines: string[] = ["---"];
  lines.push(`name: trc-${skill.id}`);
  if (skill.description) lines.push(`description: ${JSON.stringify(skill.description)}`);
  lines.push("---", "");
  lines.push(skill.body);

  fs.writeFileSync(path.join(skillDir, "SKILL.md"), lines.join("\n") + "\n");
}

/** Remove all trc-* skill directories under a base directory */
export function cleanupSkillDirs(baseDir: string): number {
  if (!fs.existsSync(baseDir)) return 0;
  const dirs = fs.readdirSync(baseDir).filter((d) => d.startsWith("trc-"));
  for (const d of dirs) {
    fs.rmSync(path.join(baseDir, d), { recursive: true, force: true });
  }
  return dirs.length;
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

/** Resolve agents directory — check project first, fall back to global */
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

/** Delete knowledge file(s) in a directory. When slug is the fallback "team",
 *  glob-deletes all knowledge-*.md to handle the case where the real slug is unknown.
 *  Otherwise deletes only the specific slug's file. Returns list of deleted paths. */
export function deleteKnowledgeFiles(dir: string, teamSlug: string): string[] {
  if (!fs.existsSync(dir)) return [];
  const deleted: string[] = [];
  if (teamSlug === "team") {
    // Slug unknown (e.g., YAML already deleted) — clean up all knowledge files
    const files = fs.readdirSync(dir).filter((f) => f.startsWith("knowledge-") && f.endsWith(".md"));
    for (const f of files) {
      const full = path.join(dir, f);
      fs.unlinkSync(full);
      deleted.push(full);
    }
  } else {
    const full = path.join(dir, knowledgeFileName(teamSlug));
    if (fs.existsSync(full)) {
      fs.unlinkSync(full);
      deleted.push(full);
    }
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

/** Resolve skills for an agent. Only returns explicitly assigned skills. */
export function resolveAgentSkills(agent: TeamMember, team: TeamDefinition): Skill[] {
  if (!agent.skills || agent.skills.length === 0 || !team.skills) return [];
  return agent.skills
    .map((id) => team.skills!.find((s) => s.id === id))
    .filter((s): s is Skill => s !== undefined);
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
