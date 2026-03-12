import * as fs from "node:fs";
import * as path from "node:path";
import {
  validateAgentName,
  sanitizeMarkerContent,
  writeSkillDir,
  cleanupSkillDirs,
  type PlatformAdapter,
  type TeamDefinition,
  type TeamMember,
} from "./base.js";
import { resolveAgentRules, resolveAgentSkills } from "../resolve-rules.js";

function sanitizeText(s: string): string {
  return s.replace(/[\n\r]/g, " ").trim();
}

function slugify(name: string): string {
  return name
    .toLowerCase()
    .replace(/[^a-z0-9-]/g, "-")
    .replace(/-+/g, "-")
    .replace(/^-|-$/g, "");
}

export class CodexAdapter implements PlatformAdapter {
  private codexDir(): string {
    return path.join(process.cwd(), ".codex");
  }

  private agentsConfigDir(): string {
    return path.join(this.codexDir(), "agents");
  }

  private agentsMdPath(): string {
    return path.join(process.cwd(), "AGENTS.md");
  }

  private skillsDir(): string {
    return path.join(process.cwd(), "skills");
  }

  private listTbAgentFiles(): string[] {
    const dir = this.agentsConfigDir();
    if (!fs.existsSync(dir)) return [];
    return fs.readdirSync(dir).filter((f) => f.startsWith("tb-") && f.endsWith(".toml"));
  }

  readTeam(): TeamDefinition | null { return null; }

  writeTeam(team: TeamDefinition): void {
    // Write native skill directories
    if (team.skills) {
      const dir = this.skillsDir();
      for (const skill of team.skills) {
        writeSkillDir(dir, skill);
      }
    }

    // Write individual subagent TOML configs
    for (const member of team.members) {
      validateAgentName(member.name);
      this.writeAgentToml(team.name, member, team.members, team);
    }

    // Register subagents in .codex/config.toml
    this.writeConfigToml(team);

    // Write AGENTS.md with team context and routing instructions
    this.writeAgentsMd(team);
  }

