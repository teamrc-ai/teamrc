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
  writeSkillDir,
  cleanupSkillDirs,
  type FileAction,
  type PlatformAdapter,
  type TeamDefinition,
  type TeamMember,
  type TeamScope,
} from "./base.js";
import { resolveAgentSkills } from "../resolve-skills.js";

export class OpenClawAdapter implements PlatformAdapter {
  private baseDir(scope: TeamScope): string {
    if (scope === "global") {
      return path.join(os.homedir(), ".agents");
    }
    return path.join(process.cwd(), ".agents");
  }

  private agentsDir(scope: TeamScope): string {
    return path.join(this.baseDir(scope), "agents");
  }

  private skillsDir(scope: TeamScope): string {
    return path.join(this.baseDir(scope), "skills");
  }

  private agentsMdPath(): string {
    return path.join(process.cwd(), "AGENTS.md");
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

  planWrite(team: TeamDefinition, scope: TeamScope = "global"): FileAction[] {
    const actions: FileAction[] = [];
    const agentDir = this.agentsDir(scope);

    // Agent files
    const existingSlugs = new Set(
      this.listTbFiles(agentDir).map((f) => f.replace(/\.md$/, "")),
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

    // Skill directories
    const skillDir = this.skillsDir(scope);
    const existingSkillDirs = new Set(
      fs.existsSync(skillDir) ? fs.readdirSync(skillDir).filter((f) => f.startsWith("trc-")) : [],
    );
    const newSkillDirs = new Set<string>();
    if (team.skills) {
      for (const skill of team.skills) {
        const dirName = `trc-${skill.id}`;
        newSkillDirs.add(dirName);
        actions.push({
          type: existingSkillDirs.has(dirName) ? "update" : "create",
          path: path.join(skillDir, dirName, "SKILL.md"),
          description: `skill: ${skill.id}`,
        });
      }
    }
    for (const d of existingSkillDirs) { if (!newSkillDirs.has(d)) actions.push({ type: "delete", path: path.join(skillDir, d) }); }

    // AGENTS.md
    const agentsMdPath = this.agentsMdPath();
    actions.push({
      type: fs.existsSync(agentsMdPath) ? "update" : "create",
      path: agentsMdPath,
      description: "teamrc routing",
    });

    return actions;
  }

  writeTeam(team: TeamDefinition, scope: TeamScope = "global"): void {
    const agentDir = this.agentsDir(scope);
    if (!fs.existsSync(agentDir)) {
      fs.mkdirSync(agentDir, { recursive: true });
    }

    // Clean old trc-*.md agent files
    this.cleanTbAgentFiles(agentDir);

    // Write individual agent files
    for (const member of team.members) {
      validateAgentName(member.name);
      const fileName = `trc-${slugify(member.name)}.md`;
      const filePath = path.join(agentDir, fileName);
      const content = buildAgentFile(team.name, member, team);
      fs.writeFileSync(filePath, content);
    }

    // Write native skill directories
    const skillDir = this.skillsDir(scope);
    cleanupSkillDirs(skillDir);
    if (team.skills) {
      if (!fs.existsSync(skillDir)) {
        fs.mkdirSync(skillDir, { recursive: true });
      }
      for (const skill of team.skills) {
        writeSkillDir(skillDir, skill);
      }
    }

    // Write AGENTS.md routing block (team-level knowledge only)
    this.updateAgentsMd(team);
  }

  private cleanTbAgentFiles(dir: string): void {
    if (!fs.existsSync(dir)) return;
    for (const f of fs.readdirSync(dir)) {
      if (f.startsWith("trc-") && f.endsWith(".md")) {
        fs.unlinkSync(path.join(dir, f));
      }
    }
  }

  private updateAgentsMd(team: TeamDefinition): void {
    const marker = "<!-- teamrc -->";
    const markerEnd = "<!-- /teamrc -->";

    const safeName = sanitizeMarkerContent(team.name);
    const memberLines = team.members
      .map((m) => `- **${sanitizeMarkerContent(m.name)}** — ${sanitizeMarkerContent(m.role)}`)
      .join("\n");

    const block = [
      marker,
      `## teamrc Team: ${safeName}`,
      "",
      "This project has a synced agent team managed by teamrc.",
      "",
      "Members:",
      memberLines,
      "",
      "Each member is defined as an agent in `.agents/agents/`. Delegate tasks to them based on their roles.",
      markerEnd,
    ].join("\n");

    const filePath = this.agentsMdPath();

    if (fs.existsSync(filePath)) {
      let content = fs.readFileSync(filePath, "utf-8");
      const regex = new RegExp(
        `${marker.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}[\\s\\S]*?${markerEnd.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}`,
      );
      content = regex.test(content)
        ? content.replace(regex, block)
        : content.trimEnd() + "\n\n" + block + "\n";
      fs.writeFileSync(filePath, content);
    } else {
      fs.writeFileSync(filePath, block + "\n");
    }
  }

  private knowledgePath(scope: TeamScope = "project"): string {
    return path.join(this.baseDir(scope), "team-knowledge.md");
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
    const { dir, scope } = this.resolveAgentsDir();
    const tbFiles = this.listTbFiles(dir);

    // Delete agent files
    for (const f of tbFiles) {
      fs.unlinkSync(path.join(dir, f));
    }
    if (tbFiles.length > 0) {
      actions.push(`Deleted ${tbFiles.length} agent file(s) from ${dir}`);
    }

    // Delete native skill directories
    const skillsDir = this.skillsDir(scope);
    const skillCount = cleanupSkillDirs(skillsDir);
    if (skillCount > 0) {
      actions.push(`Deleted ${skillCount} skill directory(ies) from ${skillsDir}`);
    }

    // Delete team knowledge
    for (const s of ["project", "global"] as TeamScope[]) {
      const kPath = this.knowledgePath(s);
      if (fs.existsSync(kPath)) {
        fs.unlinkSync(kPath);
        actions.push(`Deleted ${kPath}`);
      }
    }

    // Remove teamrc section from AGENTS.md
    const filePath = this.agentsMdPath();
    if (fs.existsSync(filePath)) {
      const content = fs.readFileSync(filePath, "utf-8");
      const marker = "<!-- teamrc -->";
      const markerEnd = "<!-- /teamrc -->";
      const regex = new RegExp(
        `\\n?${marker.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}[\\s\\S]*?${markerEnd.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\n?`,
      );
      const cleaned = content.replace(regex, "\n");
      if (cleaned !== content) {
        fs.writeFileSync(filePath, cleaned.trimEnd() + "\n");
        actions.push("Removed teamrc section from AGENTS.md");
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

  // Extract soul: everything between team header and ## Skills / ## Teammates (or end)
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

function buildAgentFile(teamName: string, member: TeamMember, team?: TeamDefinition): string {
  const name = `trc-${slugify(member.name)}`;
  const safeRole = escapeYamlString(member.role);
  const safeTeamNameText = sanitizeText(teamName);
  const safeRoleText = sanitizeText(member.role);

  const soulContent = member.soul
    ? member.soul
    : `You are ${member.name}, a ${safeRoleText} on the ${safeTeamNameText} team.\n\nFocus on your role and collaborate with your teammates.`;

  // Build frontmatter with native skills list for per-agent skills
  let skillsFrontmatter = "";
  let skillsSection = "";
  if (team) {
    const resolvedSkills = resolveAgentSkills(member, team);
    if (resolvedSkills.length > 0) {
      // Add skills to frontmatter (OpenHands native per-agent skills)
      const skillNames = resolvedSkills.map((s) => `  - trc-${s.id}`).join("\n");
      skillsFrontmatter = `\nskills:\n${skillNames}`;

      // Also inline skill content in body for context
      const skillBlocks = resolvedSkills.map((s) => {
        const title = s.title || s.id;
        const desc = s.description ? `${s.description}\n\n` : "";
        const body = typeof s.body === "string" ? s.body : "";
        return `### ${title}\n\n${desc}${body}`;
      }).join("\n\n");
      skillsSection = `\n## Skills\n\n${skillBlocks}\n`;
    }
  }

  return `---
name: "${name}"
description: "${safeRole}"${skillsFrontmatter}
---

# Team: ${safeTeamNameText}

${soulContent}
${skillsSection}`;
}
