import * as fs from "node:fs";
import * as path from "node:path";
import {
  sanitizeMarkerContent,
  validateAgentName,
  writeSkillDir,
  cleanupSkillDirs,
  type PlatformAdapter,
  type TeamDefinition,
  type TeamMember,
  type Rule,
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

function escapeYamlString(s: string): string {
  return s.replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, "\\n");
}

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

  private listTbRules(): string[] {
    const dir = this.rulesDir();
    if (!fs.existsSync(dir)) return [];
    return fs.readdirSync(dir).filter((f) => f.startsWith("tb-") && f.endsWith(".mdc"));
  }

  private listTbAgentFiles(): string[] {
    const dir = this.agentsDir();
    if (!fs.existsSync(dir)) return [];
    return fs.readdirSync(dir).filter((f) => f.startsWith("tb-") && f.endsWith(".md"));
  }

  readTeam(): TeamDefinition | null {
    return null;
  }

  writeTeam(team: TeamDefinition): void {
    // Write all rules as .mdc files (project-level, Cursor's native format)
    if (team.rules) {
      for (const rule of team.rules) {
        this.writeRuleMdc(rule);
      }
    }
    // Write native skill directories
    if (team.skills) {
      const dir = this.skillsDir();
      for (const skill of team.skills) {
        writeSkillDir(dir, skill);
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
    const filePath = path.join(dir, `tb-${slug}.md`);

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

    // Add resolved rules
    const agentRules = resolveAgentRules(member, team);
    if (agentRules.length > 0) {
      bodyParts.push("## Rules");
      bodyParts.push("");
      for (const r of agentRules) {
        const title = r.title || r.id;
        const body = typeof r.body === "string" ? r.body : "";
        bodyParts.push(`### ${title}`);
        bodyParts.push("");
        bodyParts.push(body);
        bodyParts.push("");
      }
    }

    // Add resolved skills
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
name: tb-${slug}
description: "${escapeYamlString(safeRole)} on the ${escapeYamlString(safeTeamName)} team. Use when tasks relate to ${escapeYamlString(safeRole.toLowerCase())}."
---

${body}
`;

    fs.writeFileSync(filePath, content);
  }

  private writeRuleMdc(rule: Rule): void {
    const dir = this.rulesDir();
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });

    const fileName = `tb-${rule.id}.mdc`;
    const filePath = path.join(dir, fileName);

    const description = JSON.stringify((rule.title || rule.id).replace(/[\n\r]/g, " "));
    const globs = rule.globs ? `globs: ${JSON.stringify(rule.globs)}` : "";
    const alwaysApply = rule.alwaysApply !== undefined ? `alwaysApply: ${rule.alwaysApply}` : "alwaysApply: false";
    const body = typeof rule.body === "string" ? rule.body : "";

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

    if (fs.existsSync(agentsMdPath)) {
      let content = fs.readFileSync(agentsMdPath, "utf-8");
      const regex = new RegExp(
        `${marker.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}[\\s\\S]*?${markerEnd.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}`,
      );
      content = regex.test(content) ? content.replace(regex, block) : content.trimEnd() + "\n\n" + block + "\n";
      fs.writeFileSync(agentsMdPath, content);
    } else {
      fs.writeFileSync(agentsMdPath, block + "\n");
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

    // Clean up subagent .md files
    const agentFiles = this.listTbAgentFiles();
    for (const f of agentFiles) {
      fs.unlinkSync(path.join(this.agentsDir(), f));
    }
    if (agentFiles.length > 0) {
      actions.push(`Deleted ${agentFiles.length} Cursor subagent config(s)`);
    }

    // Clean up rule .mdc files
    const tbRules = this.listTbRules();
    for (const f of tbRules) {
      fs.unlinkSync(path.join(this.rulesDir(), f));
    }
    if (tbRules.length > 0) {
      actions.push(`Deleted ${tbRules.length} TeamBridge cursor rule(s)`);
    }

    // Clean up skill directories
    const skillCount = cleanupSkillDirs(this.skillsDir());
    if (skillCount > 0) {
      actions.push(`Deleted ${skillCount} TeamBridge cursor skill(s)`);
    }

    // Clean up AGENTS.md marker block
    const agentsMdPath = path.join(this.cursorDir(), "AGENTS.md");
    if (fs.existsSync(agentsMdPath)) {
      const content = fs.readFileSync(agentsMdPath, "utf-8");
      const marker = "<!-- teambridge -->";
      const markerEnd = "<!-- /teambridge -->";
      const regex = new RegExp(
        `\\n?${marker.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}[\\s\\S]*?${markerEnd.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\n?`,
      );
      const cleaned = content.replace(regex, "\n");
      if (cleaned !== content) {
        fs.writeFileSync(agentsMdPath, cleaned.trimEnd() + "\n");
        actions.push("Removed TeamBridge section from .cursor/AGENTS.md");
      }
    }

    return actions;
  }
}
