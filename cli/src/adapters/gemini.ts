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
  type PlatformAdapter,
  type TeamDefinition,
  type TeamMember,
  type TeamScope,
} from "./base.js";
import { resolveAgentSkills } from "../resolve-skills.js";

export class GeminiAdapter implements PlatformAdapter {
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
    return path.join(this.baseDir(scope), "skills");
  }

  private geminiMdPath(): string {
    return path.join(process.cwd(), "GEMINI.md");
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

    // Write GEMINI.md knowledge marker block (team-level knowledge only)
    this.updateGeminiMd(team);
  }

  private cleanTbAgentFiles(dir: string): void {
    if (!fs.existsSync(dir)) return;
    for (const f of fs.readdirSync(dir)) {
      if (f.startsWith("trc-") && f.endsWith(".md")) {
        fs.unlinkSync(path.join(dir, f));
      }
    }
  }

  private updateGeminiMd(team: TeamDefinition): void {
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
      "Each member is defined as an agent in `.gemini/agents/`. Delegate tasks to them based on their roles.",
      markerEnd,
    ].join("\n");

    const filePath = this.geminiMdPath();

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
    if (scope === "project") {
      return path.join(process.cwd(), "teamrc-knowledge.md");
    }
    return path.join(this.baseDir("global"), "team-knowledge.md");
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

    // Remove teamrc section from GEMINI.md
    const filePath = this.geminiMdPath();
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
        actions.push("Removed teamrc section from GEMINI.md");
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
    const resolvedSkills = resolveAgentSkills(member, team);
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

  return `---
name: "${name}"
description: "${safeRole}"
---

# Team: ${safeTeamNameText}

${soulContent}
${skillsSection}`;
}
