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
  listTrcFiles,
  deleteTrcFiles,
  resolveAgentsDir,
  upsertMarkerBlock,
  removeMarkerBlock,
  cleanupSkillDirs,
  resolveAgentSkills,
  type FileAction,
  type PlatformAdapter,
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

  private rulesDir(scope: TeamScope): string {
    if (scope === "project") {
      return path.join(process.cwd(), ".claude", "rules");
    }
    return path.join(this.claudeDir, "rules");
  }

  private skillsDir(scope: TeamScope): string {
    if (scope === "project") {
      return path.join(process.cwd(), ".claude", "skills");
    }
    return path.join(this.claudeDir, "skills");
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
    const dir = this.agentsDir(scope);

    // Existing agent files that will be deleted
    const existingSlugs = new Set(
      listTrcFiles(dir).map((f) => f.replace(/\.md$/, "")),
    );
    const newSlugs = new Set<string>();

    for (const member of team.members) {
      validateAgentName(member.name);
      const slug = `trc-${slugify(member.name)}`;
      newSlugs.add(slug);
      const filePath = path.join(dir, `${slug}.md`);
      actions.push({
        type: existingSlugs.has(slug) ? "update" : "create",
        path: filePath,
        description: `agent: ${member.name}`,
      });
    }

    for (const slug of existingSlugs) {
      if (!newSlugs.has(slug)) {
        actions.push({ type: "delete", path: path.join(dir, `${slug}.md`), description: "orphaned agent" });
      }
    }

    // Skills: rules and skill dirs
    const rulesDir = this.rulesDir(scope);
    const skillsDir = this.skillsDir(scope);
    const existingRules = new Set(
      fs.existsSync(rulesDir) ? fs.readdirSync(rulesDir).filter((f) => f.startsWith("trc-") && f.endsWith(".md")) : [],
    );
    const existingSkillDirs = new Set(
      fs.existsSync(skillsDir) ? fs.readdirSync(skillsDir).filter((f) => f.startsWith("trc-")) : [],
    );
    const newRules = new Set<string>();
    const newSkillDirs = new Set<string>();

    if (team.skills) {
      for (const skill of team.skills) {
        if (typeof skill.body !== "string") continue;
        if (skill.alwaysApply || (skill.globs && skill.globs.length > 0)) {
          const fileName = `trc-${skill.id}.md`;
          newRules.add(fileName);
          actions.push({
            type: existingRules.has(fileName) ? "update" : "create",
            path: path.join(rulesDir, fileName),
            description: `rule: ${skill.id}`,
          });
        } else {
          const dirName = `trc-${skill.id}`;
          newSkillDirs.add(dirName);
          actions.push({
            type: existingSkillDirs.has(dirName) ? "update" : "create",
            path: path.join(skillsDir, dirName, "SKILL.md"),
            description: `skill: ${skill.id}`,
          });
        }
      }
    }

    for (const f of existingRules) { if (!newRules.has(f)) actions.push({ type: "delete", path: path.join(rulesDir, f) }); }
    for (const d of existingSkillDirs) { if (!newSkillDirs.has(d)) actions.push({ type: "delete", path: path.join(skillsDir, d) }); }

    if (scope === "project") {
      const claudeMdPath = path.join(process.cwd(), "CLAUDE.md");
      actions.push({
        type: fs.existsSync(claudeMdPath) ? "update" : "create",
        path: claudeMdPath,
        description: "teamrc section",
      });
    }

    return actions;
  }

  writeTeam(team: TeamDefinition, scope: TeamScope = "global"): void {
    const dir = this.agentsDir(scope);
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true });
    }

    for (const member of team.members) {
      validateAgentName(member.name);
      const fileName = `trc-${slugify(member.name)}.md`;
      const filePath = path.join(dir, fileName);
      const content = buildAgentFile(team.name, member, team.members, team);
      fs.writeFileSync(filePath, content);
    }

    // Route skills: alwaysApply/globs → native rules, otherwise → skill dirs
    this.writeSkillsAsNativeFiles(team, scope);

    this.updateClaudeMd(team, scope);
  }

  private writeSkillsAsNativeFiles(team: TeamDefinition, scope: TeamScope): void {
    if (!team.skills || team.skills.length === 0) {
      // Still clean up old files even if no skills
      deleteTrcFiles(this.rulesDir(scope));
      cleanupSkillDirs(this.skillsDir(scope));
      return;
    }

    const rulesDir = this.rulesDir(scope);
    const skillsBaseDir = this.skillsDir(scope);

    // Clean up old files before writing new ones
    deleteTrcFiles(rulesDir);
    cleanupSkillDirs(skillsBaseDir);

    for (const skill of team.skills) {
      if (typeof skill.body !== "string") continue;

      if (skill.alwaysApply || (skill.globs && skill.globs.length > 0)) {
        // Write as native rule file
        if (!fs.existsSync(rulesDir)) {
          fs.mkdirSync(rulesDir, { recursive: true });
        }

        const fileName = `trc-${skill.id}.md`;
        const filePath = path.join(rulesDir, fileName);

        let content: string;
        if (skill.globs && skill.globs.length > 0) {
          const sanitizedGlobs = skill.globs.map((g) => g.replace(/[\n\r]/g, ""));
          const pathsYaml = sanitizedGlobs.map((g) => `  - "${escapeYamlString(g)}"`).join("\n");
          content = `---\npaths:\n${pathsYaml}\n---\n\n${skill.body}\n`;
        } else {
          content = `${skill.body}\n`;
        }

        fs.writeFileSync(filePath, content);
      } else {
        // Write as SKILL.md directory
        if (!fs.existsSync(skillsBaseDir)) {
          fs.mkdirSync(skillsBaseDir, { recursive: true });
        }

        const skillDir = path.join(skillsBaseDir, `trc-${skill.id}`);
        if (!fs.existsSync(skillDir)) {
          fs.mkdirSync(skillDir, { recursive: true });
        }

        const frontmatterLines: string[] = [];
        frontmatterLines.push(`name: trc-${skill.id}`);
        if (skill.title) {
          frontmatterLines.push(`title: "${escapeYamlString(skill.title)}"`);
        }
        if (skill.description) {
          frontmatterLines.push(`description: "${escapeYamlString(skill.description)}"`);
        }

        const content = `---\n${frontmatterLines.join("\n")}\n---\n\n${skill.body}\n`;
        fs.writeFileSync(path.join(skillDir, "SKILL.md"), content);
      }
    }
  }

  private updateClaudeMd(team: TeamDefinition, scope: TeamScope): void {
    if (scope === "project") {
      const claudeMdPath = path.join(process.cwd(), "CLAUDE.md");
      const block = buildClaudeMdSection(team);
      upsertMarkerBlock(claudeMdPath, "<!-- teamrc -->", "<!-- /teamrc -->", block, "# Project Configuration\n\n");
    }
  }

  private knowledgePath(scope: TeamScope = "project"): string {
    if (scope === "project") {
      return path.join(process.cwd(), "teamrc-knowledge.md");
    }
    return path.join(this.claudeDir, "teamrc-knowledge.md");
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

  uninstall(): string[] {
    const actions: string[] = [];
    const { dir, scope } = resolveAgentsDir(this.agentsDir("project"), this.agentsDir("global"));
    const trcFiles = listTrcFiles(dir);

    // Delete agent files
    for (const f of trcFiles) {
      fs.unlinkSync(path.join(dir, f));
    }
    if (trcFiles.length > 0) {
      actions.push(`Deleted ${trcFiles.length} agent file(s) from ${dir}`);
    }

    // Delete native rule files (skills written as rules)
    const rulesDir = this.rulesDir(scope);
    const ruleFiles = listTrcFiles(rulesDir);
    for (const f of ruleFiles) {
      fs.unlinkSync(path.join(rulesDir, f));
    }
    if (ruleFiles.length > 0) {
      actions.push(`Deleted ${ruleFiles.length} native skill rule(s) from ${rulesDir}`);
    }

    // Delete native skill directories
    const skillsDir = this.skillsDir(scope);
    if (fs.existsSync(skillsDir)) {
      const trcSkillDirs = fs.readdirSync(skillsDir).filter((f) => {
        return f.startsWith("trc-") && fs.statSync(path.join(skillsDir, f)).isDirectory();
      });
      for (const f of trcSkillDirs) {
        fs.rmSync(path.join(skillsDir, f), { recursive: true, force: true });
      }
      if (trcSkillDirs.length > 0) {
        actions.push(`Deleted ${trcSkillDirs.length} native skill directory(ies) from ${skillsDir}`);
      }
    }

    // Delete team knowledge
    for (const s of ["project", "global"] as TeamScope[]) {
      const kPath = this.knowledgePath(s);
      if (fs.existsSync(kPath)) {
        fs.unlinkSync(kPath);
        actions.push(`Deleted ${kPath}`);
      }
    }

    // Remove teamrc section from CLAUDE.md
    if (scope === "project") {
      const claudeMdPath = path.join(process.cwd(), "CLAUDE.md");
      if (removeMarkerBlock(claudeMdPath, "<!-- teamrc -->", "<!-- /teamrc -->")) {
        actions.push(`Removed teamrc section from ${claudeMdPath}`);
      }
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

  // Extract agent name: strip trc- prefix
  const agentName = name.startsWith("trc-") ? name.slice(4) : name;

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

function buildAgentFile(teamName: string, member: TeamMember, allMembers: TeamMember[], team?: TeamDefinition): string {
  const name = `trc-${slugify(member.name)}`;
  const safeRole = escapeYamlString(member.role);
  const safeTeamName = escapeYamlString(teamName);
  const safeTeamNameText = sanitizeText(teamName);
  const safeRoleText = sanitizeText(member.role);
  const body = member.soul
    ? member.soul
    : `You are ${member.name}, a ${safeRoleText} on the ${safeTeamNameText} team.\n\nFocus on your role and collaborate with your teammates.`;

  // Build frontmatter with native skills list for per-agent skills
  let skillsFrontmatter = "";
  let skillsSection = "";
  if (team) {
    const resolvedSkills = resolveAgentSkills(member, team);
    if (resolvedSkills.length > 0) {
      // Add skills to frontmatter (Claude Code native per-agent skills)
      const skillNames = resolvedSkills.map((s) => `  - trc-${s.id}`).join("\n");
      skillsFrontmatter = `\nskills:\n${skillNames}`;

      // Also inline skill content in body
      const skillBlocks = resolvedSkills.map((s) => {
        const title = s.title || s.id;
        const desc = s.description ? `${s.description}\n\n` : "";
        const skillBody = typeof s.body === "string" ? s.body : "";
        return `### ${title}\n\n${desc}${skillBody}`;
      }).join("\n\n");
      skillsSection = `\n## Skills\n\n${skillBlocks}\n`;
    }
  }

  const teammates = allMembers
    .filter((m) => m.name !== member.name)
    .map((m) => `- **${sanitizeText(m.name)}** — ${sanitizeText(m.role)}`)
    .join("\n");

  return `---
name: ${name}
description: "${safeRole} on the ${safeTeamName} team. Use when tasks relate to ${safeRole.toLowerCase()}."
model: inherit${skillsFrontmatter}
---

# Team: ${safeTeamNameText}

${body}
${skillsSection}
## Teammates

${teammates}

## Team Knowledge

Shared findings and decisions are stored in \`.claude/teamrc-knowledge.md\`. Read this file at the start of every session for context from other agents and machines. When you discover something important, append it to that file.
`;
}

function buildClaudeMdSection(team: TeamDefinition): string {
  const safeName = sanitizeMarkerContent(team.name);
  const memberLines = team.members
    .map((m) => `- **${sanitizeMarkerContent(m.name)}** — ${sanitizeMarkerContent(m.role)}`)
    .join("\n");

  return `<!-- teamrc -->
## teamrc Team: ${safeName}

This project has a synced agent team managed by teamrc.

Members:
${memberLines}

Each member is defined as a subagent in \`.claude/agents/\`. Delegate tasks to them based on their roles.

### Team Knowledge
Shared findings and decisions are stored in \`.claude/teamrc-knowledge.md\`. Read this file at the start of every session for context from other agents and machines. When you discover something important (architecture decisions, gotchas, debugging insights), append it to this file so other team members can benefit.
<!-- /teamrc -->`;
}
