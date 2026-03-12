import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";
import {
  validateAgentName,
  sanitizeText,
  slugify,
  writeSkillDir,
  cleanupSkillDirs,
  resolveAgentSkills,
  type FileAction,
  type PlatformAdapter,
  type TeamDefinition,
  type TeamMember,
  type TeamScope,
} from "./base.js";

/**
 * OpenClaw file-based agent adapter.
 *
 * Each team member becomes a Markdown file with YAML frontmatter at
 * ~/.openclaw/agents/trc-<slug>.md — OpenHands auto-discovers these for
 * delegation, so agents can call each other without explicit allowlists.
 *
 * Skills:     ~/.openclaw/skills/trc-<id>/SKILL.md
 * Config:     ~/.openclaw/openclaw.json (agent registry)
 * Knowledge:  ~/.openclaw/teamrc-knowledge.md
 */
export class OpenClawAdapter implements PlatformAdapter {
  private openclawDir(): string {
    return path.join(os.homedir(), ".openclaw");
  }

  private configPath(): string {
    return path.join(this.openclawDir(), "openclaw.json");
  }

  private agentsDir(): string {
    return path.join(this.openclawDir(), "agents");
  }

  private agentFilePath(slug: string): string {
    return path.join(this.agentsDir(), `${slug}.md`);
  }

  private sharedSkillsDir(): string {
    return path.join(this.openclawDir(), "skills");
  }

  readTeam(): TeamDefinition | null {
    const agentsDir = this.agentsDir();
    if (!fs.existsSync(agentsDir)) return null;

    const agentFiles = fs.readdirSync(agentsDir)
      .filter((f) => f.startsWith("trc-") && f.endsWith(".md"));

    if (agentFiles.length === 0) return null;

    let teamName = "my-team";
    const members: TeamMember[] = [];

    for (const file of agentFiles) {
      const content = fs.readFileSync(path.join(agentsDir, file), "utf-8");
      const parsed = parseAgentFile(content);

      const slug = file.replace(/\.md$/, "");
      const name = slug.slice(4); // strip "trc-"

      members.push({
        name,
        role: parsed.role || "Agent",
        ...(parsed.soul ? { soul: parsed.soul } : {}),
      });

      if (parsed.teamName) teamName = parsed.teamName;
    }

    return members.length > 0 ? { name: teamName, members } : null;
  }

  planWrite(team: TeamDefinition, _scope: TeamScope = "global"): FileAction[] {
    const actions: FileAction[] = [];

    for (const member of team.members) {
      validateAgentName(member.name);
      const slug = `trc-${slugify(member.name)}`;
      const filePath = this.agentFilePath(slug);

      actions.push({
        type: fs.existsSync(filePath) ? "update" : "create",
        path: filePath,
        description: `agent: ${member.name}`,
      });
    }

    // Skill directories
    const sharedDir = this.sharedSkillsDir();
    const existingSkillDirs = new Set(
      fs.existsSync(sharedDir) ? fs.readdirSync(sharedDir).filter((f) => f.startsWith("trc-")) : [],
    );
    const newSkillDirs = new Set<string>();
    if (team.skills) {
      for (const skill of team.skills) {
        if (typeof skill.body !== "string") continue;
        const dirName = `trc-${skill.id}`;
        newSkillDirs.add(dirName);
        actions.push({
          type: existingSkillDirs.has(dirName) ? "update" : "create",
          path: path.join(sharedDir, dirName, "SKILL.md"),
          description: `skill: ${skill.id}`,
        });
      }
    }
    for (const d of existingSkillDirs) {
      if (!newSkillDirs.has(d)) actions.push({ type: "delete", path: path.join(sharedDir, d) });
    }

    // openclaw.json
    actions.push({
      type: fs.existsSync(this.configPath()) ? "update" : "create",
      path: this.configPath(),
      description: "agent registration",
    });

    return actions;
  }

