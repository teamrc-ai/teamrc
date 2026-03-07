import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";
import { parse as parseYaml } from "yaml";
import {
  hashContent,
  validateAgentName,
  sanitizeMarkerContent,
  sanitizeText,
  slugify,
  escapeYamlString,
  type PlatformAdapter,
  type PortableAgent,
  type TeamDefinition,
  type TeamMember,
  type TeamScope,
} from "./base.js";
import { resolveAgentRules, resolveAgentSkills } from "../resolve-rules.js";

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

  /** Find the agents directory — check project first, fall back to global */
  private resolveAgentsDir(): { dir: string; scope: TeamScope } {
    const projectDir = this.agentsDir("project");
    if (fs.existsSync(projectDir)) {
      const tbFiles = this.listTbFiles(projectDir);
      if (tbFiles.length > 0) {
        return { dir: projectDir, scope: "project" };
      }
    }
    const globalDir = this.agentsDir("global");
    return { dir: globalDir, scope: "global" };
  }

  private listTbFiles(dir: string): string[] {
    if (!fs.existsSync(dir)) return [];
    return fs.readdirSync(dir).filter((f) => f.startsWith("trc-") && f.endsWith(".md"));
  }

  readTeam(): TeamDefinition | null {
    const { dir } = this.resolveAgentsDir();
    const files = this.listTbFiles(dir);
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

    // Write native rule files
    this.writeNativeRules(team, scope);

    // Write native skill directories
    this.writeNativeSkills(team, scope);

    this.updateClaudeMd(team, scope);
  }

  private writeNativeRules(team: TeamDefinition, scope: TeamScope): void {
    if (!team.rules || team.rules.length === 0) return;

    const dir = this.rulesDir(scope);
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true });
    }

    // Clean up old trc- rule files before writing new ones
    this.cleanTbRuleFiles(dir);

    for (const rule of team.rules) {
      if (typeof rule.body !== "string") continue;

      const fileName = `trc-${rule.id}.md`;
      const filePath = path.join(dir, fileName);

      let content: string;
      if (rule.globs && rule.globs.length > 0) {
        const pathsYaml = rule.globs.map((g) => `  - "${g}"`).join("\n");
        content = `---\npaths:\n${pathsYaml}\n---\n\n${rule.body}\n`;
      } else {
        content = `${rule.body}\n`;
      }

      fs.writeFileSync(filePath, content);
    }
  }

  private writeNativeSkills(team: TeamDefinition, scope: TeamScope): void {
    if (!team.skills || team.skills.length === 0) return;

    const dir = this.skillsDir(scope);
    if (!fs.existsSync(dir)) {
      fs.mkdirSync(dir, { recursive: true });
    }

    // Clean up old trc- skill directories before writing new ones
    this.cleanTbSkillDirs(dir);

    for (const skill of team.skills) {
      if (skill.body && typeof skill.body !== "string") continue;

      const skillDir = path.join(dir, `trc-${skill.id}`);
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

      const body = typeof skill.body === "string" ? skill.body : "";
      const content = `---\n${frontmatterLines.join("\n")}\n---\n\n${body}\n`;

      fs.writeFileSync(path.join(skillDir, "SKILL.md"), content);
    }
  }

  private cleanTbRuleFiles(dir: string): void {
    if (!fs.existsSync(dir)) return;
    for (const f of fs.readdirSync(dir)) {
      if (f.startsWith("trc-") && f.endsWith(".md")) {
        fs.unlinkSync(path.join(dir, f));
      }
    }
  }

  private cleanTbSkillDirs(dir: string): void {
    if (!fs.existsSync(dir)) return;
    for (const f of fs.readdirSync(dir)) {
      if (f.startsWith("trc-")) {
        const fullPath = path.join(dir, f);
        if (fs.statSync(fullPath).isDirectory()) {
          fs.rmSync(fullPath, { recursive: true, force: true });
        }
      }
    }
  }

  private updateClaudeMd(team: TeamDefinition, scope: TeamScope): void {
    const teamSection = buildClaudeMdSection(team);

    if (scope === "project") {
      const claudeMdPath = path.join(process.cwd(), "CLAUDE.md");
      if (!fs.existsSync(claudeMdPath)) {
        fs.writeFileSync(claudeMdPath, `# Project Configuration\n${teamSection}`);
      } else {
        const existing = fs.readFileSync(claudeMdPath, "utf-8");
        const cleaned = existing.replace(
          /\n<!-- teamrc -->[\s\S]*?<!-- \/teamrc -->/,
          "",
        );
        fs.writeFileSync(claudeMdPath, cleaned.trimEnd() + "\n" + teamSection);
      }
    }
  }

  private knowledgePath(scope: TeamScope = "project"): string {
    if (scope === "project") {
      return path.join(process.cwd(), ".claude", "team-knowledge.md");
    }
    return path.join(this.claudeDir, "team-knowledge.md");
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

  appendKnowledge(entries: string[]): void {
    if (entries.length === 0) return;

    const filePath = this.knowledgePath("project");
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
        `# Team Knowledge\n\nShared findings and decisions synced by teamrc.\n\n${newContent}\n`,
      );
    }
  }

  getHashes(): Record<string, string> {
    const hashes: Record<string, string> = {};

    // Hash each agent file as portable JSON
    const { dir, scope } = this.resolveAgentsDir();
    for (const file of this.listTbFiles(dir)) {
      const content = fs.readFileSync(path.join(dir, file), "utf-8");
      const parsed = parseAgentFile(content);
      if (!parsed) continue;
      const portable = toPortableJson(parsed);
      hashes[`agent:${parsed.agentName}`] = hashContent(portable);
    }

    // Hash native rule files
    const rulesDir = this.rulesDir(scope);
    if (fs.existsSync(rulesDir)) {
      for (const f of fs.readdirSync(rulesDir)) {
        if (f.startsWith("trc-") && f.endsWith(".md")) {
          const content = fs.readFileSync(path.join(rulesDir, f), "utf-8");
          const ruleId = f.replace(/^trc-/, "").replace(/\.md$/, "");
          hashes[`rule:${ruleId}`] = hashContent(content);
        }
      }
    }

    // Hash native skill files
    const skillsDir = this.skillsDir(scope);
    if (fs.existsSync(skillsDir)) {
      for (const f of fs.readdirSync(skillsDir)) {
        if (f.startsWith("trc-")) {
          const skillFile = path.join(skillsDir, f, "SKILL.md");
          if (fs.existsSync(skillFile)) {
            const content = fs.readFileSync(skillFile, "utf-8");
            const skillId = f.replace(/^trc-/, "");
            hashes[`skill:${skillId}`] = hashContent(content);
          }
        }
      }
    }

    // Hash team knowledge file
    for (const scope of ["project", "global"] as TeamScope[]) {
      const kPath = this.knowledgePath(scope);
      if (fs.existsSync(kPath)) {
        const content = fs.readFileSync(kPath, "utf-8");
        hashes[`knowledge:${scope}`] = hashContent(content);
      }
    }

    return hashes;
  }

  watchPaths(): string[] {
    const paths = [
      this.knowledgePath("project"),
      this.knowledgePath("global"),
    ];
    // Watch both possible agent directories
    const projectAgents = this.agentsDir("project");
    const globalAgents = this.agentsDir("global");
    if (fs.existsSync(projectAgents)) paths.push(projectAgents);
    if (fs.existsSync(globalAgents)) paths.push(globalAgents);

    // Watch rules and skills directories
    for (const scope of ["project", "global"] as TeamScope[]) {
      const rDir = this.rulesDir(scope);
      const sDir = this.skillsDir(scope);
      if (fs.existsSync(rDir)) paths.push(rDir);
      if (fs.existsSync(sDir)) paths.push(sDir);
    }

    return paths;
  }

  writeFile(key: string, content: string): void {
    if (key.startsWith("agent:")) {
      this.writeAgentFromPortable(key, content);
      return;
    }
    if (key === "knowledge:project") {
      this.writeKnowledge(content);
      return;
    }
    if (key === "knowledge:global") {
      const dir = path.dirname(this.knowledgePath("global"));
      if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
      fs.writeFileSync(this.knowledgePath("global"), content);
      return;
    }
  }

  readFile(key: string): string | null {
    if (key.startsWith("agent:")) {
      return this.readAgentAsPortable(key);
    }
    if (key === "knowledge:project") {
      const p = this.knowledgePath("project");
      return fs.existsSync(p) ? fs.readFileSync(p, "utf-8") : null;
    }
    if (key === "knowledge:global") {
      const p = this.knowledgePath("global");
      return fs.existsSync(p) ? fs.readFileSync(p, "utf-8") : null;
    }
    return null;
  }

  /** Read a native agent file and return portable JSON */
  private readAgentAsPortable(key: string): string | null {
    const agentName = key.replace("agent:", "");
    const { dir } = this.resolveAgentsDir();
    const filePath = path.join(dir, `trc-${slugify(agentName)}.md`);
    if (!fs.existsSync(filePath)) return null;

    const content = fs.readFileSync(filePath, "utf-8");
    const parsed = parseAgentFile(content);
    if (!parsed) return null;
    return toPortableJson(parsed);
  }

  /** Write a native agent file from portable JSON */
  private writeAgentFromPortable(key: string, json: string): void {
    let portable: PortableAgent;
    try {
      portable = JSON.parse(json) as PortableAgent;
    } catch {
      console.warn(`Skipping malformed JSON for ${key}`);
      return;
    }
    validateAgentName(portable.name);
    const { dir } = this.resolveAgentsDir();
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });

    // Read existing team to get full member list for teammates section
    const team = this.readTeam();
    const allMembers: TeamMember[] = team?.members ?? [];

    // Update or add this member
    const idx = allMembers.findIndex((m) => m.name === portable.name);
    const member: TeamMember = { name: portable.name, role: portable.role, soul: portable.soul };
    if (idx >= 0) {
      allMembers[idx] = member;
    } else {
      allMembers.push(member);
    }

    const filePath = path.join(dir, `trc-${slugify(portable.name)}.md`);
    const content = buildAgentFile(portable.teamName, member, allMembers);
    fs.writeFileSync(filePath, content);
  }

  uninstall(): string[] {
    const actions: string[] = [];
    const { dir, scope } = this.resolveAgentsDir();
    const tbFiles = this.listTbFiles(dir);

    // Delete agent files
    for (const f of tbFiles) {
      fs.unlinkSync(path.join(dir, f));
    }
    if (tbFiles.length > 0) {
      actions.push(`Deleted ${tbFiles.length} agent file(s) from ${dir}`);
    }

    // Delete native rule files
    const rulesDir = this.rulesDir(scope);
    if (fs.existsSync(rulesDir)) {
      const tbRuleFiles = fs.readdirSync(rulesDir).filter((f) => f.startsWith("trc-") && f.endsWith(".md"));
      for (const f of tbRuleFiles) {
        fs.unlinkSync(path.join(rulesDir, f));
      }
      if (tbRuleFiles.length > 0) {
        actions.push(`Deleted ${tbRuleFiles.length} native rule file(s) from ${rulesDir}`);
      }
    }

    // Delete native skill directories
    const skillsDir = this.skillsDir(scope);
    if (fs.existsSync(skillsDir)) {
      const tbSkillDirs = fs.readdirSync(skillsDir).filter((f) => {
        return f.startsWith("trc-") && fs.statSync(path.join(skillsDir, f)).isDirectory();
      });
      for (const f of tbSkillDirs) {
        fs.rmSync(path.join(skillsDir, f), { recursive: true, force: true });
      }
      if (tbSkillDirs.length > 0) {
        actions.push(`Deleted ${tbSkillDirs.length} native skill directory(ies) from ${skillsDir}`);
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
      if (fs.existsSync(claudeMdPath)) {
        const content = fs.readFileSync(claudeMdPath, "utf-8");
        const cleaned = content.replace(
          /\n<!-- teamrc -->[\s\S]*?<!-- \/teamrc -->/,
          "",
        );
        if (cleaned !== content) {
          fs.writeFileSync(claudeMdPath, cleaned.trimEnd() + "\n");
          actions.push(`Removed teamrc section from ${claudeMdPath}`);
        }
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

/** Convert parsed agent to portable JSON string (wire format) */
function toPortableJson(parsed: ParsedAgent): string {
  const obj: PortableAgent = {
    name: parsed.agentName,
    role: parsed.role,
    teamName: parsed.teamName,
    ...(parsed.soul ? { soul: parsed.soul } : {}),
  };
  return JSON.stringify(obj);
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

  let rulesSection = "";
  if (team) {
    const resolvedRules = resolveAgentRules(member, team);
    if (resolvedRules.length > 0) {
      const ruleBlocks = resolvedRules.map((r) => {
        const title = r.title || r.id;
        const body = typeof r.body === "string" ? r.body : "";
        return `### ${title}\n\n${body}`;
      }).join("\n\n");
      rulesSection += `\n## Rules\n\n${ruleBlocks}\n`;
    }

    const resolvedSkills = resolveAgentSkills(member, team);
    if (resolvedSkills.length > 0) {
      const skillBlocks = resolvedSkills.map((s) => {
        const title = s.title || s.id;
        const desc = s.description ? `${s.description}\n\n` : "";
        const body = s.body ? (typeof s.body === "string" ? s.body : "") : "";
        return `### ${title}\n\n${desc}${body}`;
      }).join("\n\n");
      rulesSection += `\n## Skills\n\n${skillBlocks}\n`;
    }
  }

  const teammates = allMembers
    .filter((m) => m.name !== member.name)
    .map((m) => `- **${sanitizeText(m.name)}** — ${sanitizeText(m.role)}`)
    .join("\n");

  return `---
name: ${name}
description: "${safeRole} on the ${safeTeamName} team. Use when tasks relate to ${safeRole.toLowerCase()}."
model: inherit
---

# Team: ${safeTeamNameText}

${body}
${rulesSection}
## Teammates

${teammates}

## Team Knowledge

Shared findings and decisions are stored in \`.claude/team-knowledge.md\`. Read this file at the start of every session for context from other agents and machines. When you discover something important, append it to that file.
`;
}

function buildClaudeMdSection(team: TeamDefinition): string {
  const safeName = sanitizeMarkerContent(team.name);
  const memberLines = team.members
    .map((m) => `- **${sanitizeMarkerContent(m.name)}** — ${sanitizeMarkerContent(m.role)}`)
    .join("\n");

  return `
<!-- teamrc -->
## teamrc Team: ${safeName}

This project has a synced agent team managed by teamrc.

Members:
${memberLines}

Each member is defined as a subagent in \`.claude/agents/\`. Delegate tasks to them based on their roles.

### Team Knowledge
Shared findings and decisions are stored in \`.claude/team-knowledge.md\`. Read this file at the start of every session for context from other agents and machines. When you discover something important (architecture decisions, gotchas, debugging insights), append it to this file so other team members can benefit.
<!-- /teamrc -->`;
}
