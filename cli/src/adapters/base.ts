import * as crypto from "node:crypto";
import * as fs from "node:fs";
import { createRequire } from "node:module";
import * as path from "node:path";

export function hashContent(content: string): string {
  return crypto.createHash("sha256").update(content).digest("hex").slice(0, 16);
}

/** Validate that an agent name is safe for use in file paths */
export function validateAgentName(name: string): void {
  if (!/^[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}$/.test(name)) {
    throw new Error(`Invalid agent name: ${JSON.stringify(name)}`);
  }
}

/** Portable agent representation — the wire format sent to/from relay */
export interface PortableAgent {
  name: string;
  role: string;
  soul?: string;
  teamName: string;
}

export interface Rule {
  id: string;
  title?: string;
  globs?: string[];
  alwaysApply?: boolean;
  body: string | { source: string };
}

export interface Skill {
  id: string;
  title?: string;
  description?: string;
  body?: string | { source: string };
}

export interface TeamMember {
  name: string;
  role: string;
  soul?: string;
  rules?: string[];   // references Rule.id
  skills?: string[];  // references Skill.id
}

export interface TeamDefinition {
  name: string;
  members: TeamMember[];
  rules?: Rule[];
  skills?: Skill[];
}

export type TeamScope = "project" | "global";

/** Strip HTML comment sequences to prevent marker injection */
export function sanitizeMarkerContent(s: string): string {
  return s.replace(/<!--/g, "").replace(/-->/g, "");
}

export interface PlatformAdapter {
  readTeam(): TeamDefinition | null;
  writeTeam(team: TeamDefinition, scope?: TeamScope): void;
  readKnowledge(): string;
  writeKnowledge(content: string): void;
  appendKnowledge(entries: string[]): void;
  getHashes(): Record<string, string>;
  installHooks(relay: string, token: string): void;
  watchPaths(): string[];
  writeFile(key: string, content: string): void;
  readFile(key: string): string | null;
  /** Remove everything TeamBridge installed for this platform. Returns list of actions taken. */
  uninstall(): string[];
}

/** Write a native SKILL.md file for a skill in the given base directory */
export function writeSkillDir(baseDir: string, skill: Skill): void {
  if (skill.body && typeof skill.body !== "string") return; // skip source-referenced skills
  const skillDir = path.join(baseDir, `tb-${skill.id}`);
  if (!fs.existsSync(skillDir)) fs.mkdirSync(skillDir, { recursive: true });

  const lines: string[] = ["---"];
  lines.push(`name: tb-${skill.id}`);
  if (skill.description) lines.push(`description: ${JSON.stringify(skill.description)}`);
  lines.push("---", "");
  if (skill.body && typeof skill.body === "string") lines.push(skill.body);

  fs.writeFileSync(path.join(skillDir, "SKILL.md"), lines.join("\n") + "\n");
}

/** Remove all tb-* skill directories under a base directory */
export function cleanupSkillDirs(baseDir: string): number {
  if (!fs.existsSync(baseDir)) return 0;
  const dirs = fs.readdirSync(baseDir).filter((d) => d.startsWith("tb-"));
  for (const d of dirs) {
    fs.rmSync(path.join(baseDir, d), { recursive: true, force: true });
  }
  return dirs.length;
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
    default:
      throw new Error(`Unknown platform: ${platform}`);
  }
}
