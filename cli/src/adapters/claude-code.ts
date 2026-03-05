import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";
import * as crypto from "node:crypto";
import type {
  PlatformAdapter,
  TeamDefinition,
  TeamMember,
} from "./base.js";

function hashContent(content: string): string {
  return crypto.createHash("sha256").update(content).digest("hex").slice(0, 16);
}

export class ClaudeCodeAdapter implements PlatformAdapter {
  private claudeDir: string;

  constructor() {
    this.claudeDir = path.join(os.homedir(), ".claude");
  }

  readTeam(): TeamDefinition | null {
    const teamsDir = path.join(this.claudeDir, "teams");
    if (!fs.existsSync(teamsDir)) {
      return null;
    }

    const teamDirs = fs.readdirSync(teamsDir).filter((d) => {
      const fullPath = path.join(teamsDir, d);
      return fs.statSync(fullPath).isDirectory();
    });

    if (teamDirs.length === 0) {
      return null;
    }

    const firstTeam = teamDirs[0]!;
    const configPath = path.join(teamsDir, firstTeam, "config.json");
    if (!fs.existsSync(configPath)) {
      return null;
    }

    try {
      const raw = fs.readFileSync(configPath, "utf-8");
      const parsed = JSON.parse(raw) as {
        name?: string;
        members?: TeamMember[];
      };
      return {
        name: parsed.name ?? firstTeam,
        members: parsed.members ?? [],
      };
    } catch {
      return null;
    }
  }

  writeTeam(team: TeamDefinition): void {
    const teamDir = path.join(this.claudeDir, "teams", team.name);
    if (!fs.existsSync(teamDir)) {
      fs.mkdirSync(teamDir, { recursive: true });
    }

    const configPath = path.join(teamDir, "config.json");
    fs.writeFileSync(
      configPath,
      JSON.stringify(
        { name: team.name, members: team.members },
        null,
        2,
      ),
    );

    // Append team section to CLAUDE.md if it exists in cwd
    const claudeMdPath = path.join(process.cwd(), "CLAUDE.md");
    if (fs.existsSync(claudeMdPath)) {
      const existing = fs.readFileSync(claudeMdPath, "utf-8");
      const teamSection = `\n\n## Team: ${team.name}\n\nMembers:\n${team.members.map((m) => `- **${m.name}** — ${m.role}`).join("\n")}\n`;
      if (!existing.includes(`## Team: ${team.name}`)) {
        fs.appendFileSync(claudeMdPath, teamSection);
      }
    }
  }

  readMemory(): string[] {
    const projectsDir = path.join(this.claudeDir, "projects");
    if (!fs.existsSync(projectsDir)) {
      return [];
    }

    const entries: string[] = [];
    const projectDirs = fs.readdirSync(projectsDir).filter((d) => {
      const fullPath = path.join(projectsDir, d);
      return fs.statSync(fullPath).isDirectory();
    });

    for (const projDir of projectDirs) {
      const memoryDir = path.join(projectsDir, projDir, "memory");
      if (!fs.existsSync(memoryDir)) {
        continue;
      }

      const mdFiles = fs
        .readdirSync(memoryDir)
        .filter((f) => f.endsWith(".md"));
      for (const mdFile of mdFiles) {
        const content = fs.readFileSync(
          path.join(memoryDir, mdFile),
          "utf-8",
        );
        if (content.trim()) {
          entries.push(content);
        }
      }
    }

    return entries;
  }

  writeMemory(entries: string[]): void {
    const projectsDir = path.join(this.claudeDir, "projects");
    if (!fs.existsSync(projectsDir)) {
      fs.mkdirSync(projectsDir, { recursive: true });
    }

    // Find first project dir or create one
    const projectDirs = fs.existsSync(projectsDir)
      ? fs.readdirSync(projectsDir).filter((d) => {
          const fullPath = path.join(projectsDir, d);
          return fs.statSync(fullPath).isDirectory();
        })
      : [];

    const targetProject =
      projectDirs.length > 0 ? projectDirs[0]! : "default";
    const memoryDir = path.join(projectsDir, targetProject, "memory");
    if (!fs.existsSync(memoryDir)) {
      fs.mkdirSync(memoryDir, { recursive: true });
    }

    const sharedPath = path.join(memoryDir, "teambridge-shared.md");
    const content = entries.join("\n\n---\n\n");
    fs.writeFileSync(sharedPath, content);
  }

  getHashes(): Record<string, string> {
    const hashes: Record<string, string> = {};

    // Hash team configs
    const teamsDir = path.join(this.claudeDir, "teams");
    if (fs.existsSync(teamsDir)) {
      const teamDirs = fs.readdirSync(teamsDir).filter((d) => {
        const fullPath = path.join(teamsDir, d);
        return fs.statSync(fullPath).isDirectory();
      });
      for (const teamDir of teamDirs) {
        const configPath = path.join(teamsDir, teamDir, "config.json");
        if (fs.existsSync(configPath)) {
          const content = fs.readFileSync(configPath, "utf-8");
          hashes[`team:${teamDir}`] = hashContent(content);
        }
      }
    }

    // Hash memory files
    const projectsDir = path.join(this.claudeDir, "projects");
    if (fs.existsSync(projectsDir)) {
      const projectDirs = fs.readdirSync(projectsDir).filter((d) => {
        const fullPath = path.join(projectsDir, d);
        return fs.statSync(fullPath).isDirectory();
      });
      for (const projDir of projectDirs) {
        const memoryDir = path.join(projectsDir, projDir, "memory");
        if (!fs.existsSync(memoryDir)) continue;
        const mdFiles = fs
          .readdirSync(memoryDir)
          .filter((f) => f.endsWith(".md"));
        for (const mdFile of mdFiles) {
          const filePath = path.join(memoryDir, mdFile);
          const content = fs.readFileSync(filePath, "utf-8");
          hashes[`memory:${projDir}/${mdFile}`] = hashContent(content);
        }
      }
    }

    return hashes;
  }

  installHooks(relay: string, token: string): void {
    const settingsPath = path.join(this.claudeDir, "settings.json");
    let settings: Record<string, unknown> = {};

    if (fs.existsSync(settingsPath)) {
      try {
        settings = JSON.parse(
          fs.readFileSync(settingsPath, "utf-8"),
        ) as Record<string, unknown>;
      } catch {
        // Start fresh if settings file is corrupted
      }
    }

    const hooks = (settings["hooks"] ?? {}) as Record<string, unknown>;
    const sessionStart = (hooks["SessionStart"] ?? []) as Array<{
      command: string;
    }>;

    const hookCommand = "npx teambridge sync 2>/dev/null || true";
    const alreadyInstalled = sessionStart.some(
      (h) => h.command === hookCommand,
    );

    if (!alreadyInstalled) {
      sessionStart.push({ command: hookCommand });
    }

    hooks["SessionStart"] = sessionStart;
    settings["hooks"] = hooks;

    if (!fs.existsSync(this.claudeDir)) {
      fs.mkdirSync(this.claudeDir, { recursive: true });
    }
    fs.writeFileSync(settingsPath, JSON.stringify(settings, null, 2));
  }
}
