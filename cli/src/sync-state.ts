import * as fs from "node:fs";
import * as path from "node:path";
import { randomBytes } from "node:crypto";
import YAML from "yaml";

export interface SyncState {
  syncHash?: string;
  syncHashMembers?: string;
  syncHashSkills?: string;
  syncHashKnowledge?: string;
  lastPollAt?: string; // ISO timestamp
}

const STATE_DIR = ".teamrc";
const STATE_FILE = "state.json";

function getStatePath(projectDir?: string): string {
  const base = projectDir ?? process.cwd();
  return path.join(base, STATE_DIR, STATE_FILE);
}

function getStateDir(projectDir?: string): string {
  const base = projectDir ?? process.cwd();
  return path.join(base, STATE_DIR);
}

export function readSyncState(projectDir?: string): SyncState {
  const statePath = getStatePath(projectDir);
  if (!fs.existsSync(statePath)) {
    return {};
  }
  try {
    const raw = fs.readFileSync(statePath, "utf-8");
    const parsed = JSON.parse(raw);
    if (!parsed || typeof parsed !== "object") return {};
    return {
      ...(parsed.syncHash ? { syncHash: String(parsed.syncHash) } : {}),
      ...(parsed.syncHashMembers ? { syncHashMembers: String(parsed.syncHashMembers) } : {}),
      ...(parsed.syncHashSkills ? { syncHashSkills: String(parsed.syncHashSkills) } : {}),
      ...(parsed.syncHashKnowledge ? { syncHashKnowledge: String(parsed.syncHashKnowledge) } : {}),
      ...(parsed.lastPollAt ? { lastPollAt: String(parsed.lastPollAt) } : {}),
    };
  } catch {
    return {};
  }
}

export function writeSyncState(state: SyncState, projectDir?: string): void {
  const dir = getStateDir(projectDir);
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true, mode: 0o700 });
  }
  const statePath = getStatePath(projectDir);
  const tmpPath = `${statePath}.${randomBytes(4).toString("hex")}.tmp`;
  fs.writeFileSync(tmpPath, JSON.stringify(state, null, 2), { mode: 0o600 });
  fs.renameSync(tmpPath, statePath);
}

/**
 * Migrate legacy syncHash fields from a team YAML object into state.json.
 * Returns true if migration occurred (caller should rewrite the YAML without hash fields).
 */
export function migrateLegacySyncHashes(
  yamlData: { syncHash?: string; syncHashMembers?: string; syncHashSkills?: string; syncHashKnowledge?: string },
  projectDir?: string,
): boolean {
  if (!yamlData.syncHash && !yamlData.syncHashMembers && !yamlData.syncHashSkills && !yamlData.syncHashKnowledge) {
    return false;
  }

  const existing = readSyncState(projectDir);
  // Only migrate if state.json doesn't already have hashes
  if (existing.syncHash) return false;

  writeSyncState({
    ...existing,
    ...(yamlData.syncHash ? { syncHash: yamlData.syncHash } : {}),
    ...(yamlData.syncHashMembers ? { syncHashMembers: yamlData.syncHashMembers } : {}),
    ...(yamlData.syncHashSkills ? { syncHashSkills: yamlData.syncHashSkills } : {}),
    ...(yamlData.syncHashKnowledge ? { syncHashKnowledge: yamlData.syncHashKnowledge } : {}),
  }, projectDir);

  return true;
}

/**
 * Check a YAML file for legacy syncHash fields and migrate them to state.json.
 * If migration occurs, rewrites the YAML file without the hash fields.
 */
export function migrateLegacyYamlHashes(yamlPath: string, projectDir?: string): void {
  if (!fs.existsSync(yamlPath)) return;

  // Check if state.json already exists  --  if so, no migration needed
  const existing = readSyncState(projectDir);
  if (existing.syncHash) return;

  try {
    const content = fs.readFileSync(yamlPath, "utf-8");
    const data = YAML.parse(content);
    if (!data || typeof data !== "object") return;

    const legacyFields: Record<string, string> = {};
    if (data.syncHash) legacyFields.syncHash = String(data.syncHash);
    if (data.syncHashMembers) legacyFields.syncHashMembers = String(data.syncHashMembers);
    if (data.syncHashSkills) legacyFields.syncHashSkills = String(data.syncHashSkills);
    if (data.syncHashKnowledge) legacyFields.syncHashKnowledge = String(data.syncHashKnowledge);

    if (Object.keys(legacyFields).length === 0) return;

    // Migrate to state.json
    const migrated = migrateLegacySyncHashes(legacyFields, projectDir);
    if (!migrated) return;

    // Rewrite YAML without hash fields
    delete data.syncHash;
    delete data.syncHashMembers;
    delete data.syncHashSkills;
    delete data.syncHashKnowledge;

    const newYaml = YAML.stringify(data);
    const tmpPath = `${yamlPath}.${randomBytes(4).toString("hex")}.tmp`;
    fs.writeFileSync(tmpPath, newYaml);
    fs.renameSync(tmpPath, yamlPath);
  } catch {
    // Migration is best-effort  --  don't break the workflow
  }
}