  /** Write a TOML config file for an individual subagent */
  private writeAgentToml(teamName: string, member: TeamMember, allMembers: TeamMember[], team: TeamDefinition): void {
    const dir = this.agentsConfigDir();
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });

    const slug = slugify(member.name);
    const filePath = path.join(dir, `tb-${slug}.toml`);

    const safeName = sanitizeText(member.name);
    const safeRole = sanitizeText(member.role);
    const safeTeamName = sanitizeText(teamName);

    // Build developer instructions
    const instructionParts: string[] = [];
    instructionParts.push(`You are ${safeName}, a ${safeRole} on the ${safeTeamName} team.`);
    instructionParts.push("");

    if (member.soul) {
      instructionParts.push(member.soul);
      instructionParts.push("");
    }

    // Add resolved rules
    const agentRules = resolveAgentRules(member, team);
    if (agentRules.length > 0) {
      instructionParts.push("## Rules");
      instructionParts.push("");
      for (const r of agentRules) {
        const title = r.title || r.id;
        const body = typeof r.body === "string" ? r.body : "";
        instructionParts.push(`### ${title}`);
        instructionParts.push("");
        instructionParts.push(body);
        instructionParts.push("");
      }
    }

    // Add resolved skills
    const agentSkills = resolveAgentSkills(member, team);
    if (agentSkills.length > 0) {
      instructionParts.push("## Skills");
      instructionParts.push("");
      for (const s of agentSkills) {
        const title = s.title || s.id;
        const desc = s.description ? `${s.description}\n\n` : "";
        const body = s.body ? (typeof s.body === "string" ? s.body : "") : "";
        instructionParts.push(`### ${title}`);
        instructionParts.push("");
        if (desc) instructionParts.push(desc);
        if (body) instructionParts.push(body);
        instructionParts.push("");
      }
    }

    // Add teammates
    const teammates = allMembers
      .filter((m) => m.name !== member.name)
      .map((m) => `- ${sanitizeText(m.name)}: ${sanitizeText(m.role)}`)
      .join("\n");
    if (teammates) {
      instructionParts.push("## Teammates");
      instructionParts.push("");
      instructionParts.push(teammates);
      instructionParts.push("");
    }

    const instructions = instructionParts.join("\n").trim();

    // Escape for TOML multi-line string
    const tomlContent = [
      `# TeamBridge subagent: ${safeName}`,
      `# Role: ${safeRole}`,
      "",
      `developer_instructions = """`,
      instructions,
      `"""`,
      "",
    ].join("\n");

    fs.writeFileSync(filePath, tomlContent);
  }

  /** Write .codex/config.toml registering all subagents */
  private writeConfigToml(team: TeamDefinition): void {
    const codexDir = this.codexDir();
    if (!fs.existsSync(codexDir)) fs.mkdirSync(codexDir, { recursive: true });

    const configPath = path.join(codexDir, "config.toml");
    const marker = "# --- teambridge start ---";
    const markerEnd = "# --- teambridge end ---";

    const lines: string[] = [marker, ""];

    // Global agents settings
    lines.push("[agents]");
    lines.push(`max_threads = ${Math.min(team.members.length, 8)}`);
    lines.push(`max_depth = 1`);
    lines.push("");

    // Register each agent
    for (const member of team.members) {
      const slug = slugify(member.name);
      const safeRole = sanitizeText(member.role);
      lines.push(`[agents.tb-${slug}]`);
      lines.push(`description = ${JSON.stringify(safeRole)}`);
      lines.push(`config_file = "agents/tb-${slug}.toml"`);
      lines.push("");
    }

    lines.push(markerEnd);
    const block = lines.join("\n");

    if (fs.existsSync(configPath)) {
      let content = fs.readFileSync(configPath, "utf-8");
      const regex = new RegExp(
        `${marker.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}[\\s\\S]*?${markerEnd.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}`,
      );
      content = regex.test(content) ? content.replace(regex, block) : content.trimEnd() + "\n\n" + block + "\n";
      fs.writeFileSync(configPath, content);
    } else {
      fs.writeFileSync(configPath, block + "\n");
    }
  }

  /** Write AGENTS.md with team context for the main agent */
  private writeAgentsMd(team: TeamDefinition): void {
    const marker = "<!-- teambridge -->";
    const markerEnd = "<!-- /teambridge -->";

    const sections = [`# Team: ${sanitizeMarkerContent(team.name)}`, ""];
    sections.push("You have access to specialized subagents. Delegate tasks to the right specialist.", "");

    for (const member of team.members) {
      const slug = slugify(member.name);
      sections.push(`## ${sanitizeMarkerContent(member.name)} (\`tb-${slug}\`)`, "");
      sections.push(`**Role:** ${sanitizeMarkerContent(member.role)}`, "");

      const agentRules = resolveAgentRules(member, team);
      if (agentRules.length > 0) {
        sections.push("**Rules:**");
        for (const r of agentRules) {
          sections.push(`- \`${sanitizeMarkerContent(r.id)}\``);
        }
        sections.push("");
      }

      const agentSkills = resolveAgentSkills(member, team);
      if (agentSkills.length > 0) {
        sections.push("**Skills:**");
        for (const s of agentSkills) {
          sections.push(`- \`${sanitizeMarkerContent(s.id)}\``);
        }
        sections.push("");
      }
    }

    const block = [marker, ...sections, markerEnd].join("\n");
    const filePath = this.agentsMdPath();

    if (fs.existsSync(filePath)) {
      let content = fs.readFileSync(filePath, "utf-8");
      const regex = new RegExp(
        `${marker.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}[\\s\\S]*?${markerEnd.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}`,
      );
      content = regex.test(content) ? content.replace(regex, block) : content.trimEnd() + "\n\n" + block + "\n";
      fs.writeFileSync(filePath, content);
    } else {
      fs.writeFileSync(filePath, block + "\n");
    }
  }

  readKnowledge(): string { return ""; }
  writeKnowledge(_content: string): void {}
  appendKnowledge(_entries: string[]): void {}
  getHashes(): Record<string, string> { return {}; }
  watchPaths(): string[] { return []; }
  writeFile(_key: string, _content: string): void {}
  readFile(_key: string): string | null { return null; }
  uninstall(): string[] {
    const actions: string[] = [];

    // Clean up subagent TOML files
    const agentFiles = this.listTbAgentFiles();
    for (const f of agentFiles) {
      fs.unlinkSync(path.join(this.agentsConfigDir(), f));
    }
    if (agentFiles.length > 0) {
      actions.push(`Deleted ${agentFiles.length} Codex subagent config(s)`);
    }

    // Clean up config.toml teambridge section
    const configPath = path.join(this.codexDir(), "config.toml");
    if (fs.existsSync(configPath)) {
      const content = fs.readFileSync(configPath, "utf-8");
      const marker = "# --- teambridge start ---";
      const markerEnd = "# --- teambridge end ---";
      const regex = new RegExp(
        `\\n?${marker.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}[\\s\\S]*?${markerEnd.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\n?`,
      );
      const cleaned = content.replace(regex, "\n");
      if (cleaned !== content) {
        fs.writeFileSync(configPath, cleaned.trimEnd() + "\n");
        actions.push("Removed TeamBridge section from .codex/config.toml");
      }
    }

    // Clean up skill directories
    const skillCount = cleanupSkillDirs(this.skillsDir());
    if (skillCount > 0) {
      actions.push(`Deleted ${skillCount} TeamBridge codex skill(s)`);
    }

    // Clean up AGENTS.md marker block
    const filePath = this.agentsMdPath();
    if (fs.existsSync(filePath)) {
      const content = fs.readFileSync(filePath, "utf-8");
      const marker = "<!-- teambridge -->";
      const markerEnd = "<!-- /teambridge -->";
      const regex = new RegExp(
        `\\n?${marker.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}[\\s\\S]*?${markerEnd.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\n?`,
      );
      const cleaned = content.replace(regex, "\n");
      if (cleaned !== content) {
        fs.writeFileSync(filePath, cleaned.trimEnd() + "\n");
        actions.push("Removed TeamBridge section from AGENTS.md");
      }
    }

    return actions;
  }
}
