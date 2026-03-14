import * as fs from "node:fs";
import * as path from "node:path";
import { parse as parseYaml } from "yaml";
import {
  sanitizeMarkerContent,
  sanitizeText,
  slugify,
  escapeYamlString,
  knowledgeFileName,
  deleteKnowledgeFiles,
  validateAgentName,
  writeSkillDir,
  listTrcFiles,
  upsertMarkerBlock,
  removeMarkerBlock,
  cleanupSkillDirs,
  resolveAgentSkills,
  enrichTeamKnowledgeSkill,
  createBuiltInSkills,
  type FileAction,
  type PlatformAdapter,
  type TeamDefinition,
  type TeamMember,
  type Skill,
  type TeamScope,
} from "./base.js";

export class CursorAdapter implements PlatformAdapter {
  private teamSlug: string;

  constructor(teamSlug?: string) {
    this.teamSlug = teamSlug || "team";
  }

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
    const dir = this.agentsDir();
    const files = listTrcFiles(dir);
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

    if (members.length === 0) return null;

    // Read skills from .mdc rule files (alwaysApply / glob skills)
    const skills: Skill[] = [];
    const mdcFiles = listTrcFiles(this.rulesDir(), ".mdc");
    for (const file of mdcFiles) {
      const content = fs.readFileSync(path.join(this.rulesDir(), file), "utf-8");
      const skill = parseMdcFile(file, content);
      if (skill) skills.push(skill);
    }

    // Read skills from skill directories (on-demand skills)
    const skillsBase = this.skillsDir();
    if (fs.existsSync(skillsBase)) {
      const skillDirs = fs.readdirSync(skillsBase).filter((d) => d.startsWith("trc-"));
      for (const dirName of skillDirs) {
        const skillMdPath = path.join(skillsBase, dirName, "SKILL.md");
        if (!fs.existsSync(skillMdPath)) continue;
        const content = fs.readFileSync(skillMdPath, "utf-8");
        const skill = parseSkillMd(dirName, content);
        if (skill) skills.push(skill);
      }
    }

    return { name: teamName, members, ...(skills.length > 0 ? { skills } : {}) };
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
    // Enrich team-knowledge skill with actual knowledge content
    const teamWithKnowledge = enrichTeamKnowledgeSkill(team, `.teamrc/${knowledgeFileName(this.teamSlug)}`, this.readKnowledge());

    // Clean old rule files and skill dirs
    const oldRules = listTrcFiles(this.rulesDir(), ".mdc");
    for (const f of oldRules) {
      fs.unlinkSync(path.join(this.rulesDir(), f));
    }
    cleanupSkillDirs(this.skillsDir());

    // Route skills: alwaysApply/globs → .mdc rule, otherwise → SKILL.md
    if (teamWithKnowledge.skills) {
      for (const skill of teamWithKnowledge.skills) {
        if (skill.alwaysApply || (skill.globs && skill.globs.length > 0)) {
          this.writeSkillAsMdc(skill);
        } else {
          writeSkillDir(this.skillsDir(), skill);
        }
      }
    }

    // Write built-in teamrc skills (on-demand slash commands)
    const knowledgePath = `.teamrc/${knowledgeFileName(this.teamSlug)}`;
    for (const skill of createBuiltInSkills(knowledgePath)) {
      writeSkillDir(this.skillsDir(), skill);
    }

    // Build set of desired agent filenames and delete orphans
    const desiredFiles = new Set<string>();
    for (const member of team.members) {
      validateAgentName(member.name);
      desiredFiles.add(`trc-${slugify(member.name)}.md`);
    }
    for (const existing of listTrcFiles(this.agentsDir())) {
      if (!desiredFiles.has(existing)) {
        fs.unlinkSync(path.join(this.agentsDir(), existing));
      }
    }

