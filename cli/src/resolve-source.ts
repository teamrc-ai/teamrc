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

export function resolveBody(
  body: string | { source: string } | undefined,
  basePath: string,
): string {
  if (body === undefined) return "";
  if (typeof body === "string") return body;
  if (body.source) {
    const resolved = path.resolve(basePath, body.source);
    if (fs.existsSync(resolved)) {
      return fs.readFileSync(resolved, "utf-8");
    }
    return "";
  }
  return "";
}
