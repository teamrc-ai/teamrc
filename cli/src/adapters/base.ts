import { createRequire } from "node:module";

export interface TeamMember {
  name: string;
  role: string;
}

export interface TeamDefinition {
  name: string;
  members: TeamMember[];
}

export interface PlatformAdapter {
  readTeam(): TeamDefinition | null;
  writeTeam(team: TeamDefinition): void;
  readMemory(): string[];
  writeMemory(entries: string[]): void;
  getHashes(): Record<string, string>;
  installHooks(relay: string, token: string): void;
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
