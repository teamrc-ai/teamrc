import * as fs from "node:fs";
import * as path from "node:path";
import {
  validateAgentName,
  sanitizeMarkerContent,
  sanitizeText,
  slugify,
  listTrcFiles,
  upsertMarkerBlock,
  removeMarkerBlock,
  writeSkillDir,
  cleanupSkillDirs,
  resolveAgentSkills,
  type FileAction,
  type PlatformAdapter,
  type TeamDefinition,
  type TeamMember,
} from "./base.js";

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
    return path.join(process.cwd(), ".agents", "skills");
  }


  readTeam(): TeamDefinition | null { return null; }

  planWrite(team: TeamDefinition): FileAction[] {
    const actions: FileAction[] = [];

    // Subagent TOML files
    const existingAgents = new Set(listTrcFiles(this.agentsConfigDir(), ".toml"));
    const newAgents = new Set<string>();
    for (const member of team.members) {
      validateAgentName(member.name);
      const fileName = `trc-${slugify(member.name)}.toml`;
      newAgents.add(fileName);
      actions.push({
        type: existingAgents.has(fileName) ? "update" : "create",
        path: path.join(this.agentsConfigDir(), fileName),
        description: `agent: ${member.name}`,
      });
    }
    for (const f of existingAgents) {
      if (!newAgents.has(f)) actions.push({ type: "delete", path: path.join(this.agentsConfigDir(), f) });
    }

    // config.toml
    const configPath = path.join(this.codexDir(), "config.toml");
    actions.push({
      type: fs.existsSync(configPath) ? "update" : "create",
      path: configPath,
      description: "agent registration",
    });

    // Skill directories
    const existingSkillDirs = new Set(
      fs.existsSync(this.skillsDir()) ? fs.readdirSync(this.skillsDir()).filter((f) => f.startsWith("trc-")) : [],
    );
    const newSkillDirs = new Set<string>();
    if (team.skills) {
      for (const skill of team.skills) {
        if (!skill.alwaysApply && !(skill.globs && skill.globs.length > 0)) {
          const dirName = `trc-${skill.id}`;
          newSkillDirs.add(dirName);
          actions.push({
            type: existingSkillDirs.has(dirName) ? "update" : "create",
            path: path.join(this.skillsDir(), dirName, "SKILL.md"),
            description: `skill: ${skill.id}`,
          });
        }
      }
    }
    for (const d of existingSkillDirs) { if (!newSkillDirs.has(d)) actions.push({ type: "delete", path: path.join(this.skillsDir(), d) }); }

    // AGENTS.md
    const agentsMdPath = this.agentsMdPath();
    actions.push({
      type: fs.existsSync(agentsMdPath) ? "update" : "create",
      path: agentsMdPath,
      description: "team routing",
    });

    return actions;
  }

  writeTeam(team: TeamDefinition): void {
    // Route skills: alwaysApply/globs → inline in AGENTS.md, on-demand → .agents/skills/
    cleanupSkillDirs(this.skillsDir());
    if (team.skills) {
      const dir = this.skillsDir();
      for (const skill of team.skills) {
        if (!skill.alwaysApply && !(skill.globs && skill.globs.length > 0)) {
          writeSkillDir(dir, skill);
        }
      }
    }

    // Write individual subagent TOML configs
    for (const member of team.members) {
      validateAgentName(member.name);
      this.writeAgentToml(team.name, member, team.members, team);
    }

    // Register subagents in .codex/config.toml
    this.writeConfigToml(team);

    // Write AGENTS.md with team context, routing, and always-on skills
    this.writeAgentsMd(team);
  }

  /** Write a TOML config file for an individual subagent */
  private writeAgentToml(teamName: string, member: TeamMember, allMembers: TeamMember[], team: TeamDefinition): void {
    const dir = this.agentsConfigDir();
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });

    const slug = slugify(member.name);
    const filePath = path.join(dir, `trc-${slug}.toml`);

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

    // Add resolved skills (per-agent, inlined into developer_instructions)
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

    const instructions = instructionParts.join("\n").trim()
      .replace(/\\/g, "\\\\")
      .replace(/"/g, '\\"');

    const tomlContent = [
      `# teamrc agent: ${safeName}`,
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
    const marker = "# --- teamrc start ---";
    const markerEnd = "# --- teamrc end ---";

    const lines: string[] = [marker, ""];

    // Global agents settings
    lines.push("[agents]");
    lines.push("multi_agent = true");
    lines.push(`max_threads = ${Math.min(team.members.length, 8)}`);
    lines.push(`max_depth = 1`);
    lines.push("");

    // Register each agent
    for (const member of team.members) {
      const slug = slugify(member.name);
      const safeRole = sanitizeText(member.role);
      lines.push(`[agents.trc-${slug}]`);
      lines.push(`description = ${JSON.stringify(safeRole)}`);
      lines.push(`config_file = "agents/trc-${slug}.toml"`);
      lines.push("");
    }

    lines.push(markerEnd);
    const block = lines.join("\n");
    upsertMarkerBlock(configPath, marker, markerEnd, block);
  }

  /** Write AGENTS.md with team context, routing, and always-on skills */
  private writeAgentsMd(team: TeamDefinition): void {
    const marker = "<!-- teamrc -->";
    const markerEnd = "<!-- /teamrc -->";

    const sections = [`# Team: ${sanitizeMarkerContent(team.name)}`, ""];
    sections.push("You have access to specialized subagents. Delegate tasks to the right specialist.", "");

    for (const member of team.members) {
      const slug = slugify(member.name);
      sections.push(`## ${sanitizeMarkerContent(member.name)} (\`trc-${slug}\`)`, "");
      sections.push(`**Role:** ${sanitizeMarkerContent(member.role)}`, "");

      const agentSkills = resolveAgentSkills(member, team);
      if (agentSkills.length > 0) {
        sections.push("**Skills:**");
        for (const s of agentSkills) {
          sections.push(`- \`${sanitizeMarkerContent(s.id)}\``);
        }
        sections.push("");
      }
    }

    // Inline alwaysApply/globs skills as sections (Codex has no native rules)
    const alwaysOnSkills = (team.skills || []).filter(
      (s) => s.alwaysApply || (s.globs && s.globs.length > 0),
    );
    if (alwaysOnSkills.length > 0) {
      sections.push("---", "");
      sections.push("## Team Rules", "");
      for (const s of alwaysOnSkills) {
        const title = s.title || s.id;
        const body = typeof s.body === "string" ? s.body : "";
        sections.push(`### ${sanitizeMarkerContent(title)}`, "");
        if (s.globs && s.globs.length > 0) {
          sections.push(`_Applies to: ${s.globs.join(", ")}_`, "");
        }
        if (body) sections.push(body, "");
      }
    }

    sections.push("## Team Knowledge");
    sections.push("");
    sections.push("Shared findings and decisions are stored in `teamrc-knowledge.md`. Read this file at the start of every session for context from other agents and machines. When you discover something important (architecture decisions, gotchas, debugging insights), append it to this file so other team members can benefit.");
    sections.push("");

    const block = [marker, ...sections, markerEnd].join("\n");
    upsertMarkerBlock(this.agentsMdPath(), marker, markerEnd, block);
  }

  readKnowledge(): string {
    const p = path.join(process.cwd(), "teamrc-knowledge.md");
    if (fs.existsSync(p)) return fs.readFileSync(p, "utf-8");
    return "";
  }

  writeKnowledge(content: string): void {
    fs.writeFileSync(path.join(process.cwd(), "teamrc-knowledge.md"), content);
  }

  uninstall(): string[] {
    const actions: string[] = [];

    // Clean up subagent TOML files
    const agentFiles = listTrcFiles(this.agentsConfigDir(), ".toml");
    for (const f of agentFiles) {
      fs.unlinkSync(path.join(this.agentsConfigDir(), f));
    }
    if (agentFiles.length > 0) {
      actions.push(`Deleted ${agentFiles.length} Codex subagent config(s)`);
    }

    // Clean up config.toml teamrc section
    if (removeMarkerBlock(path.join(this.codexDir(), "config.toml"), "# --- teamrc start ---", "# --- teamrc end ---")) {
      actions.push("Removed teamrc section from .codex/config.toml");
    }

    // Clean up skill directories
    const skillCount = cleanupSkillDirs(this.skillsDir());
    if (skillCount > 0) {
      actions.push(`Deleted ${skillCount} teamrc codex skill(s)`);
    }

    // Clean up AGENTS.md marker block
    if (removeMarkerBlock(this.agentsMdPath(), "<!-- teamrc -->", "<!-- /teamrc -->")) {
      actions.push("Removed teamrc section from AGENTS.md");
    }

    return actions;
  }
}