  writeTeam(team: TeamDefinition, _scope: TeamScope = "global"): void {
    const agentsDir = this.agentsDir();
    if (!fs.existsSync(agentsDir)) {
      fs.mkdirSync(agentsDir, { recursive: true });
    }

    // Write per-agent .md files
    for (const member of team.members) {
      validateAgentName(member.name);
      const slug = `trc-${slugify(member.name)}`;

      fs.writeFileSync(
        this.agentFilePath(slug),
        buildAgentFile(team.name, member, team.members, team),
      );
    }

    // Clean up stale agent files
    const validSlugs = new Set(team.members.map((m) => `trc-${slugify(m.name)}`));
    const existingFiles = fs.readdirSync(agentsDir)
      .filter((f) => f.startsWith("trc-") && f.endsWith(".md"));
    for (const file of existingFiles) {
      const slug = file.replace(/\.md$/, "");
      if (!validSlugs.has(slug)) {
        fs.unlinkSync(path.join(agentsDir, file));
      }
    }

    // Clean up legacy workspace dirs
    const openclawDir = this.openclawDir();
    if (fs.existsSync(openclawDir)) {
      for (const entry of fs.readdirSync(openclawDir)) {
        if (entry.startsWith("workspace-trc-")) {
          fs.rmSync(path.join(openclawDir, entry), { recursive: true, force: true });
        }
      }
    }

    // Write skills to ~/.openclaw/skills/
    const sharedDir = this.sharedSkillsDir();
    cleanupSkillDirs(sharedDir);
    if (team.skills) {
      if (!fs.existsSync(sharedDir)) {
        fs.mkdirSync(sharedDir, { recursive: true });
      }
      for (const skill of team.skills) {
        writeSkillDir(sharedDir, skill);
      }
    }

    // Register agents in openclaw.json
    this.writeAgentsConfig(team);
  }

  private readConfig(): Record<string, unknown> | null {
    const configPath = this.configPath();
    if (!fs.existsSync(configPath)) return null;
    try {
      return JSON.parse(fs.readFileSync(configPath, "utf-8")) as Record<string, unknown>;
    } catch {
      return null;
    }
  }

  private writeAgentsConfig(team: TeamDefinition): void {
    const configPath = this.configPath();
    const configDir = path.dirname(configPath);
    if (!fs.existsSync(configDir)) {
      fs.mkdirSync(configDir, { recursive: true });
    }

    let config = this.readConfig() ?? {};

    const trcEntries: AgentEntry[] = team.members.map((m) => {
      const slug = `trc-${slugify(m.name)}`;
      return {
        id: slug,
        name: sanitizeText(m.name),
      };
    });

    // Preserve non-trc entries
    const agents = (config.agents ?? {}) as Record<string, unknown>;
    const existingList = (agents.list ?? []) as AgentEntry[];
    const nonTrcEntries = existingList.filter((a) => !a.id?.startsWith("trc-"));

    // Set first trc agent as default if no other default exists
    const hasDefault = nonTrcEntries.some((a) => a.default);
    if (!hasDefault && trcEntries.length > 0) {
      trcEntries[0].default = true;
    }

    config = {
      ...config,
      agents: {
        ...agents,
        list: [...nonTrcEntries, ...trcEntries],
      },
    };

    fs.writeFileSync(configPath, JSON.stringify(config, null, 2) + "\n");
  }

  private knowledgePath(): string {
    return path.join(this.openclawDir(), "teamrc-knowledge.md");
  }

  readKnowledge(): string {
    const filePath = this.knowledgePath();
    if (fs.existsSync(filePath)) {
      return fs.readFileSync(filePath, "utf-8");
    }
    return "";
  }

  writeKnowledge(content: string): void {
    const filePath = this.knowledgePath();
    const dir = path.dirname(filePath);
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true });
    }
    fs.writeFileSync(filePath, content);
  }

  uninstall(): string[] {
    const actions: string[] = [];
    const agentsDir = this.agentsDir();

    // Delete trc-*.md agent files
    if (fs.existsSync(agentsDir)) {
      const agentFiles = fs.readdirSync(agentsDir)
        .filter((f) => f.startsWith("trc-") && f.endsWith(".md"));
      for (const file of agentFiles) {
        fs.unlinkSync(path.join(agentsDir, file));
        actions.push(`Deleted agent file ${file}`);
      }

      // Delete legacy agent state subdirs
      const agentDirs = fs.readdirSync(agentsDir)
        .filter((f) => f.startsWith("trc-") && fs.statSync(path.join(agentsDir, f)).isDirectory());
      for (const dir of agentDirs) {
        fs.rmSync(path.join(agentsDir, dir), { recursive: true, force: true });
        actions.push(`Deleted agent dir ${dir}`);
      }
    }

    // Delete legacy workspace dirs
    const openclawDir = this.openclawDir();
    if (fs.existsSync(openclawDir)) {
      for (const entry of fs.readdirSync(openclawDir)) {
        if (entry.startsWith("workspace-trc-")) {
          fs.rmSync(path.join(openclawDir, entry), { recursive: true, force: true });
          actions.push(`Deleted legacy workspace ${entry}`);
        }
      }
    }

    // Remove trc- skill directories
    const sharedDir = this.sharedSkillsDir();
    const skillCount = cleanupSkillDirs(sharedDir);
    if (skillCount > 0) {
      actions.push(`Deleted ${skillCount} shared skill directory(ies) from ${sharedDir}`);
    }

    // Remove trc- entries from openclaw.json
    const config = this.readConfig();
    if (config) {
      const agents = (config.agents as Record<string, unknown>)?.list as AgentEntry[] | undefined;
      if (agents) {
        const nonTrcEntries = agents.filter((a) => !a.id?.startsWith("trc-"));
        const removedCount = agents.length - nonTrcEntries.length;
        if (removedCount > 0) {
          const agentsObj = (config.agents ?? {}) as Record<string, unknown>;
          const updated = { ...config, agents: { ...agentsObj, list: nonTrcEntries } };
          fs.writeFileSync(this.configPath(), JSON.stringify(updated, null, 2) + "\n");
          actions.push(`Removed ${removedCount} agent(s) from openclaw.json`);
        }
      }
    }

    // Delete team knowledge
    const kPath = this.knowledgePath();
    if (fs.existsSync(kPath)) {
      fs.unlinkSync(kPath);
      actions.push(`Deleted ${kPath}`);
    }

    return actions;
  }
}

