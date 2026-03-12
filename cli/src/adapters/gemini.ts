import * as fs from "node:fs";
import * as path from "node:path";
import { sanitizeMarkerContent, writeSkillDir, cleanupSkillDirs, type PlatformAdapter, type TeamDefinition } from "./base.js";
import { resolveAgentRules, resolveAgentSkills } from "../resolve-rules.js";

export class GeminiAdapter implements PlatformAdapter {
  readonly supportsSync = false;
  private geminiMdPath(): string {
    return path.join(process.cwd(), "GEMINI.md");
  }

  private skillsDir(): string {
    return path.join(process.cwd(), ".gemini", "skills");
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

    const marker = "<!-- teamrc -->";
    const markerEnd = "<!-- /teamrc -->";

    const sections = [`# Team: ${sanitizeMarkerContent(team.name)}`, ""];

    for (const member of team.members) {
      sections.push(`## ${sanitizeMarkerContent(member.name)}`, "");
      sections.push(`**Role:** ${sanitizeMarkerContent(member.role)}`, "");

      const agentRules = resolveAgentRules(member, team);
      if (agentRules.length > 0) {
        sections.push("### Rules", "");
        for (const r of agentRules) {
          const title = sanitizeMarkerContent(r.title || r.id);
          const body = typeof r.body === "string" ? sanitizeMarkerContent(r.body) : "";
          sections.push(`**${title}:** ${body}`, "");
        }
      }

      const agentSkills = resolveAgentSkills(member, team);
      if (agentSkills.length > 0) {
        sections.push("### Skills", "");
        for (const s of agentSkills) {
          const title = s.title || s.id;
          const desc = s.description ? sanitizeMarkerContent(s.description) : "";
          const body = s.body ? (typeof s.body === "string" ? sanitizeMarkerContent(s.body) : "") : "";
          sections.push(`**${sanitizeMarkerContent(title)}**`, "", ...(desc ? [desc, ""] : []), ...(body ? [body, ""] : []));
        }
      }
    }

    const block = [marker, ...sections, markerEnd].join("\n");
    const filePath = this.geminiMdPath();

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
  getFileMtime(_key: string): number { return 0; }
  uninstall(): string[] {
    const actions: string[] = [];

    // Clean up skill directories
    const skillCount = cleanupSkillDirs(this.skillsDir());
    if (skillCount > 0) {
      actions.push(`Deleted ${skillCount} teamrc gemini skill(s)`);
    }

    const filePath = this.geminiMdPath();
    if (!fs.existsSync(filePath)) return actions;
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
    return actions;
  }
}
