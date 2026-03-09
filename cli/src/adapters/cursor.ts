import * as fs from "node:fs";
import * as path from "node:path";
import {
  sanitizeMarkerContent,
  sanitizeText,
  slugify,
  escapeYamlString,
  validateAgentName,
  writeSkillDir,
  listTrcFiles,
  upsertMarkerBlock,
  removeMarkerBlock,
  cleanupSkillDirs,
  resolveAgentSkills,
  type FileAction,
  type PlatformAdapter,
  type TeamDefinition,
  type TeamMember,
  type Skill,
} from "./base.js";

export class CursorAdapter implements PlatformAdapter {
  private cursorDir(): string {
    return path.join(process.cwd(), ".cursor");
  }

  private rulesDir(): string {
    return path.join(this.cursorDir(), "rules");
  }

  private agentsDir(): string {
    return path.join(this.cursorDir(), "agents");
  }

  private skillsDir(): string {
    return path.join(this.cursorDir(), "skills");
  }

  readTeam(): TeamDefinition | null {
    return null;
  }

  planWrite(team: TeamDefinition): FileAction[] {
    const actions: FileAction[] = [];

    // Agent files
    const existingAgents = new Set(listTrcFiles(this.agentsDir()));
    const newAgents = new Set<string>();
    for (const member of team.members) {
      validateAgentName(member.name);
      const fileName = `trc-${slugify(member.name)}.md`;
      newAgents.add(fileName);
      actions.push({
        type: existingAgents.has(fileName) ? "update" : "create",
        path: path.join(this.agentsDir(), fileName),
        description: `agent: ${member.name}`,
      });
    }
    for (const f of existingAgents) {
      if (!newAgents.has(f)) actions.push({ type: "delete", path: path.join(this.agentsDir(), f) });
    }

    // Rules (.mdc) and skill dirs
    const existingRules = new Set(listTrcFiles(this.rulesDir(), ".mdc"));
    const existingSkillDirs = new Set(
      fs.existsSync(this.skillsDir()) ? fs.readdirSync(this.skillsDir()).filter((f) => f.startsWith("trc-")) : [],
    );
    const newRules = new Set<string>();
    const newSkillDirs = new Set<string>();

    if (team.skills) {
      for (const skill of team.skills) {
        if (skill.alwaysApply || (skill.globs && skill.globs.length > 0)) {
          const fileName = `trc-${skill.id}.mdc`;
          newRules.add(fileName);
          actions.push({
            type: existingRules.has(fileName) ? "update" : "create",
            path: path.join(this.rulesDir(), fileName),
            description: `rule: ${skill.id}`,
          });
        } else {
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
    for (const f of existingRules) { if (!newRules.has(f)) actions.push({ type: "delete", path: path.join(this.rulesDir(), f) }); }
    for (const d of existingSkillDirs) { if (!newSkillDirs.has(d)) actions.push({ type: "delete", path: path.join(this.skillsDir(), d) }); }

    // AGENTS.md
    const agentsMdPath = path.join(this.cursorDir(), "AGENTS.md");
    actions.push({
      type: fs.existsSync(agentsMdPath) ? "update" : "create",
      path: agentsMdPath,
      description: "teamrc routing",
    });

    return actions;
  }

  writeTeam(team: TeamDefinition): void {
    // Clean old rule files and skill dirs
    const oldRules = listTrcFiles(this.rulesDir(), ".mdc");
    for (const f of oldRules) {
      fs.unlinkSync(path.join(this.rulesDir(), f));
    }
    cleanupSkillDirs(this.skillsDir());

    // Route skills: alwaysApply/globs → .mdc rule, otherwise → SKILL.md
    if (team.skills) {
      for (const skill of team.skills) {
        if (skill.alwaysApply || (skill.globs && skill.globs.length > 0)) {
          this.writeSkillAsMdc(skill);
        } else {
          writeSkillDir(this.skillsDir(), skill);
        }
      }
    }
    // Write individual subagent .md files
    for (const member of team.members) {
      validateAgentName(member.name);
      this.writeAgentMd(team.name, member, team.members, team);
    }
    // Write routing AGENTS.md
    this.writeAgentsMd(team);
  }

  /** Write a subagent .md file with YAML frontmatter (Cursor native format) */
  private writeAgentMd(teamName: string, member: TeamMember, allMembers: TeamMember[], team: TeamDefinition): void {
    const dir = this.agentsDir();
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });

    const slug = slugify(member.name);
    const filePath = path.join(dir, `trc-${slug}.md`);

    const safeName = sanitizeText(member.name);
    const safeRole = sanitizeText(member.role);
    const safeTeamName = sanitizeText(teamName);

    // Build body content
    const bodyParts: string[] = [];
    bodyParts.push(`# Team: ${safeTeamName}`);
    bodyParts.push("");

    if (member.soul) {
      bodyParts.push(member.soul);
    } else {
      bodyParts.push(`You are ${safeName}, a ${safeRole} on the ${safeTeamName} team.`);
      bodyParts.push("");
      bodyParts.push("Focus on your role and collaborate with your teammates.");
    }
    bodyParts.push("");

    // Add resolved skills (per-agent, inlined into body for Cursor)
    const agentSkills = resolveAgentSkills(member, team);
    if (agentSkills.length > 0) {
      bodyParts.push("## Skills");
      bodyParts.push("");
      for (const s of agentSkills) {
        const title = s.title || s.id;
        const desc = s.description ? `${s.description}\n\n` : "";
        const body = s.body ? (typeof s.body === "string" ? s.body : "") : "";
        bodyParts.push(`### ${title}`);
        bodyParts.push("");
        if (desc) bodyParts.push(desc);
        if (body) bodyParts.push(body);
        bodyParts.push("");
      }
    }

    // Add teammates
    const teammates = allMembers
      .filter((m) => m.name !== member.name)
      .map((m) => `- **${sanitizeText(m.name)}** — ${sanitizeText(m.role)}`)
      .join("\n");
    if (teammates) {
      bodyParts.push("## Teammates");
      bodyParts.push("");
      bodyParts.push(teammates);
      bodyParts.push("");
    }

    const body = bodyParts.join("\n").trim();

    const content = `---
name: trc-${slug}
description: "${escapeYamlString(safeRole)} on the ${escapeYamlString(safeTeamName)} team. Use when tasks relate to ${escapeYamlString(safeRole.toLowerCase())}."
---

${body}
`;

    fs.writeFileSync(filePath, content);
  }

  private writeSkillAsMdc(skill: Skill): void {
    const dir = this.rulesDir();
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });

