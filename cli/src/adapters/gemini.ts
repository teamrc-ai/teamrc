import * as fs from "node:fs";
import * as path from "node:path";
import { sanitizeMarkerContent, type PlatformAdapter, type TeamDefinition } from "./base.js";

export class GeminiAdapter implements PlatformAdapter {
  private geminiMdPath(): string {
    return path.join(process.cwd(), "GEMINI.md");
  }

  readTeam(): TeamDefinition | null { return null; }

  writeTeam(team: TeamDefinition): void {
    const marker = "<!-- teambridge -->";
    const markerEnd = "<!-- /teambridge -->";

    const memberLines = team.members
      .map((m) => `- **${sanitizeMarkerContent(m.name)}** — ${sanitizeMarkerContent(m.role)}`)
      .join("\n");

    const sections = [`# Team: ${sanitizeMarkerContent(team.name)}`, "", memberLines];

    if (team.rules && team.rules.length > 0) {
      sections.push("", "## Rules", "");
      for (const rule of team.rules) {
        const title = sanitizeMarkerContent(rule.title || rule.id);
        const body = typeof rule.body === "string" ? sanitizeMarkerContent(rule.body) : "";
        sections.push(`### ${title}`, "", body);
      }
    }

    if (team.skills && team.skills.length > 0) {
      sections.push("", "## Skills", "");
      for (const skill of team.skills) {
        const title = skill.title || skill.id;
        const desc = skill.description || "";
        const body = skill.body ? (typeof skill.body === "string" ? skill.body : "") : "";
        sections.push(`### ${title}`, "", ...(desc ? [desc, ""] : []), ...(body ? [body] : []));
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
  installHooks(_relay: string, _token: string): void {}
  watchPaths(): string[] { return []; }
  writeFile(_key: string, _content: string): void {}
  readFile(_key: string): string | null { return null; }
  uninstall(): string[] {
    const filePath = this.geminiMdPath();
    if (!fs.existsSync(filePath)) return [];
    const content = fs.readFileSync(filePath, "utf-8");
    const marker = "<!-- teambridge -->";
    const markerEnd = "<!-- /teambridge -->";
    const regex = new RegExp(
      `\\n?${marker.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}[\\s\\S]*?${markerEnd.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}\\n?`,
    );
    const cleaned = content.replace(regex, "\n");
    if (cleaned !== content) {
      fs.writeFileSync(filePath, cleaned.trimEnd() + "\n");
      return ["Removed TeamBridge section from GEMINI.md"];
    }
    return [];
  }
}
