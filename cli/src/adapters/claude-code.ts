import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";
import { parse as parseYaml } from "yaml";
import {
  hashContent,
  validateAgentName,
  type PlatformAdapter,
  type PortableAgent,
  type TeamDefinition,
  type TeamMember,
  type TeamScope,
} from "./base.js";

export class ClaudeCodeAdapter implements PlatformAdapter {
  private claudeDir: string;

  constructor() {
    this.claudeDir = path.join(os.homedir(), ".claude");
  }

  private agentsDir(scope: TeamScope): string {
    if (scope === "project") {
      return path.join(process.cwd(), ".claude", "agents");
    }
    return path.join(this.claudeDir, "agents");
  }

  /** Find the agents directory — check project first, fall back to global */
  private resolveAgentsDir(): { dir: string; scope: TeamScope } {
    const projectDir = this.agentsDir("project");
    if (fs.existsSync(projectDir)) {
      const tbFiles = this.listTbFiles(projectDir);
      if (tbFiles.length > 0) {
        return { dir: projectDir, scope: "project" };
      }
    }
    const globalDir = this.agentsDir("global");
    return { dir: globalDir, scope: "global" };
  }

  private listTbFiles(dir: string): string[] {
    if (!fs.existsSync(dir)) return [];
    return fs.readdirSync(dir).filter((f) => f.startsWith("tb-") && f.endsWith(".md"));
  }

  readTeam(): TeamDefinition | null {
    const { dir } = this.resolveAgentsDir();
    const files = this.listTbFiles(dir);
    if (files.length === 0) return null;

    let teamName = "my-team";
    const members: TeamMember[] = [];

    for (const file of files) {
      const content = fs.readFileSync(path.join(dir, file), "utf-8");
      const parsed = parseAgentFile(content);
      if (!parsed) continue;
      if (parsed.teamName) teamName = parsed.teamName;
      members.push({
        name: parsed.agentName,
        role: parsed.role,
        ...(parsed.soul ? { soul: parsed.soul } : {}),
      });
    }

    return members.length > 0 ? { name: teamName, members } : null;
  }

