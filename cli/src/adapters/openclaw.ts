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
 * OpenClaw multi-agent adapter.
 *
 * Follows https://docs.openclaw.ai/concepts/multi-agent — each team member
 * becomes a fully isolated OpenClaw agent with:
 *   - Workspace:  ~/.openclaw/workspace-trc-<slug>/
 *     containing AGENTS.md (instructions) and SOUL.md (persona)
 *   - Agent dir:  ~/.openclaw/agents/trc-<slug>/agent/
 *   - Sessions:   ~/.openclaw/agents/trc-<slug>/sessions/
 *   - Per-agent skills in <workspace>/skills/
 *
 * Shared (team-wide) skills go to ~/.openclaw/skills/.
 * Agent list is registered in ~/.openclaw/openclaw.json under agents.list[].
 */
export class OpenClawAdapter implements PlatformAdapter {
  private openclawDir(): string {
    return path.join(os.homedir(), ".openclaw");
  }

  private configPath(): string {
    return path.join(this.openclawDir(), "openclaw.json");
  }

  private agentWorkspace(slug: string): string {
    return path.join(this.openclawDir(), `workspace-${slug}`);
  }

  private agentDir(slug: string): string {
    return path.join(this.openclawDir(), "agents", slug, "agent");
  }

  private sharedSkillsDir(): string {
    return path.join(this.openclawDir(), "skills");
  }

  private agentSkillsDir(slug: string): string {
    return path.join(this.agentWorkspace(slug), "skills");
  }

