import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";
import * as crypto from "node:crypto";
import { execFileSync } from "node:child_process";
import type {
  PlatformAdapter,
  TeamDefinition,
  TeamMember,
} from "./base.js";

function hashContent(content: string): string {
  return crypto.createHash("sha256").update(content).digest("hex").slice(0, 16);
}

export class OpenClawAdapter implements PlatformAdapter {
  private openclawDir: string;

  constructor() {
    this.openclawDir = path.join(os.homedir(), ".openclaw");
  }

  readTeam(): TeamDefinition | null {
    const agentsDir = path.join(this.openclawDir, "agents");
    if (!fs.existsSync(agentsDir)) {
      return null;
    }

    const agentDirs = fs.readdirSync(agentsDir).filter((d) => {
      const fullPath = path.join(agentsDir, d);
      return fs.statSync(fullPath).isDirectory();
    });

    if (agentDirs.length === 0) {
      return null;
    }

    const members: TeamMember[] = [];
    for (const agentDir of agentDirs) {
      const soulPath = path.join(agentsDir, agentDir, "SOUL.md");
      let role = "agent";
      if (fs.existsSync(soulPath)) {
        const content = fs.readFileSync(soulPath, "utf-8");
        // Extract role from first line or heading
        const firstLine = content.split("\n")[0] ?? "";
        const roleMatch = firstLine.match(/^#\s*(.+)/);
        if (roleMatch) {
          role = roleMatch[1]!.trim();
        }
      }
      members.push({ name: agentDir, role });
    }

    return {
      name: "openclaw-team",
      members,
    };
  }

  writeTeam(team: TeamDefinition): void {
    const workspaceAgentsDir = path.join(
      this.openclawDir,
      "workspace",
      "agents",
    );

    for (const member of team.members) {
      const agentDir = path.join(workspaceAgentsDir, member.name);
      if (!fs.existsSync(agentDir)) {
        fs.mkdirSync(agentDir, { recursive: true });
      }

      // Write SOUL.md
      const soulPath = path.join(agentDir, "SOUL.md");
      const soulContent = `# ${member.role}\n\nAgent: ${member.name}\nRole: ${member.role}\n`;
      fs.writeFileSync(soulPath, soulContent);

      // Write AGENTS.md with full team info
      const agentsPath = path.join(agentDir, "AGENTS.md");
      const agentsContent = `# Team: ${team.name}\n\n${team.members.map((m) => `- **${m.name}** — ${m.role}`).join("\n")}\n`;
      fs.writeFileSync(agentsPath, agentsContent);

      // Register agent via openclaw CLI
      try {
        execFileSync("openclaw", ["agents", "add", member.name], {
          stdio: "ignore",
        });
      } catch {
        // openclaw CLI may not be available; continue silently
      }
    }
  }

  readMemory(): string[] {
    const memoryPath = path.join(
      this.openclawDir,
      "workspace",
      "MEMORY.md",
    );
    if (!fs.existsSync(memoryPath)) {
      return [];
    }

    const content = fs.readFileSync(memoryPath, "utf-8");
    if (!content.trim()) {
      return [];
    }
    return [content];
  }

  writeMemory(entries: string[]): void {
    const workspaceDir = path.join(this.openclawDir, "workspace");
    if (!fs.existsSync(workspaceDir)) {
      fs.mkdirSync(workspaceDir, { recursive: true });
    }

    const memoryPath = path.join(workspaceDir, "MEMORY.md");
    const newContent = entries.join("\n\n---\n\n");

    if (fs.existsSync(memoryPath)) {
      fs.appendFileSync(memoryPath, "\n\n---\n\n" + newContent);
    } else {
      fs.writeFileSync(memoryPath, newContent);
    }
  }

  getHashes(): Record<string, string> {
    const hashes: Record<string, string> = {};

    // Hash MEMORY.md
    const memoryPath = path.join(
      this.openclawDir,
      "workspace",
      "MEMORY.md",
    );
    if (fs.existsSync(memoryPath)) {
      const content = fs.readFileSync(memoryPath, "utf-8");
      hashes["memory:MEMORY.md"] = hashContent(content);
    }

    // Hash agent SOUL.md files
    const agentsDir = path.join(this.openclawDir, "agents");
    if (fs.existsSync(agentsDir)) {
      const agentDirs = fs.readdirSync(agentsDir).filter((d) => {
        const fullPath = path.join(agentsDir, d);
        return fs.statSync(fullPath).isDirectory();
      });
      for (const agentDir of agentDirs) {
        const soulPath = path.join(agentsDir, agentDir, "SOUL.md");
        if (fs.existsSync(soulPath)) {
          const content = fs.readFileSync(soulPath, "utf-8");
          hashes[`agent:${agentDir}/SOUL.md`] = hashContent(content);
        }
      }
    }

    return hashes;
  }

  installHooks(relay: string, token: string): void {
    const hookDir = path.join(
      this.openclawDir,
      "hooks",
      "teambridge-sync",
    );
    if (!fs.existsSync(hookDir)) {
      fs.mkdirSync(hookDir, { recursive: true });
    }

    const hookPath = path.join(hookDir, "index.ts");
    const hookContent = `// TeamBridge sync hook for OpenClaw
// Runs on session start to sync team state

import { execFileSync } from "node:child_process";

export default function teambridgeSync() {
  try {
    execFileSync("npx", ["teambridge", "sync"], {
      stdio: "ignore",
      env: {
        ...process.env,
        TEAMBRIDGE_RELAY: "${relay}",
      },
    });
  } catch {
    // Sync failures are non-fatal
  }
}
`;
    fs.writeFileSync(hookPath, hookContent);

    // Enable the hook in OpenClaw config
    const configPath = path.join(this.openclawDir, "config.json");
    let config: Record<string, unknown> = {};
    if (fs.existsSync(configPath)) {
      try {
        config = JSON.parse(
          fs.readFileSync(configPath, "utf-8"),
        ) as Record<string, unknown>;
      } catch {
        // Start fresh
      }
    }

    const hooks = (config["hooks"] ?? []) as string[];
    if (!hooks.includes("teambridge-sync")) {
      hooks.push("teambridge-sync");
    }
    config["hooks"] = hooks;
    fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
  }
}
