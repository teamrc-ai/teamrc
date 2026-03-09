// ---------------------------------------------------------------------------
// Template catalog — loads agents, skills, and teams from YAML files
// ---------------------------------------------------------------------------

import * as fs from "node:fs";
import * as path from "node:path";
import { fileURLToPath } from "node:url";
import YAML from "yaml";
import type { Skill, TeamDefinition, TeamMember } from "./adapters/base.js";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const TEMPLATES_DIR = path.resolve(__dirname, "../../templates");

// ---------------------------------------------------------------------------
// Catalog file types
// ---------------------------------------------------------------------------

interface CatalogAgent {
  name: string;
  role: string;
  category: string;
  soul: string;
}

interface CatalogSkill {
  id: string;
  title: string;
  category: string;
  description?: string;
  alwaysApply?: boolean;
  globs?: string[];
  userInvocable?: boolean;
  body: string;
}

interface CatalogTeam {
  label: string;
  description: string;
  defaultPlatforms: string[];
  name: string;
  agents: string[];
  skills: string[];
  agentSkills?: Record<string, string[]>;
}

// ---------------------------------------------------------------------------
// Public types
// ---------------------------------------------------------------------------

export interface AgentCategory {
  id: string;
  label: string;
  agents: string[];
}

export interface SkillCategory {
  id: string;
  label: string;
  skills: string[];
}

export interface TeamTemplate {
  id: string;
  label: string;
  description: string;
  defaultPlatforms: string[];
  teamName: string;
  members: TeamMember[];
  skills: Skill[];
}

// ---------------------------------------------------------------------------
// Loaders
// ---------------------------------------------------------------------------

function readYaml<T>(filePath: string): T {
  return YAML.parse(fs.readFileSync(filePath, "utf-8")) as T;
}

const SAFE_NAME_RE = /^[a-zA-Z0-9][a-zA-Z0-9_-]*$/;

export function loadAgent(name: string): CatalogAgent {
  if (!SAFE_NAME_RE.test(name)) throw new Error(`Invalid agent name in template: ${JSON.stringify(name)}`);
  return readYaml<CatalogAgent>(path.join(TEMPLATES_DIR, "agents", `${name}.yaml`));
}

export function loadSkill(id: string): CatalogSkill {
  if (!SAFE_NAME_RE.test(id)) throw new Error(`Invalid skill ID in template: ${JSON.stringify(id)}`);
  return readYaml<CatalogSkill>(path.join(TEMPLATES_DIR, "skills", `${id}.yaml`));
}

function loadTeamRaw(id: string): CatalogTeam {
  return readYaml<CatalogTeam>(path.join(TEMPLATES_DIR, "teams", `${id}.yaml`));
}

// ---------------------------------------------------------------------------
// Directory scanning helpers
// ---------------------------------------------------------------------------

function scanYamlDir(dir: string): string[] {
  if (!fs.existsSync(dir)) return [];
  return fs
    .readdirSync(dir)
    .filter((f) => f.endsWith(".yaml") && f !== "_index.yaml")
    .map((f) => f.replace(/\.yaml$/, ""));
}

function tryReadIndex<T>(dir: string): T | null {
  const indexPath = path.join(dir, "_index.yaml");
  if (!fs.existsSync(indexPath)) return null;
  return readYaml<T>(indexPath);
}

// ---------------------------------------------------------------------------
// Index readers (auto-discover files, use _index.yaml for ordering/labels)
// ---------------------------------------------------------------------------

export function listTeams(): string[] {
  const dir = path.join(TEMPLATES_DIR, "teams");
  const index = tryReadIndex<{ order: string[] }>(dir);
  const onDisk = scanYamlDir(dir);
  if (!index) return onDisk;

  // Start with index order, append any new files not in the index
  const ordered = index.order.filter((id) => onDisk.includes(id));
  for (const id of onDisk) {
    if (!ordered.includes(id)) ordered.push(id);
  }
  return ordered;
}