  readTeam(): TeamDefinition | null {
    const config = this.readConfig();
    if (!config) return null;

    const agents = config.agents as Record<string, unknown> | undefined;
    const agentsList = agents?.list as AgentEntry[] | undefined;
    if (!agentsList || agentsList.length === 0) return null;

    const trcAgents = agentsList.filter((a) => a.id?.startsWith("trc-"));
    if (trcAgents.length === 0) return null;

    let teamName = "my-team";
    const members: TeamMember[] = [];

    for (const agent of trcAgents) {
      const name = agent.id.slice(4); // strip "trc-"
      const workspace = agent.workspace
        ? agent.workspace.replace(/^~/, os.homedir())
        : this.agentWorkspace(agent.id);

      // Read role from SOUL.md frontmatter comment
      const soulPath = path.join(workspace, "SOUL.md");
      let role = "Agent";
      let soul: string | undefined;
      if (fs.existsSync(soulPath)) {
        const content = fs.readFileSync(soulPath, "utf-8");
        const parsed = parseSoulMd(content);
        if (parsed.role) role = parsed.role;
        if (parsed.soul) soul = parsed.soul;
      }

      members.push({ name, role, ...(soul ? { soul } : {}) });
    }

    // Extract team name from first agent's AGENTS.md
    if (trcAgents.length > 0) {
      const firstWorkspace = trcAgents[0].workspace
        ? trcAgents[0].workspace.replace(/^~/, os.homedir())
        : this.agentWorkspace(trcAgents[0].id);
      const agentsMd = path.join(firstWorkspace, "AGENTS.md");
      if (fs.existsSync(agentsMd)) {
        const content = fs.readFileSync(agentsMd, "utf-8");
        const nameMatch = content.match(/^# Team:\s*(.+)$/m);
        if (nameMatch) teamName = nameMatch[1].trim();
      }
    }

    return members.length > 0 ? { name: teamName, members } : null;
  }

  planWrite(team: TeamDefinition, _scope: TeamScope = "global"): FileAction[] {
    const actions: FileAction[] = [];

    for (const member of team.members) {
      validateAgentName(member.name);
      const slug = `trc-${slugify(member.name)}`;
      const workspace = this.agentWorkspace(slug);

      actions.push({
        type: fs.existsSync(path.join(workspace, "AGENTS.md")) ? "update" : "create",
        path: path.join(workspace, "AGENTS.md"),
        description: `agent workspace: ${member.name}`,
      });
      actions.push({
        type: fs.existsSync(path.join(workspace, "SOUL.md")) ? "update" : "create",
        path: path.join(workspace, "SOUL.md"),
        description: `agent soul: ${member.name}`,
      });
    }

    // Shared skill directories in ~/.openclaw/skills/
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
    // Create per-agent workspaces
    for (const member of team.members) {
      validateAgentName(member.name);
      const slug = `trc-${slugify(member.name)}`;
      const workspace = this.agentWorkspace(slug);

      if (!fs.existsSync(workspace)) {
        fs.mkdirSync(workspace, { recursive: true });
      }

      // Write AGENTS.md (instructions for this agent)
      fs.writeFileSync(
        path.join(workspace, "AGENTS.md"),
        buildAgentsMd(team.name, member, team.members, team),
      );

      // Write SOUL.md (persona, tone, role)
      fs.writeFileSync(
        path.join(workspace, "SOUL.md"),
        buildSoulMd(member),
      );

      // Write per-agent skills into <workspace>/skills/
      const agentSkills = resolveAgentSkills(member, team);
      const wsSkillsDir = this.agentSkillsDir(slug);
      cleanupSkillDirs(wsSkillsDir);
      if (agentSkills.length > 0) {
        if (!fs.existsSync(wsSkillsDir)) {
          fs.mkdirSync(wsSkillsDir, { recursive: true });
        }
        for (const skill of agentSkills) {
          writeSkillDir(wsSkillsDir, skill);
        }
      }

      // Ensure agent state dir exists
      const agentDir = this.agentDir(slug);
      if (!fs.existsSync(agentDir)) {
        fs.mkdirSync(agentDir, { recursive: true });
      }
    }

    // Write shared (team-wide) skills to ~/.openclaw/skills/
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

    // Build agents.list entries for teamrc members
    const trcEntries: AgentEntry[] = team.members.map((m) => {
      const slug = `trc-${slugify(m.name)}`;
      return {
        id: slug,
        name: sanitizeText(m.name),
        workspace: `~/.openclaw/workspace-${slug}`,
        agentDir: `~/.openclaw/agents/${slug}/agent`,
      };
    });

    // Preserve non-trc entries from existing config
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
    return path.join(this.openclawDir(), "team-knowledge.md");
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

    // Read config to find trc- agents
    const config = this.readConfig();
    const agents = (config?.agents as Record<string, unknown>)?.list as AgentEntry[] | undefined;
    const trcAgents = agents?.filter((a) => a.id?.startsWith("trc-")) ?? [];

    // Delete each trc- agent workspace and agent dir
    for (const agent of trcAgents) {
      const workspace = agent.workspace
        ? agent.workspace.replace(/^~/, os.homedir())
        : this.agentWorkspace(agent.id);
      if (fs.existsSync(workspace)) {
        fs.rmSync(workspace, { recursive: true, force: true });
        actions.push(`Deleted workspace ${workspace}`);
      }

      const agentDir = path.join(this.openclawDir(), "agents", agent.id);
      if (fs.existsSync(agentDir)) {
        fs.rmSync(agentDir, { recursive: true, force: true });
        actions.push(`Deleted agent dir ${agentDir}`);
      }
    }

    // Remove trc- skill directories from shared skills
    const sharedDir = this.sharedSkillsDir();
    const skillCount = cleanupSkillDirs(sharedDir);
    if (skillCount > 0) {
      actions.push(`Deleted ${skillCount} shared skill directory(ies) from ${sharedDir}`);
    }

    // Remove trc- entries from openclaw.json
    if (config && agents) {
      const nonTrcEntries = agents.filter((a) => !a.id?.startsWith("trc-"));
      const removedCount = agents.length - nonTrcEntries.length;
      if (removedCount > 0) {
        const agentsObj = (config.agents ?? {}) as Record<string, unknown>;
        const updated = { ...config, agents: { ...agentsObj, list: nonTrcEntries } };
        fs.writeFileSync(this.configPath(), JSON.stringify(updated, null, 2) + "\n");
        actions.push(`Removed ${removedCount} agent(s) from openclaw.json`);
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

function buildAgentsMd(
  teamName: string,
  member: TeamMember,
  allMembers: TeamMember[],
  team: TeamDefinition,
): string {
  const safeTeamName = sanitizeText(teamName);
  const safeName = sanitizeText(member.name);
  const safeRole = sanitizeText(member.role);

  const lines: string[] = [];
  lines.push(`# Team: ${safeTeamName}`);
  lines.push("");
  lines.push(`You are ${safeName}, a ${safeRole} on the ${safeTeamName} team.`);
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

  // Per-agent skills summary
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
  lines.push("Shared findings are stored in `~/.openclaw/team-knowledge.md`. Read it at the start of every session. Append important discoveries so other team members benefit.");
  lines.push("");

  return lines.join("\n");
}

function buildSoulMd(member: TeamMember): string {
  const safeName = sanitizeText(member.name);
  const safeRole = sanitizeText(member.role);

  const lines: string[] = [];
  // Encode role in a comment so readTeam can parse it back
  lines.push(`<!-- teamrc-role: ${safeRole} -->`);
  lines.push("");

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

  return lines.join("\n");
}

/** Parse role and soul content from a SOUL.md */
function parseSoulMd(content: string): { role?: string; soul?: string } {
  const roleMatch = content.match(/^<!-- teamrc-role:\s*(.+?)\s*-->$/m);
  const role = roleMatch ? roleMatch[1] : undefined;

  // Soul is everything after the role comment
  const soulRaw = content.replace(/^<!-- teamrc-role:.*?-->\n*/m, "").trim();

  // Check if it's the default template
  const isDefault = soulRaw.match(/^# .+\n\nYou are .+\. Your role is .+\./);
  const soul = isDefault ? undefined : soulRaw || undefined;

  return { role, soul };
}
