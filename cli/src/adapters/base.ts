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

export type PlatformName = (typeof VALID_PLATFORMS)[number];

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
  /** Remove everything teamrc installed for this platform. Returns list of actions taken. */
  uninstall(): string[];
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

/** Escape a string for use in YAML double-quoted values */
export function escapeYamlString(s: string): string {
  return s.replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, "\\n");
}

export function getAdapter(platform: string): PlatformAdapter {
  const require = createRequire(import.meta.url);

  switch (platform) {
    case "claude-code": {
      const mod = require("./claude-code.js") as {
        ClaudeCodeAdapter: new () => PlatformAdapter;
      };
      return new mod.ClaudeCodeAdapter();
    }
    case "openclaw": {
      const mod = require("./openclaw.js") as {
        OpenClawAdapter: new () => PlatformAdapter;
      };
      return new mod.OpenClawAdapter();
    }
    case "cursor": {
      const mod = require("./cursor.js") as {
        CursorAdapter: new () => PlatformAdapter;
      };
      return new mod.CursorAdapter();
    }
    case "codex": {
      const mod = require("./codex.js") as {
        CodexAdapter: new () => PlatformAdapter;
      };
      return new mod.CodexAdapter();
    }
    case "gemini": {
      const mod = require("./gemini.js") as {
        GeminiAdapter: new () => PlatformAdapter;
      };
      return new mod.GeminiAdapter();
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