    const fileName = `trc-${skill.id}.mdc`;
    const filePath = path.join(dir, fileName);

    const description = JSON.stringify((skill.description || skill.title || skill.id).replace(/[\n\r]/g, " "));
    const sanitizedGlobs = skill.globs?.map((g) => g.replace(/[\n\r]/g, "")) ?? [];
    const globs = sanitizedGlobs.length ? `globs: ${JSON.stringify(sanitizedGlobs)}` : "";
    const alwaysApply = skill.alwaysApply ? "alwaysApply: true" : "alwaysApply: false";
    const body = typeof skill.body === "string" ? skill.body : "";

    const frontmatter = [
      "---",
      `description: ${description}`,
      ...(globs ? [globs] : []),
      alwaysApply,
      "---",
    ].join("\n");

    fs.writeFileSync(filePath, `${frontmatter}\n\n${body}\n`);
  }

  private writeAgentsMd(team: TeamDefinition): void {
    const cursorDir = this.cursorDir();
    if (!fs.existsSync(cursorDir)) fs.mkdirSync(cursorDir, { recursive: true });

    const agentsMdPath = path.join(cursorDir, "AGENTS.md");
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

    const block = [marker, ...sections, markerEnd].join("\n");
    upsertMarkerBlock(agentsMdPath, marker, markerEnd, block);
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

    // Clean up subagent .md files
    const agentFiles = listTrcFiles(this.agentsDir());
    for (const f of agentFiles) {
      fs.unlinkSync(path.join(this.agentsDir(), f));
    }
    if (agentFiles.length > 0) {
      actions.push(`Deleted ${agentFiles.length} Cursor subagent config(s)`);
    }

    // Clean up rule .mdc files
    const trcRules = listTrcFiles(this.rulesDir(), ".mdc");
    for (const f of trcRules) {
      fs.unlinkSync(path.join(this.rulesDir(), f));
    }
    if (trcRules.length > 0) {
      actions.push(`Deleted ${trcRules.length} teamrc cursor rule(s)`);
    }

    // Clean up skill directories
    const skillCount = cleanupSkillDirs(this.skillsDir());
    if (skillCount > 0) {
      actions.push(`Deleted ${skillCount} teamrc cursor skill(s)`);
    }

    // Clean up AGENTS.md marker block
    const agentsMdPath = path.join(this.cursorDir(), "AGENTS.md");
    if (removeMarkerBlock(agentsMdPath, "<!-- teamrc -->", "<!-- /teamrc -->")) {
      actions.push("Removed teamrc section from .cursor/AGENTS.md");
    }

    return actions;
  }
}
