import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";
import { parse as parseYaml } from "yaml";
import {
  validateAgentName,
  sanitizeMarkerContent,
  sanitizeText,
  slugify,
  escapeYamlString,
  knowledgeFileName,
  deleteKnowledgeFiles,
  listTrcFiles,
  deleteTrcFiles,
  resolveAgentsDir,
  upsertMarkerBlock,
  removeMarkerBlock,
  writeSkillDir,
  cleanupSkillDirs,
  resolveAgentSkills,
  enrichTeamKnowledgeSkill,
  createBuiltInSkills,
  type FileAction,
  type PlatformAdapter,
  type TeamDefinition,
  type TeamMember,
  type TeamScope,
} from "./base.js";

export class GeminiAdapter implements PlatformAdapter {
  private teamSlug: string;

  constructor(teamSlug?: string) {
    this.teamSlug = teamSlug || "team";
  }

  private baseDir(scope: TeamScope): string {
    if (scope === "global") {
      return path.join(os.homedir(), ".gemini");
    }
    return path.join(process.cwd(), ".gemini");
  }

  private agentsDir(scope: TeamScope): string {
    return path.join(this.baseDir(scope), "agents");
  }

  private skillsDir(scope: TeamScope): string {
    if (scope === "global") {
      return path.join(os.homedir(), ".agents", "skills");
    }
    return path.join(process.cwd(), ".agents", "skills");
  }

  /** Antigravity uses .agent/skills/ (singular)  --  mirror skills there for compatibility */
  private antigravitySkillsDir(scope: TeamScope): string {
    if (scope === "global") {
      return path.join(os.homedir(), ".gemini", "antigravity", "skills");
    }
    return path.join(process.cwd(), ".agent", "skills");
  }

  private geminiMdPath(): string {
    return path.join(process.cwd(), "GEMINI.md");
  }

  readTeam(): TeamDefinition | null {
    const { dir } = resolveAgentsDir(this.agentsDir("project"), this.agentsDir("global"));
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

    return members.length > 0 ? { name: teamName, members } : null;
  }

  planWrite(team: TeamDefinition, scope: TeamScope = "global"): FileAction[] {
    const actions: FileAction[] = [];
    const agentDir = this.agentsDir(scope);

    // Agent files
    const existingSlugs = new Set(
      listTrcFiles(agentDir).map((f) => f.replace(/\.md$/, "")),
    );
    const newSlugs = new Set<string>();
    for (const member of team.members) {
      validateAgentName(member.name);
      const slug = `trc-${slugify(member.name)}`;
      newSlugs.add(slug);
      actions.push({
        type: existingSlugs.has(slug) ? "update" : "create",
        path: path.join(agentDir, `${slug}.md`),
        description: `agent: ${member.name}`,
      });
    }
    for (const slug of existingSlugs) {
      if (!newSlugs.has(slug)) actions.push({ type: "delete", path: path.join(agentDir, `${slug}.md`) });
    }

    // Skill directories (Gemini CLI + Antigravity)
    const skillDir = this.skillsDir(scope);
    const antigravityDir = this.antigravitySkillsDir(scope);
    const existingSkillDirs = new Set(
      fs.existsSync(skillDir) ? fs.readdirSync(skillDir).filter((f) => f.startsWith("trc-")) : [],
    );
    const newSkillDirs = new Set<string>();
    if (team.skills) {
      for (const skill of team.skills) {
        if (!skill.alwaysApply && !(skill.globs && skill.globs.length > 0)) {
          const dirName = `trc-${skill.id}`;
          newSkillDirs.add(dirName);
          actions.push({
            type: existingSkillDirs.has(dirName) ? "update" : "create",
            path: path.join(skillDir, dirName, "SKILL.md"),
            description: `skill: ${skill.id}`,
          });
          actions.push({
            type: "create",
            path: path.join(antigravityDir, dirName, "SKILL.md"),
            description: `skill (antigravity): ${skill.id}`,
          });
        }
      }
    }
    for (const d of existingSkillDirs) { if (!newSkillDirs.has(d)) actions.push({ type: "delete", path: path.join(skillDir, d) }); }

    // GEMINI.md
    const geminiMdPath = this.geminiMdPath();
    actions.push({
      type: fs.existsSync(geminiMdPath) ? "update" : "create",
      path: geminiMdPath,
      description: "teamrc section",
    });

    return actions;
  }

