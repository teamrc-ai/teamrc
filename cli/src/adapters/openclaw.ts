import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";
import { execFileSync } from "node:child_process";
import {
  hashContent,
  validateAgentName,
  type PlatformAdapter,
  type PortableAgent,
  type TeamDefinition,
  type TeamMember,
} from "./base.js";
import { resolveAgentRules, resolveAgentSkills } from "../resolve-rules.js";

function sanitizeText(text: string): string {
  return text.replace(/[\n\r]/g, " ").trim();
}

export class OpenClawAdapter implements PlatformAdapter {
  private openclawDir: string;

  constructor() {
    this.openclawDir = path.join(os.homedir(), ".openclaw");
  }

  /** Parse JSON with comments and trailing commas (openclaw.json format) */
  private readOpenClawConfig(configPath: string): Record<string, unknown> | null {
    if (!fs.existsSync(configPath)) return null;
    try {
      const raw = fs.readFileSync(configPath, "utf-8");
      const cleaned = raw
        .replace(/\/\/.*$/gm, "")
        .replace(/,\s*([\]}])/g, "$1");
      return JSON.parse(cleaned) as Record<string, unknown>;
    } catch {
      return null;
    }
  }

  /** Directory for a TeamBridge agent's workspace */
  private agentWorkspace(agentName: string): string {
    return path.join(this.openclawDir, "workspaces", `tb-${agentName}`);
  }

  /** List all tb-* workspace directories */
  private listTbWorkspaces(): string[] {
    const dir = path.join(this.openclawDir, "workspaces");
    if (!fs.existsSync(dir)) return [];
    return fs.readdirSync(dir).filter((d) =>
      d.startsWith("tb-") && fs.statSync(path.join(dir, d)).isDirectory(),
    );
  }

  readTeam(): TeamDefinition | null {
    const workspaces = this.listTbWorkspaces();
    if (workspaces.length === 0) return null;

    let teamName = "my-team";
    const members: TeamMember[] = [];

    for (const ws of workspaces) {
      const agentName = ws.replace("tb-", "");
      const wsDir = path.join(this.openclawDir, "workspaces", ws);
      const parsed = this.parseWorkspace(agentName, wsDir);
      if (!parsed) continue;
      if (parsed.teamName) teamName = parsed.teamName;
      members.push({
        name: parsed.name,
        role: parsed.role,
        ...(parsed.soul ? { soul: parsed.soul } : {}),
      });
    }

    return members.length > 0 ? { name: teamName, members } : null;
  }

  private parseWorkspace(agentName: string, wsDir: string): PortableAgent | null {
    const soulPath = path.join(wsDir, "SOUL.md");
    const agentsPath = path.join(wsDir, "AGENTS.md");
    if (!fs.existsSync(soulPath)) return null;

    const soulContent = fs.readFileSync(soulPath, "utf-8");
    const agentsContent = fs.existsSync(agentsPath) ? fs.readFileSync(agentsPath, "utf-8") : "";

    // Extract role from SOUL.md first line: "# Role description"
    const roleMatch = soulContent.match(/^#\s+(.+)$/m);
    const role = roleMatch ? roleMatch[1].trim() : "Agent";

    // Extract team name from AGENTS.md: "# Team: teamName"
    const teamMatch = agentsContent.match(/^#\s+Team:\s*(.+)$/m);
    const teamName = teamMatch ? teamMatch[1].trim() : "my-team";

    // Extract soul: everything after the first heading in SOUL.md
    const soulBody = soulContent.replace(/^#.*\n+/, "").trim();
    // Check if it's the default generated text
    const isDefault = soulBody.startsWith(`You are ${agentName} on the`);
    const soul = isDefault ? undefined : soulBody || undefined;

    return { name: agentName, role, soul, teamName };
  }

  writeTeam(team: TeamDefinition): void {
    const agentIds: string[] = [];

    for (const member of team.members) {
      validateAgentName(member.name);
      const agentName = `tb-${member.name}`;
      agentIds.push(agentName);
      const workspaceDir = this.agentWorkspace(member.name);
      if (!fs.existsSync(workspaceDir)) {
        fs.mkdirSync(workspaceDir, { recursive: true });
      }

      this.writeNativeAgentFiles(workspaceDir, team.name, member, team.members, team);

      // Register agent with OpenClaw via CLI
      try {
        execFileSync("openclaw", [
          "agents", "add", agentName,
          "--workspace", workspaceDir,
          "--non-interactive",
        ], {
          stdio: "ignore",
        });
      } catch {
        // CLI not available — register directly in openclaw.json
        this.registerAgentInConfig(agentName, workspaceDir);
      }
    }

    // Write team-wide skills to the default workspace
    if (team.skills && team.skills.length > 0) {
      const defaultWorkspace = path.join(this.openclawDir, "workspace");
      if (!fs.existsSync(defaultWorkspace)) {
        fs.mkdirSync(defaultWorkspace, { recursive: true });
      }
      this.writeNativeSkillFiles(defaultWorkspace, team.skills);
    }

    // Wire up routing: allow main agent to spawn team agents + add dispatch rules
    this.wireRouting(team, agentIds);
  }

  private writeNativeAgentFiles(wsDir: string, teamName: string, member: TeamMember, allMembers: TeamMember[], team?: TeamDefinition): void {
    const safeName = sanitizeText(member.name);
    const safeRole = sanitizeText(member.role);

    // SOUL.md — persona definition (required by OpenClaw)
    const soulPath = path.join(wsDir, "SOUL.md");
    const soulContent = member.soul
      ? `# ${safeRole}\n\n${member.soul}`
      : `# ${safeRole}\n\nYou are ${safeName} on the ${teamName} team.\nRole: ${safeRole}\n`;
    fs.writeFileSync(soulPath, soulContent);

    // AGENTS.md — operating instructions
    const agentsPath = path.join(wsDir, "AGENTS.md");
    const teammatesList = allMembers
      .map((m) => `- **${sanitizeText(m.name)}** — ${sanitizeText(m.role)}`)
      .join("\n");

    let extraSections = "";
    if (team) {
      const resolvedRules = resolveAgentRules(member, team);
      if (resolvedRules.length > 0) {
        const ruleBlocks = resolvedRules.map((r) => {
          const title = r.title || r.id;
          const body = typeof r.body === "string" ? r.body : "";
          return `### ${title}\n\n${body}`;
        }).join("\n\n");
        extraSections += `## Rules\n\n${ruleBlocks}\n\n`;
      }

      const resolvedSkills = resolveAgentSkills(member, team);
      if (resolvedSkills.length > 0) {
        const skillBlocks = resolvedSkills.map((s) => {
          const title = s.title || s.id;
          const desc = s.description ? `${s.description}\n\n` : "";
          const body = s.body ? (typeof s.body === "string" ? s.body : "") : "";
          return `### ${title}\n\n${desc}${body}`;
        }).join("\n\n");
        extraSections += `## Skills\n\n${skillBlocks}\n\n`;
      }

      // Write native skill directories for this agent's resolved skills
      this.writeNativeSkillFiles(wsDir, resolvedSkills);
    }

    const agentsContent = [
      `# Team: ${teamName}`,
      "",
      `You are **${safeName}** — ${safeRole}.`,
      "",
      "## Teammates",
      "",
      teammatesList,
      "",
      ...(extraSections ? [extraSections] : []),
      "## Team Knowledge",
      "",
      "Shared findings and decisions are stored in `TEAM-KNOWLEDGE.md` in the default workspace. Read it at the start of every session for context from other agents and machines. When you discover something important, append it to that file.",
      "",
    ].join("\n");
    fs.writeFileSync(agentsPath, agentsContent);
  }

  /** Write native OpenClaw skill directories (skills/tb-{id}/SKILL.md) into a workspace */
  private writeNativeSkillFiles(wsDir: string, skills: import("./base.js").Skill[]): void {
    for (const skill of skills) {
      const body = skill.body ? (typeof skill.body === "string" ? skill.body : null) : null;
      const skillDir = path.join(wsDir, "skills", `tb-${skill.id}`);
      if (!fs.existsSync(skillDir)) {
        fs.mkdirSync(skillDir, { recursive: true });
      }

      const frontmatterLines = [`name: tb-${skill.id}`];
      if (skill.description) {
        frontmatterLines.push(`description: "${skill.description}"`);
      }

      const parts = [
        "---",
        frontmatterLines.join("\n"),
        "---",
      ];
      if (body) {
        parts.push("", body);
      }

      fs.writeFileSync(path.join(skillDir, "SKILL.md"), parts.join("\n") + "\n");
    }
  }

  /** Configure the main agent to dispatch to TeamBridge sub-agents */
  private wireRouting(team: TeamDefinition, agentIds: string[]): void {
    this.updateAllowAgents(agentIds);
    this.writeRoutingInstructions(team, agentIds);
  }

  private updateAllowAgents(agentIds: string[]): void {
    const configPath = path.join(this.openclawDir, "openclaw.json");
    const config = this.readOpenClawConfig(configPath);
    if (!config) return;

    const agents = (config["agents"] ?? {}) as Record<string, unknown>;
    const list = (agents["list"] ?? []) as Array<Record<string, unknown>>;

    let mainAgent = list.find((a) => a["default"] === true);
    if (!mainAgent && list.length > 0) {
      mainAgent = list.find((a) => !String(a["id"] ?? "").startsWith("tb-")) ?? list[0];
    }
    if (!mainAgent) return;

    const subagents = (mainAgent["subagents"] ?? {}) as Record<string, unknown>;
    const existing = (subagents["allowAgents"] ?? []) as string[];
    const merged = [...new Set([...existing, ...agentIds])];
    subagents["allowAgents"] = merged;
    mainAgent["subagents"] = subagents;

    config["agents"] = agents;
    fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
  }

  private writeRoutingInstructions(team: TeamDefinition, agentIds: string[]): void {
    const defaultWorkspace = path.join(this.openclawDir, "workspace");
    const agentsMdPath = path.join(defaultWorkspace, "AGENTS.md");

    const marker = "<!-- teambridge:routing -->";
    const markerEnd = "<!-- /teambridge:routing -->";

    const routingBlock = [
      marker,
      `## TeamBridge: ${team.name}`,
      "",
      "You have access to specialized team agents. Dispatch tasks to the right specialist using `sessions_spawn`.",
      "",
      "| Agent ID | Role |",
      "|----------|------|",
      ...team.members.map((m, i) => `| \`${agentIds[i]}\` | ${m.role} |`),
      "",
      "**Dispatch rules:**",
      ...team.members.map((m, i) => `- For ${m.role.toLowerCase()} tasks, spawn \`${agentIds[i]}\``),
      "",
      "**Usage:** `sessions_spawn` with `agentId` set to the agent ID above.",
      "",
      `**Team knowledge:** Shared findings are in \`TEAM-KNOWLEDGE.md\`. Read it for cross-agent context.`,
      markerEnd,
    ].join("\n");

    if (!fs.existsSync(defaultWorkspace)) {
      fs.mkdirSync(defaultWorkspace, { recursive: true });
    }

    if (fs.existsSync(agentsMdPath)) {
      let content = fs.readFileSync(agentsMdPath, "utf-8");
      const markerRegex = new RegExp(
        `${marker.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}[\\s\\S]*?${markerEnd.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}`,
      );
      if (markerRegex.test(content)) {
        content = content.replace(markerRegex, routingBlock);
      } else {
        content = content.trimEnd() + "\n\n" + routingBlock + "\n";
      }
      fs.writeFileSync(agentsMdPath, content);
    } else {
      fs.writeFileSync(agentsMdPath, routingBlock + "\n");
    }
  }

  private registerAgentInConfig(agentId: string, workspace: string): void {
    const configPath = path.join(this.openclawDir, "openclaw.json");
    const config = this.readOpenClawConfig(configPath) ?? {};

    const agents = (config["agents"] ?? {}) as Record<string, unknown>;
    const list = (agents["list"] ?? []) as Array<{ id: string; workspace?: string }>;

    if (list.some((a) => a.id === agentId)) return;

    list.push({ id: agentId, workspace });
    agents["list"] = list;
    config["agents"] = agents;

    const dir = path.dirname(configPath);
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true, mode: 0o700 });
    }
    fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
  }

  private knowledgePath(): string {
    return path.join(this.openclawDir, "workspace", "TEAM-KNOWLEDGE.md");
  }

  readKnowledge(): string {
    const filePath = this.knowledgePath();
    if (!fs.existsSync(filePath)) {
      return "";
    }
    return fs.readFileSync(filePath, "utf-8");
  }

  writeKnowledge(content: string): void {
    const dir = path.dirname(this.knowledgePath());
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true });
    }
    fs.writeFileSync(this.knowledgePath(), content);
  }

  appendKnowledge(entries: string[]): void {
    if (entries.length === 0) return;

    const filePath = this.knowledgePath();
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

    // Hash each agent workspace as portable JSON
    for (const ws of this.listTbWorkspaces()) {
      const agentName = ws.replace("tb-", "");
      const wsDir = path.join(this.openclawDir, "workspaces", ws);
      const parsed = this.parseWorkspace(agentName, wsDir);
      if (!parsed) continue;
      const portable = JSON.stringify(parsed);
      hashes[`agent:${agentName}`] = hashContent(portable);
    }

    // Hash team knowledge file
    const knowledgePath = this.knowledgePath();
    if (fs.existsSync(knowledgePath)) {
      const content = fs.readFileSync(knowledgePath, "utf-8");
      hashes["knowledge:team"] = hashContent(content);
    }

    return hashes;
  }

  watchPaths(): string[] {
    const paths = [this.knowledgePath()];
    // Watch all tb-* workspace directories
    const wsBase = path.join(this.openclawDir, "workspaces");
    if (fs.existsSync(wsBase)) {
      for (const ws of this.listTbWorkspaces()) {
        paths.push(path.join(wsBase, ws));
      }
    }
    return paths;
  }

  writeFile(key: string, content: string): void {
    if (key.startsWith("agent:")) {
      this.writeAgentFromPortable(key, content);
      return;
    }
    if (key === "knowledge:team") {
      this.writeKnowledge(content);
      return;
    }
  }

  readFile(key: string): string | null {
    if (key.startsWith("agent:")) {
      return this.readAgentAsPortable(key);
    }
    if (key === "knowledge:team") {
      const p = this.knowledgePath();
      return fs.existsSync(p) ? fs.readFileSync(p, "utf-8") : null;
    }
    return null;
  }

  private readAgentAsPortable(key: string): string | null {
    const agentName = key.replace("agent:", "");
    const wsDir = this.agentWorkspace(agentName);
    const parsed = this.parseWorkspace(agentName, wsDir);
    return parsed ? JSON.stringify(parsed) : null;
  }

  private writeAgentFromPortable(key: string, json: string): void {
    const portable = JSON.parse(json) as PortableAgent;
    validateAgentName(portable.name);
    const wsDir = this.agentWorkspace(portable.name);
    if (!fs.existsSync(wsDir)) {
      fs.mkdirSync(wsDir, { recursive: true });
    }

    const team = this.readTeam();
    const allMembers: TeamMember[] = team?.members ?? [];

    const idx = allMembers.findIndex((m) => m.name === portable.name);
    const member: TeamMember = { name: portable.name, role: portable.role, soul: portable.soul };
    if (idx >= 0) {
      allMembers[idx] = member;
    } else {
      allMembers.push(member);
    }

    this.writeNativeAgentFiles(wsDir, portable.teamName, member, allMembers);

    // Register if not already
    const agentId = `tb-${portable.name}`;
    try {
      execFileSync("openclaw", [
        "agents", "add", agentId,
        "--workspace", wsDir,
        "--non-interactive",
      ], { stdio: "ignore" });
    } catch {
      this.registerAgentInConfig(agentId, wsDir);
    }
  }

  uninstall(): string[] {
    const actions: string[] = [];

    // Delete tb-* workspace directories
    const workspaces = this.listTbWorkspaces();
    if (workspaces.length > 0) {
      const wsBase = path.join(this.openclawDir, "workspaces");
      for (const ws of workspaces) {
        fs.rmSync(path.join(wsBase, ws), { recursive: true });
      }
      actions.push(`Deleted ${workspaces.length} agent workspace(s)`);
    }

    // Delete tb-* skill directories from the default workspace
    const defaultSkillsDir = path.join(this.openclawDir, "workspace", "skills");
    if (fs.existsSync(defaultSkillsDir)) {
      const tbSkills = fs.readdirSync(defaultSkillsDir).filter((d) =>
        d.startsWith("tb-") && fs.statSync(path.join(defaultSkillsDir, d)).isDirectory(),
      );
      for (const sd of tbSkills) {
        fs.rmSync(path.join(defaultSkillsDir, sd), { recursive: true });
      }
      if (tbSkills.length > 0) {
        actions.push(`Deleted ${tbSkills.length} skill directory(ies) from default workspace`);
      }
    }

    // Delete team knowledge
    const kPath = this.knowledgePath();
    if (fs.existsSync(kPath)) {
      fs.unlinkSync(kPath);
      actions.push(`Deleted ${kPath}`);
    }

    // Remove routing section from AGENTS.md
    const agentsMdPath = path.join(this.openclawDir, "workspace", "AGENTS.md");
    if (fs.existsSync(agentsMdPath)) {
      const content = fs.readFileSync(agentsMdPath, "utf-8");
      const marker = "<!-- teambridge:routing -->";
      const markerEnd = "<!-- /teambridge:routing -->";
      const markerRegex = new RegExp(
        `\\n?${marker.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}[\\s\\S]*?${markerEnd.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\n?`,
      );
      const cleaned = content.replace(markerRegex, "\n");
      if (cleaned !== content) {
        fs.writeFileSync(agentsMdPath, cleaned.trimEnd() + "\n");
        actions.push(`Removed TeamBridge routing from ${agentsMdPath}`);
      }
    }

    // Remove tb-* agents from openclaw.json
    const configPath = path.join(this.openclawDir, "openclaw.json");
    const config = this.readOpenClawConfig(configPath);
    if (config) {
      const agents = (config["agents"] ?? {}) as Record<string, unknown>;
      const list = (agents["list"] ?? []) as Array<Record<string, unknown>>;
      const filtered = list.filter((a) => !String(a["id"] ?? "").startsWith("tb-"));
      if (filtered.length !== list.length) {
        agents["list"] = filtered;
        // Also clean allowAgents on remaining agents
        for (const agent of filtered) {
          const subagents = (agent["subagents"] ?? {}) as Record<string, unknown>;
          const allow = (subagents["allowAgents"] ?? []) as string[];
          const cleanedAllow = allow.filter((id) => !id.startsWith("tb-"));
          if (cleanedAllow.length !== allow.length) {
            subagents["allowAgents"] = cleanedAllow;
            agent["subagents"] = subagents;
          }
        }
        config["agents"] = agents;
        fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
        actions.push(`Removed tb-* agents from ${configPath}`);
      }
    }

    return actions;
  }

}