// --- Types ---

interface AgentEntry {
  id: string;
  name?: string;
  workspace?: string;
  agentDir?: string;
  default?: boolean;
  [key: string]: unknown;
}

// --- Helpers ---

function buildAgentFile(
  teamName: string,
  member: TeamMember,
  allMembers: TeamMember[],
  team: TeamDefinition,
): string {
  const safeTeamName = sanitizeText(teamName);
  const safeName = sanitizeText(member.name);
  const safeRole = sanitizeText(member.role);

  const lines: string[] = [];

  // YAML frontmatter
  lines.push("---");
  lines.push(`name: trc-${slugify(member.name)}`);
  lines.push(`description: ${safeRole}`);
  lines.push("---");
  lines.push("");

  // Role comment (for round-trip parsing)
  lines.push(`<!-- teamrc-role: ${safeRole} -->`);
  lines.push("");

  // Soul / persona
  if (member.soul) {
    lines.push(member.soul);
  } else {
    lines.push(`# ${safeName}`);
    lines.push("");
    lines.push(`You are ${safeName}. Your role is ${safeRole}.`);
    lines.push("");
    lines.push("Focus on your role and collaborate with your teammates.");
  }
  lines.push("");

  // Team context
  lines.push(`## Team: ${safeTeamName}`);
  lines.push("");

  // Teammates
  const teammates = allMembers
    .filter((m) => m.name !== member.name)
    .map((m) => `- **${sanitizeText(m.name)}** — ${sanitizeText(m.role)}`)
    .join("\n");
  if (teammates) {
    lines.push("## Teammates");
    lines.push("");
    lines.push(teammates);
    lines.push("");
  }

  // Per-agent skills
  const agentSkills = resolveAgentSkills(member, team);
  if (agentSkills.length > 0) {
    lines.push("## Skills");
    lines.push("");
    for (const s of agentSkills) {
      lines.push(`- **${s.title || s.id}**: ${s.description || ""}`);
    }
    lines.push("");
  }

  lines.push("## Team Knowledge");
  lines.push("");
  lines.push("Shared findings are stored in `~/.openclaw/teamrc-knowledge.md`. Read it at the start of every session. Append important discoveries so other team members benefit.");
  lines.push("");

  return lines.join("\n");
}

/** Parse an agent .md file back into role, soul, and team name */
function parseAgentFile(content: string): {
  role?: string;
  soul?: string;
  teamName?: string;
} {
  // Strip YAML frontmatter
  const bodyMatch = content.match(/^---\n[\s\S]*?\n---\n([\s\S]*)$/);
  const body = bodyMatch ? bodyMatch[1] : content;

  // Parse role from comment
  const roleMatch = body.match(/^<!-- teamrc-role:\s*(.+?)\s*-->$/m);
  const role = roleMatch ? roleMatch[1] : undefined;

  // Parse team name
  const teamMatch = body.match(/^## Team:\s*(.+)$/m);
  const teamName = teamMatch ? teamMatch[1].trim() : undefined;

  // Extract soul: content between role comment and ## Team:
  let soul: string | undefined;
  if (roleMatch) {
    const roleEnd = body.indexOf(roleMatch[0]) + roleMatch[0].length;
    const afterRole = body.slice(roleEnd);
    const teamIdx = afterRole.indexOf("\n## Team:");
    const soulRaw = (teamIdx >= 0
      ? afterRole.slice(0, teamIdx)
      : afterRole
    ).trim();

    if (soulRaw) {
      // Check if it's the default template
      const isDefault = soulRaw.match(/^# .+\n\nYou are .+\. Your role is .+\./);
      soul = isDefault ? undefined : soulRaw;
    }
  }

  return { role, soul, teamName };
}