    // Write individual subagent .md files
    for (const member of team.members) {
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

  private knowledgePath(): string {
    return path.join(process.cwd(), ".teamrc", knowledgeFileName(this.teamSlug));
  }

  readKnowledge(): string {
    const p = this.knowledgePath();
    if (fs.existsSync(p)) return fs.readFileSync(p, "utf-8");
    return "";
  }

  writeKnowledge(content: string): void {
    const p = this.knowledgePath();
    fs.mkdirSync(path.dirname(p), { recursive: true });
    fs.writeFileSync(p, content);
  }

  uninstall(_scope?: TeamScope): string[] {
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

    // Clean up knowledge
    for (const deleted of deleteKnowledgeFiles(path.join(process.cwd(), ".teamrc"), this.teamSlug)) {
      actions.push(`Deleted ${deleted}`);
    }

    // Clean up AGENTS.md marker block
    const agentsMdPath = path.join(this.cursorDir(), "AGENTS.md");
    if (removeMarkerBlock(agentsMdPath, "<!-- teamrc -->", "<!-- /teamrc -->")) {
      actions.push("Removed teamrc section from .cursor/AGENTS.md");
    }

    return actions;
  }
}

// --- Helpers ---

interface ParsedAgent {
  agentName: string;
  role: string;
  soul?: string;
  teamName: string;
}

/** Parse a trc-*.mdc rule file back into a Skill (alwaysApply / glob skills) */
function parseMdcFile(fileName: string, content: string): Skill | null {
  const id = fileName.replace(/^trc-/, "").replace(/\.mdc$/, "");
  const match = content.match(/^---\n([\s\S]*?)\n---\n([\s\S]*)$/);
  if (!match) return null;

  let frontmatter: Record<string, unknown>;
  try {
    frontmatter = parseYaml(match[1]) as Record<string, unknown>;
  } catch {
    return null;
  }

  const body = match[2].trim();
  const description = typeof frontmatter.description === "string" ? frontmatter.description : undefined;
  const alwaysApply = frontmatter.alwaysApply === true;
  const globs = Array.isArray(frontmatter.globs)
    ? (frontmatter.globs as unknown[]).map(String)
    : undefined;

  return {
    id,
    ...(description ? { description } : {}),
    ...(alwaysApply ? { alwaysApply } : {}),
    ...(globs && globs.length > 0 ? { globs } : {}),
    body,
  };
}

/** Parse a SKILL.md file from a trc-* skill directory back into a Skill (on-demand skills) */
function parseSkillMd(dirName: string, content: string): Skill | null {
  const id = dirName.replace(/^trc-/, "");
  const match = content.match(/^---\n([\s\S]*?)\n---\n([\s\S]*)$/);
  if (!match) {
    // No frontmatter — treat entire content as body
    return { id, body: content.trim() };
  }

  let frontmatter: Record<string, unknown>;
  try {
    frontmatter = parseYaml(match[1]) as Record<string, unknown>;
  } catch {
    return { id, body: content.trim() };
  }

  const body = match[2].trim();
  const description = typeof frontmatter.description === "string" ? frontmatter.description : undefined;
  const title = typeof frontmatter.title === "string" ? frontmatter.title : undefined;

  return {
    id,
    ...(title ? { title } : {}),
    ...(description ? { description } : {}),
    body,
  };
}

/** Parse a trc-*.md agent file back into structured data */
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

  // Extract agent name: strip trc- prefix
  const agentName = name.startsWith("trc-") ? name.slice(4) : name;

  // Extract role from description: "Role on the teamName team. Use when..."
  const roleMatch = description.match(/^(.+?)\s+on the\s+/);
  const role = roleMatch ? roleMatch[1] : description;

  // Extract team name from body: "# Team: teamName"
  const teamMatch = body.match(/^# Team:\s*(.+)$/m);
  const teamName = teamMatch ? teamMatch[1].trim() : "my-team";

  // Extract soul: everything between team header and ## Skills / ## Teammates / ## Team Knowledge (or end)
  const bodyAfterHeader = body.replace(/^# Team:.*\n+/, "");
  const sectionIdx = bodyAfterHeader.search(/^## (Skills|Teammates)/m);
  const soulRaw = sectionIdx >= 0
    ? bodyAfterHeader.slice(0, sectionIdx).trim()
    : bodyAfterHeader.trim();

  // Only set soul if it's not the default generated text
  const isDefault = soulRaw.startsWith(`You are ${agentName},`);
  const soul = isDefault ? undefined : soulRaw || undefined;

  return { agentName, role, soul, teamName };
}
