import * as crypto from "node:crypto";
import { createRequire } from "node:module";

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
    default:
      throw new Error(`Unknown platform: ${platform}`);
  }
}
