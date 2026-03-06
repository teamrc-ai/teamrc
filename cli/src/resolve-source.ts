import { readTeamYaml } from "./team-yaml.js";
import type { TeamDefinition } from "./adapters/base.js";
import * as fs from "node:fs";
import * as path from "node:path";

export type SourceType = "yaml" | "platform" | "none";

export interface ResolvedTeam {
  source: SourceType;
  team: TeamDefinition | null;
}

export function resolveTeamSource(
  yamlPath: string,
  adapterTeam: TeamDefinition | null,
): ResolvedTeam {
  const yamlTeam = readTeamYaml(yamlPath);
  if (yamlTeam) {
    return { source: "yaml", team: yamlTeam };
  }

  if (adapterTeam) {
    return { source: "platform", team: adapterTeam };
  }

  return { source: "none", team: null };
}

const MAX_SOURCE_SIZE = 1024 * 1024; // 1 MB

export function resolveBody(
  body: string | { source: string } | undefined,
  basePath: string,
): string {
  if (body === undefined) return "";
  if (typeof body === "string") return body;
  if (body.source) {
    if (typeof body.source !== "string") return "";
    const resolved = path.resolve(basePath, body.source);
    // Prevent path traversal: resolved path must stay within basePath
    const realBase = path.resolve(basePath);
    if (!resolved.startsWith(realBase + path.sep) && resolved !== realBase) {
      throw new Error(`Path traversal blocked: source "${body.source}" resolves outside project directory`);
    }
    if (!fs.existsSync(resolved)) return "";
    // Re-check after resolving symlinks to prevent symlink-based traversal
    const realResolved = fs.realpathSync(resolved);
    const realBaseResolved = fs.realpathSync(realBase);
    if (!realResolved.startsWith(realBaseResolved + path.sep) && realResolved !== realBaseResolved) {
      throw new Error(`Path traversal blocked: source "${body.source}" resolves outside project directory via symlink`);
    }
    const stat = fs.statSync(resolved);
    if (stat.size > MAX_SOURCE_SIZE) {
      throw new Error(`Source file "${body.source}" exceeds maximum size of ${MAX_SOURCE_SIZE} bytes`);
    }
    return fs.readFileSync(resolved, "utf-8");
  }
  return "";
}