  writeTeam(team: TeamDefinition, scope: TeamScope = "global"): void {
    const dir = this.agentsDir(scope);
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true });
    }

    for (const member of team.members) {
      const fileName = `tb-${slugify(member.name)}.md`;
      const filePath = path.join(dir, fileName);
      const content = buildAgentFile(team.name, member, team.members);
      fs.writeFileSync(filePath, content);
    }

    this.updateClaudeMd(team, scope);
  }

  private updateClaudeMd(team: TeamDefinition, scope: TeamScope): void {
    const teamSection = buildClaudeMdSection(team);

    if (scope === "project") {
      const claudeMdPath = path.join(process.cwd(), "CLAUDE.md");
      if (!fs.existsSync(claudeMdPath)) {
        fs.writeFileSync(claudeMdPath, `# Project Configuration\n${teamSection}`);
      } else {
        const existing = fs.readFileSync(claudeMdPath, "utf-8");
        const cleaned = existing.replace(
          /\n## TeamBridge Team: .+?(?=\n## |\n# |$)/s,
          "",
        );
        fs.writeFileSync(claudeMdPath, cleaned.trimEnd() + "\n" + teamSection);
      }
    }
  }

  private knowledgePath(scope: TeamScope = "project"): string {
    if (scope === "project") {
      return path.join(process.cwd(), ".claude", "team-knowledge.md");
    }
    return path.join(this.claudeDir, "team-knowledge.md");
  }

  readKnowledge(): string {
    for (const scope of ["project", "global"] as TeamScope[]) {
      const filePath = this.knowledgePath(scope);
      if (fs.existsSync(filePath)) {
        return fs.readFileSync(filePath, "utf-8");
      }
    }
    return "";
  }

  writeKnowledge(content: string): void {
    const filePath = this.knowledgePath("project");
    const dir = path.dirname(filePath);
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true });
    }
    fs.writeFileSync(filePath, content);
  }

  appendKnowledge(entries: string[]): void {
    if (entries.length === 0) return;

    const filePath = this.knowledgePath("project");
    const dir = path.dirname(filePath);
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true });
    }

    const newContent = entries
      .map((e) => `- ${new Date().toISOString().slice(0, 10)}: ${e}`)
      .join("\n");

    if (fs.existsSync(filePath)) {
      fs.appendFileSync(filePath, "\n" + newContent + "\n");
    } else {
      fs.writeFileSync(
        filePath,
        `# Team Knowledge\n\nShared findings and decisions synced by TeamBridge. Do not edit manually.\n\n${newContent}\n`,
      );
    }
  }

  getHashes(): Record<string, string> {
    const hashes: Record<string, string> = {};

    // Hash each agent file as portable JSON
    const { dir } = this.resolveAgentsDir();
    for (const file of this.listTbFiles(dir)) {
      const content = fs.readFileSync(path.join(dir, file), "utf-8");
      const parsed = parseAgentFile(content);
      if (!parsed) continue;
      const portable = toPortableJson(parsed);
      hashes[`agent:${parsed.agentName}`] = hashContent(portable);
    }

    // Hash team knowledge file
    for (const scope of ["project", "global"] as TeamScope[]) {
      const kPath = this.knowledgePath(scope);
      if (fs.existsSync(kPath)) {
        const content = fs.readFileSync(kPath, "utf-8");
        hashes[`knowledge:${scope}`] = hashContent(content);
      }
    }

    return hashes;
  }

  watchPaths(): string[] {
    const paths = [
      this.knowledgePath("project"),
      this.knowledgePath("global"),
    ];
    // Watch both possible agent directories
    const projectAgents = this.agentsDir("project");
    const globalAgents = this.agentsDir("global");
    if (fs.existsSync(projectAgents)) paths.push(projectAgents);
    if (fs.existsSync(globalAgents)) paths.push(globalAgents);
    return paths;
  }

  writeFile(key: string, content: string): void {
    if (key.startsWith("agent:")) {
      this.writeAgentFromPortable(key, content);
      return;
    }
    if (key === "knowledge:project") {
      this.writeKnowledge(content);
      return;
    }
    if (key === "knowledge:global") {
      const dir = path.dirname(this.knowledgePath("global"));
      if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
      fs.writeFileSync(this.knowledgePath("global"), content);
      return;
    }
  }

  readFile(key: string): string | null {
    if (key.startsWith("agent:")) {
      return this.readAgentAsPortable(key);
    }
    if (key === "knowledge:project") {
      const p = this.knowledgePath("project");
      return fs.existsSync(p) ? fs.readFileSync(p, "utf-8") : null;
    }
    if (key === "knowledge:global") {
      const p = this.knowledgePath("global");
      return fs.existsSync(p) ? fs.readFileSync(p, "utf-8") : null;
    }
    return null;
  }

  /** Read a native agent file and return portable JSON */
  private readAgentAsPortable(key: string): string | null {
    const agentName = key.replace("agent:", "");
    const { dir } = this.resolveAgentsDir();
    const filePath = path.join(dir, `tb-${slugify(agentName)}.md`);
    if (!fs.existsSync(filePath)) return null;

    const content = fs.readFileSync(filePath, "utf-8");
    const parsed = parseAgentFile(content);
    if (!parsed) return null;
    return toPortableJson(parsed);
  }

  /** Write a native agent file from portable JSON */
  private writeAgentFromPortable(key: string, json: string): void {
    const portable = JSON.parse(json) as PortableAgent;
    validateAgentName(portable.name);
    const { dir } = this.resolveAgentsDir();
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });

    // Read existing team to get full member list for teammates section
    const team = this.readTeam();
    const allMembers: TeamMember[] = team?.members ?? [];

    // Update or add this member
    const idx = allMembers.findIndex((m) => m.name === portable.name);
    const member: TeamMember = { name: portable.name, role: portable.role, soul: portable.soul };
    if (idx >= 0) {
      allMembers[idx] = member;
    } else {
      allMembers.push(member);
    }

    const filePath = path.join(dir, `tb-${slugify(portable.name)}.md`);
    const content = buildAgentFile(portable.teamName, member, allMembers);
    fs.writeFileSync(filePath, content);
  }

  uninstall(): string[] {
    const actions: string[] = [];
    const { dir, scope } = this.resolveAgentsDir();
    const tbFiles = this.listTbFiles(dir);

    // Delete agent files
    for (const f of tbFiles) {
      fs.unlinkSync(path.join(dir, f));
    }
    if (tbFiles.length > 0) {
      actions.push(`Deleted ${tbFiles.length} agent file(s) from ${dir}`);
    }

    // Delete team knowledge
    for (const s of ["project", "global"] as TeamScope[]) {
      const kPath = this.knowledgePath(s);
      if (fs.existsSync(kPath)) {
        fs.unlinkSync(kPath);
        actions.push(`Deleted ${kPath}`);
      }
    }

    // Remove TeamBridge section from CLAUDE.md
    if (scope === "project") {
      const claudeMdPath = path.join(process.cwd(), "CLAUDE.md");
      if (fs.existsSync(claudeMdPath)) {
        const content = fs.readFileSync(claudeMdPath, "utf-8");
        const cleaned = content.replace(
          /\n## TeamBridge Team: .+?(?=\n## |\n# |$)/s,
          "",
        );
        if (cleaned !== content) {
          fs.writeFileSync(claudeMdPath, cleaned.trimEnd() + "\n");
          actions.push(`Removed TeamBridge section from ${claudeMdPath}`);
        }
      }
    }

    // Remove hook from settings.json
    const settingsPath = path.join(this.claudeDir, "settings.json");
    if (fs.existsSync(settingsPath)) {
      try {
        const settings = JSON.parse(fs.readFileSync(settingsPath, "utf-8")) as Record<string, unknown>;
        const hooks = (settings["hooks"] ?? {}) as Record<string, unknown>;
        const sessionStart = (hooks["SessionStart"] ?? []) as Array<{ command: string }>;
        const filtered = sessionStart.filter((h) => !h.command.includes("teambridge"));
        if (filtered.length !== sessionStart.length) {
          hooks["SessionStart"] = filtered;
          settings["hooks"] = hooks;
          fs.writeFileSync(settingsPath, JSON.stringify(settings, null, 2));
          actions.push(`Removed TeamBridge hook from ${settingsPath}`);
        }
      } catch {
        // Leave settings alone if we can't parse them
      }
    }

    return actions;
  }

  installHooks(relay: string, _token: string): void {
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

// --- Helpers ---

function slugify(name: string): string {
  return name
    .toLowerCase()
    .replace(/[^a-z0-9-]/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "");
}

interface ParsedAgent {
  agentName: string;
  role: string;
  soul?: string;
  teamName: string;
}

/** Parse a tb-*.md agent file back into structured data */
function parseAgentFile(content: string): ParsedAgent | null {
  const match = content.match(/^---\n([\s\S]*?)\n---\n([\s\S]*)$/);
  if (!match) return null;

  let frontmatter: Record<string, unknown>;
  try {
    frontmatter = parseYaml(match[1]) as Record<string, unknown>;
  } catch {
    return null;
  }

  const name = String(frontmatter.name ?? "");
  const description = String(frontmatter.description ?? "");
  const body = match[2].trim();

  // Extract agent name: strip tb- prefix
  const agentName = name.startsWith("tb-") ? name.slice(3) : name;

  // Extract role from description: "Role on the teamName team. Use when..."
  const roleMatch = description.match(/^(.+?)\s+on the\s+/);
  const role = roleMatch ? roleMatch[1] : description;

  // Extract team name from body: "# Team: teamName"
  const teamMatch = body.match(/^# Team:\s*(.+)$/m);
  const teamName = teamMatch ? teamMatch[1].trim() : "my-team";

  // Extract soul: everything between the team header and ## Teammates (or end)
  const bodyAfterHeader = body.replace(/^# Team:.*\n+/, "");
  const teammatesIdx = bodyAfterHeader.indexOf("## Teammates");
  const soulRaw = teammatesIdx >= 0
    ? bodyAfterHeader.slice(0, teammatesIdx).trim()
    : bodyAfterHeader.trim();

  // Only set soul if it's not the default generated text
  const isDefault = soulRaw.startsWith(`You are ${agentName},`);
  const soul = isDefault ? undefined : soulRaw || undefined;

  return { agentName, role, soul, teamName };
}

/** Convert parsed agent to portable JSON string (wire format) */
function toPortableJson(parsed: ParsedAgent): string {
  const obj: PortableAgent = {
    name: parsed.agentName,
    role: parsed.role,
    teamName: parsed.teamName,
    ...(parsed.soul ? { soul: parsed.soul } : {}),
  };
  return JSON.stringify(obj);
}

function buildAgentFile(teamName: string, member: TeamMember, allMembers: TeamMember[]): string {
  const name = `tb-${slugify(member.name)}`;
  const body = member.soul
    ? member.soul
    : `You are ${member.name}, a ${member.role} on the ${teamName} team.\n\nFocus on your role and collaborate with your teammates.`;

  const teammates = allMembers
    .filter((m) => m.name !== member.name)
    .map((m) => `- **${m.name}** — ${m.role}`)
    .join("\n");

  return `---
name: ${name}
description: "${member.role} on the ${teamName} team. Use when tasks relate to ${member.role.toLowerCase()}."
model: inherit
---

# Team: ${teamName}

${body}

## Teammates

${teammates}

## Team Knowledge

Shared findings and decisions are stored in \`.claude/team-knowledge.md\`. Read this file at the start of every session for context from other agents and machines. When you discover something important, append it to that file.
`;
}

function buildClaudeMdSection(team: TeamDefinition): string {
  const memberLines = team.members
    .map((m) => `- **${m.name}** — ${m.role}`)
    .join("\n");

  return `
## TeamBridge Team: ${team.name}

This project has a synced agent team managed by TeamBridge.

Members:
${memberLines}

Each member is defined as a subagent in \`.claude/agents/\`. Delegate tasks to them based on their roles.

### Team Knowledge
Shared findings and decisions are stored in \`.claude/team-knowledge.md\`. Read this file at the start of every session for context from other agents and machines. When you discover something important (architecture decisions, gotchas, debugging insights), append it to this file so other team members can benefit.
`;
}