export function listAgentCategories(): AgentCategory[] {
  const dir = path.join(TEMPLATES_DIR, "agents");
  const index = tryReadIndex<{ categories: AgentCategory[] }>(dir);
  const onDisk = scanYamlDir(dir);

  // Track which agents are already categorized
  const categorized = new Set<string>();
  const categories: AgentCategory[] = [];

  if (index) {
    for (const cat of index.categories) {
      // Only include agents that exist on disk
      const agents = cat.agents.filter((a) => onDisk.includes(a));
      agents.forEach((a) => categorized.add(a));
      categories.push({ ...cat, agents });
    }
  }

  // Auto-discover agents not in the index, group by their file's category field
  const uncategorized: Record<string, string[]> = {};
  for (const name of onDisk) {
    if (categorized.has(name)) continue;
    try {
      const agent = loadAgent(name);
      const cat = agent.category || "uncategorized";
      if (!uncategorized[cat]) uncategorized[cat] = [];
      uncategorized[cat].push(name);
    } catch {
      // Skip files that can't be parsed
    }
  }

  // Merge discovered agents into existing categories or create new ones
  for (const [catId, agents] of Object.entries(uncategorized)) {
    const existing = categories.find((c) => c.id === catId);
    if (existing) {
      existing.agents.push(...agents);
    } else {
      categories.push({ id: catId, label: catId, agents });
    }
  }

  return categories;
}

export function listSkillCategories(): SkillCategory[] {
  const dir = path.join(TEMPLATES_DIR, "skills");
  const index = tryReadIndex<{ categories: SkillCategory[] }>(dir);
  const onDisk = scanYamlDir(dir);

  const categorized = new Set<string>();
  const categories: SkillCategory[] = [];

  if (index) {
    for (const cat of index.categories) {
      const skills = cat.skills.filter((s) => onDisk.includes(s));
      skills.forEach((s) => categorized.add(s));
      categories.push({ ...cat, skills });
    }
  }

  // Auto-discover skills not in the index
  const uncategorized: Record<string, string[]> = {};
  for (const id of onDisk) {
    if (categorized.has(id)) continue;
    try {
      const skill = loadSkill(id);
      const cat = skill.category || "uncategorized";
      if (!uncategorized[cat]) uncategorized[cat] = [];
      uncategorized[cat].push(id);
    } catch {
      // Skip files that can't be parsed
    }
  }

  for (const [catId, skills] of Object.entries(uncategorized)) {
    const existing = categories.find((c) => c.id === catId);
    if (existing) {
      existing.skills.push(...skills);
    } else {
      categories.push({ id: catId, label: catId, skills });
    }
  }

  return categories;
}

// ---------------------------------------------------------------------------
// Resolution
// ---------------------------------------------------------------------------

/** Resolve a team template into a fully self-contained TeamTemplate */
export function resolveTeam(teamId: string): TeamTemplate {
  const team = loadTeamRaw(teamId);

  const members: TeamMember[] = team.agents.map((agentName) => {
    const agent = loadAgent(agentName);
    const agentSkillIds = team.agentSkills?.[agentName];
    return {
      name: agent.name,
      role: agent.role,
      soul: agent.soul,
      ...(agentSkillIds && agentSkillIds.length > 0 ? { skills: agentSkillIds } : {}),
    };
  });

  const skills: Skill[] = team.skills.map((skillId) => {
    const skill = loadSkill(skillId);
    return {
      id: skill.id,
      title: skill.title,
      ...(skill.description ? { description: skill.description } : {}),
      ...(skill.alwaysApply !== undefined ? { alwaysApply: skill.alwaysApply } : {}),
      ...(skill.globs ? { globs: skill.globs } : {}),
      ...(skill.userInvocable !== undefined ? { userInvocable: skill.userInvocable } : {}),
      body: skill.body,
    };
  });

  return {
    id: teamId,
    label: team.label,
    description: team.description,
    defaultPlatforms: team.defaultPlatforms,
    teamName: team.name,
    members,
    skills,
  };
}

/** Convert a resolved TeamTemplate into a TeamDefinition (for writing to .teamrc.yaml) */
export function templateToTeamDefinition(template: TeamTemplate, teamName: string): TeamDefinition {
  return {
    name: teamName,
    members: template.members.map((m) => ({
      name: m.name,
      role: m.role,
      soul: m.soul,
      ...(m.skills && m.skills.length > 0 ? { skills: m.skills } : {}),
    })),
    skills: template.skills.length > 0 ? template.skills : undefined,
  };
}
