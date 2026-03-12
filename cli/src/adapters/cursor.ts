import * as fs from "node:fs";
import * as path from "node:path";
import {
  sanitizeMarkerContent,
  type PlatformAdapter,
  type TeamDefinition,
  type Rule,
} from "./base.js";

export class CursorAdapter implements PlatformAdapter {
  private cursorDir(): string {
    return path.join(process.cwd(), ".cursor");
  }

  private rulesDir(): string {
    return path.join(this.cursorDir(), "rules");
  }

  private listTbRules(): string[] {
    const dir = this.rulesDir();
    if (!fs.existsSync(dir)) return [];
    return fs.readdirSync(dir).filter((f) => f.startsWith("tb-") && f.endsWith(".mdc"));
  }

  readTeam(): TeamDefinition | null {
    return null;
  }

  writeTeam(team: TeamDefinition): void {
    if (team.rules) {
      for (const rule of team.rules) {
        this.writeRuleMdc(rule);
      }
    }
    this.writeAgentsMd(team);
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

    const memberLines = team.members
      .map((m) => `- **${sanitizeMarkerContent(m.name)}** — ${sanitizeMarkerContent(m.role)}`)
      .join("\n");

    const block = [marker, `# Team: ${sanitizeMarkerContent(team.name)}`, "", memberLines, markerEnd].join("\n");

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
  installHooks(_relay: string, _token: string): void {}
  watchPaths(): string[] { return []; }
  writeFile(_key: string, _content: string): void {}
  readFile(_key: string): string | null { return null; }
  uninstall(): string[] {
    const actions: string[] = [];
    const tbRules = this.listTbRules();
    for (const f of tbRules) {
      fs.unlinkSync(path.join(this.rulesDir(), f));
    }
    if (tbRules.length > 0) {
      actions.push(`Deleted ${tbRules.length} TeamBridge cursor rule(s)`);
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