  writeTeam(team: TeamDefinition, scope: TeamScope = "global"): void {
    // Enrich team-knowledge skill with actual knowledge content
    const knowledgePath = scope === "project"
      ? `.teamrc/${knowledgeFileName(this.teamSlug)}`
      : `~/.teamrc/${knowledgeFileName(this.teamSlug)}`;
    const teamWithKnowledge = enrichTeamKnowledgeSkill(team, knowledgePath, this.readKnowledge());

    const agentDir = this.agentsDir(scope);
    if (!fs.existsSync(agentDir)) {
      fs.mkdirSync(agentDir, { recursive: true });
    }

    // Clean old trc-*.md agent files
    deleteTrcFiles(agentDir);

    // Write individual agent files (use enriched team so alwaysApply skills have knowledge content)
    for (const member of teamWithKnowledge.members) {
      validateAgentName(member.name);
      const fileName = `trc-${slugify(member.name)}.md`;
      const filePath = path.join(agentDir, fileName);
      const content = buildAgentFile(teamWithKnowledge.name, member, teamWithKnowledge);
      fs.writeFileSync(filePath, content);
    }

    // Route skills: alwaysApply/globs → inline in GEMINI.md, on-demand → skill dirs
    // Write to both .agents/skills/ (Gemini CLI) and .agent/skills/ (Antigravity)
    const skillDir = this.skillsDir(scope);
    const antigravityDir = this.antigravitySkillsDir(scope);
    cleanupSkillDirs(skillDir);
    cleanupSkillDirs(antigravityDir);
    if (teamWithKnowledge.skills) {
      for (const skill of teamWithKnowledge.skills) {
        if (!skill.alwaysApply && !(skill.globs && skill.globs.length > 0)) {
          if (!fs.existsSync(skillDir)) fs.mkdirSync(skillDir, { recursive: true });
          if (!fs.existsSync(antigravityDir)) fs.mkdirSync(antigravityDir, { recursive: true });
          writeSkillDir(skillDir, skill);
          writeSkillDir(antigravityDir, skill);
        }
      }
    }

    // Write built-in teamrc skills (on-demand slash commands)
    for (const skill of createBuiltInSkills(knowledgePath)) {
      if (!fs.existsSync(skillDir)) fs.mkdirSync(skillDir, { recursive: true });
      if (!fs.existsSync(antigravityDir)) fs.mkdirSync(antigravityDir, { recursive: true });
      writeSkillDir(skillDir, skill);
      writeSkillDir(antigravityDir, skill);
    }

    // Write GEMINI.md with team context and always-on skills (use enriched team)
    this.updateGeminiMd(teamWithKnowledge);
  }

  private updateGeminiMd(team: TeamDefinition): void {
    const marker = "<!-- teamrc -->";
    const markerEnd = "<!-- /teamrc -->";

    const safeName = sanitizeMarkerContent(team.name);
    const memberLines = team.members
      .map((m) => `- **${sanitizeMarkerContent(m.name)}**  --  ${sanitizeMarkerContent(m.role)}`)
      .join("\n");

    const sections = [
      marker,
      `## teamrc Team: ${safeName}`,
      "",
      "This project has a synced agent team managed by teamrc.",
      "",
      "Members:",
      memberLines,
      "",
      "Each member is defined as an agent in `.gemini/agents/`. Delegate tasks to them based on their roles.",
    ];

    // Inline alwaysApply/globs skills (Gemini has no native rules)
    const alwaysOnSkills = (team.skills || []).filter(
      (s) => s.alwaysApply || (s.globs && s.globs.length > 0),
    );
    if (alwaysOnSkills.length > 0) {
      sections.push("");
      sections.push("### Team Rules");
      sections.push("");
      for (const s of alwaysOnSkills) {
        const title = s.title || s.id;
        const body = typeof s.body === "string" ? s.body : "";
        sections.push(`#### ${sanitizeMarkerContent(title)}`);
        sections.push("");
        if (s.globs && s.globs.length > 0) {
          sections.push(`_Applies to: ${s.globs.join(", ")}_`);
          sections.push("");
        }
        if (body) {
          sections.push(body);
          sections.push("");
        }
      }
    }

    sections.push(markerEnd);
    const block = sections.join("\n");
    upsertMarkerBlock(this.geminiMdPath(), marker, markerEnd, block);
  }

  getKnowledgePath(scope: TeamScope = "project"): string {
    if (scope === "project") {
      return path.join(process.cwd(), ".teamrc", knowledgeFileName(this.teamSlug));
    }
    return path.join(os.homedir(), ".teamrc", knowledgeFileName(this.teamSlug));
  }

  readKnowledge(): string {
    for (const scope of ["project", "global"] as TeamScope[]) {
      const filePath = this.getKnowledgePath(scope);
      if (fs.existsSync(filePath)) {
        return fs.readFileSync(filePath, "utf-8");
      }
    }
    return "";
  }

  writeKnowledge(content: string): void {
    const p = this.getKnowledgePath();
    fs.mkdirSync(path.dirname(p), { recursive: true });
    fs.writeFileSync(p, content);
  }

  uninstall(requestedScope?: TeamScope): string[] {
    const actions: string[] = [];
    const { dir, scope } = requestedScope
      ? { dir: this.agentsDir(requestedScope), scope: requestedScope }
      : resolveAgentsDir(this.agentsDir("project"), this.agentsDir("global"));
    const trcFiles = listTrcFiles(dir);

    // Delete agent files
    for (const f of trcFiles) {
      fs.unlinkSync(path.join(dir, f));
    }
    if (trcFiles.length > 0) {
      actions.push(`Deleted ${trcFiles.length} agent file(s) from ${dir}`);
    }

    // Delete native skill directories (Gemini CLI + Antigravity)
    const skillsDir = this.skillsDir(scope);
    const antigravityDir = this.antigravitySkillsDir(scope);
    const skillCount = cleanupSkillDirs(skillsDir);
    const antigravityCount = cleanupSkillDirs(antigravityDir);
    if (skillCount > 0) {
      actions.push(`Deleted ${skillCount} skill directory(ies) from ${skillsDir}`);
    }
    if (antigravityCount > 0) {
      actions.push(`Deleted ${antigravityCount} skill directory(ies) from ${antigravityDir}`);
    }

    // Delete team knowledge
    const projectKnowledgeDir = path.join(process.cwd(), ".teamrc");
    const globalKnowledgeDir = path.join(os.homedir(), ".teamrc");
    for (const dir of [projectKnowledgeDir, globalKnowledgeDir]) {
      for (const deleted of deleteKnowledgeFiles(dir, this.teamSlug)) {
        actions.push(`Deleted ${deleted}`);
      }
    }

    // Remove teamrc section from GEMINI.md
    if (removeMarkerBlock(this.geminiMdPath(), "<!-- teamrc -->", "<!-- /teamrc -->")) {
      actions.push("Removed teamrc section from GEMINI.md");
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

  // Role comes from description field
  const role = description || "Agent";

  // Extract team name from body: "# Team: teamName"
  const teamMatch = body.match(/^# Team:\s*(.+)$/m);
  const teamName = teamMatch ? teamMatch[1].trim() : "my-team";

  // Extract soul: everything between team header and ## Rules / ## Skills / ## Teammates (or end)
  const bodyAfterHeader = body.replace(/^# Team:.*\n+/, "");
  const sectionIdx = bodyAfterHeader.search(/^## (Rules|Skills|Teammates)/m);
  const soulRaw = sectionIdx >= 0
    ? bodyAfterHeader.slice(0, sectionIdx).trim()
    : bodyAfterHeader.trim();

  // Only set soul if it's not the default generated text
  const isDefault = soulRaw.startsWith(`You are ${agentName},`);
  const soul = isDefault ? undefined : soulRaw || undefined;

  return { agentName, role, soul, teamName };
}

function buildAgentFile(teamName: string, member: TeamMember, team?: TeamDefinition): string {
  const name = `trc-${slugify(member.name)}`;
  const safeRole = escapeYamlString(member.role);
  const safeTeamNameText = sanitizeText(teamName);
  const safeRoleText = sanitizeText(member.role);

  const soulContent = member.soul
    ? member.soul
    : `You are ${member.name}, a ${safeRoleText} on the ${safeTeamNameText} team.\n\nFocus on your role and collaborate with your teammates.`;

  let skillsSection = "";
  if (team) {
    // Include alwaysApply skills since Gemini has no native rules system
    const resolvedSkills = resolveAgentSkills(member, team, { includeAlwaysApply: true });
    if (resolvedSkills.length > 0) {
      const skillBlocks = resolvedSkills.map((s) => {
        const title = s.title || s.id;
        const desc = s.description ? `${s.description}\n\n` : "";
        const body = typeof s.body === "string" ? s.body : "";
        return `### ${title}\n\n${desc}${body}`;
      }).join("\n\n");
      skillsSection = `\n## Skills\n\n${skillBlocks}\n`;
    }
  }

  const description = member.description
    ? escapeYamlString(member.description)
    : safeRole;

  return `---
name: "${name}"
description: "${description}"
---

# Team: ${safeTeamNameText}

${soulContent}
${skillsSection}`;
}
