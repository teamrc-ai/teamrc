import { signMessage } from "./auth.js";
import type { Skill, TeamDefinition } from "./adapters/base.js";

import { validateSkillId, resolveBody } from "./team-yaml.js";
import { cliCmd } from "./utils.js";
import { createRequire } from "node:module";

const require = createRequire(import.meta.url);
const { version: CLI_VERSION } = require("../package.json") as { version: string };

export interface TeamrcTeam {
  id: string;
  name: string;
  members: Array<{ name: string; role: string; platform?: string; skills?: string[]; soul?: string }>;
  skills?: Skill[];
  knowledge?: string;
  owner_claim_secret?: string;
  hash?: string;
  members_hash?: string;
  skills_hash?: string;
  knowledge_hash?: string;
}

export interface TeamHeadResponse {
  hash: string;
  members_hash: string;
  skills_hash: string;
  knowledge_hash: string;
}

export interface TaskItem {
  number: number;
  description: string;
  assignee: string;
  status: string;
  created_by?: string;
  claimed_by?: string;
  claimed_at?: string;
  completed_at?: string;
  inserted_at?: string;
  updated_at?: string;
}

export class SyncConflictError extends Error {
  serverHash: string;
  constructor(message: string, serverHash: string) {
    super(message);
    this.name = "SyncConflictError";
    this.serverHash = serverHash;
  }
}

export class UpgradeRequiredError extends Error {
  constructor() {
    super("Your teamrc CLI is outdated. Please update: npm install -g teamrc");
    this.name = "UpgradeRequiredError";
  }
}

export class TeamNotFoundError extends Error {
  constructor() {
    super("This team no longer exists on the relay.");
    this.name = "TeamNotFoundError";
  }
}

/** API version sent with every request. Uses major version from package.json. */
const API_VERSION = String(parseInt(CLI_VERSION, 10) || 1);

// Size caps for relay-sourced content to prevent resource exhaustion
const MAX_NAME_LEN = 64;
const MAX_ROLE_LEN = 500;
const MAX_SOUL_LEN = 4096;
const MAX_BODY_LEN = 65536;

function capString(s: string | undefined, max: number): string | undefined {
  if (!s) return s;
  return s.length > max ? s.slice(0, max) : s;
}

/** Strip YAML frontmatter delimiters from body/soul content to prevent injection */
function sanitizeFrontmatter(s: string): string {
  return s.replace(/^---\s*$/gm, "- - -");
}

export function remoteTeamToDefinition(team: TeamrcTeam): TeamDefinition {
  // Validate skill IDs from the relay to prevent path traversal
  const skills = team.skills?.filter((s) => {
    try { validateSkillId(s.id); return true; } catch { return false; }
  }).map((s) => ({
    ...s,
    body: typeof s.body === "string" ? sanitizeFrontmatter(capString(s.body, MAX_BODY_LEN)!) : s.body,
    globs: s.globs?.map((g) => g.replace(/[\n\r]/g, "")) ?? [],
    ...(s.title ? { title: capString(s.title, MAX_NAME_LEN) } : {}),
    ...(s.description ? { description: capString(s.description, MAX_ROLE_LEN) } : {}),
  }));

  return {
    name: capString(team.name, MAX_NAME_LEN) ?? "",
    members: team.members.map((m) => ({
      name: capString(m.name, MAX_NAME_LEN) ?? "",
      role: capString(m.role, MAX_ROLE_LEN) ?? "",
      ...(m.soul ? { soul: sanitizeFrontmatter(capString(m.soul, MAX_SOUL_LEN)!) } : {}),
      ...(m.skills?.length ? { skills: m.skills.filter((id) => {
        try { validateSkillId(id); return true; } catch { return false; }
      }) } : {}),
    })),
    ...(skills?.length ? { skills } : {}),
  };
}

/** Sanitize a locally-sourced TeamDefinition (e.g. from readTeamYaml) before sending to relay.
 *  Applies the same caps, frontmatter stripping, and skill ID validation as remoteTeamToDefinition.
 *  Strips source-body skills since they should not be sent unresolved to the relay. */
export function sanitizeTeamDefinition(team: TeamDefinition): TeamDefinition {
  const skills = team.skills?.filter((s) => {
    // Drop source-body skills  --  they reference local files and must not be sent to relay unresolved
    if (typeof s.body === "object" && s.body?.source) return false;
    try { validateSkillId(s.id); return true; } catch { return false; }
  }).map((s) => ({
    ...s,
    body: typeof s.body === "string" ? sanitizeFrontmatter(capString(s.body, MAX_BODY_LEN)!) : s.body,
    globs: s.globs?.map((g) => g.replace(/[\n\r]/g, "")) ?? [],
    ...(s.title ? { title: capString(s.title, MAX_NAME_LEN) } : {}),
    ...(s.description ? { description: capString(s.description, MAX_ROLE_LEN) } : {}),
  }));

  return {
    ...team,
    name: capString(team.name, MAX_NAME_LEN) ?? "",
    members: team.members.map((m) => ({
      ...m,
      name: capString(m.name, MAX_NAME_LEN) ?? "",
      role: capString(m.role, MAX_ROLE_LEN) ?? "",
      ...(m.soul ? { soul: sanitizeFrontmatter(capString(m.soul, MAX_SOUL_LEN)!) } : {}),
      ...(m.skills?.length ? { skills: m.skills.filter((id) => {
        try { validateSkillId(id); return true; } catch { return false; }
      }) } : {}),
    })),
    ...(skills?.length ? { skills } : { skills: undefined }),
  };
}

export class TeamrcClient {
  private baseUrl: string;
  private privateKey: Uint8Array;
  private token: string;
  private teamId?: string;

  /** Default timeout for all fetch requests (30 seconds) */
  static readonly FETCH_TIMEOUT_MS = 30_000;

  constructor(baseUrl: string, privateKey: Uint8Array, token: string, teamId?: string) {
    this.baseUrl = baseUrl.replace(/\/$/, "");
    this.privateKey = privateKey;
    this.token = token;
    this.teamId = teamId;
  }

  /** Update the team ID (e.g. after createTeam returns a new ID) */
  setTeamId(teamId: string): void {
    this.teamId = teamId;
  }

  /** Extract a short, safe error message from a response */
  private async errorMessage(res: Response, context: string): Promise<string> {
    try {
      const body = await res.json() as { error?: string };
      if (body.error) return `${context}: ${res.status} ${body.error}`;
    } catch { /* not JSON */ }
    return `${context}: ${res.status}`;
  }

  /** Check for 426 Upgrade Required and throw a user-facing error */
  private checkUpgradeRequired(res: Response): void {
    if (res.status === 426) {
      throw new UpgradeRequiredError();
    }
  }

  private async signedHeaders(
    body: string,
  ): Promise<Record<string, string>> {
    const timestamp = Math.floor(Date.now() / 1000).toString();
    const message = `${timestamp}.${body}`;
    const signature = await signMessage(this.privateKey, message);
    return {
      "Content-Type": "application/json",
      "X-Teamrc-Version": API_VERSION,
      "x-trc-signature": signature,
      "x-trc-timestamp": timestamp,
    };
  }

  private async signedGet<T>(path: string): Promise<T> {
    const timestamp = Math.floor(Date.now() / 1000).toString();
    const message = `${timestamp}.GET ${path}`;
    const signature = await signMessage(this.privateKey, message);
    const res = await fetch(`${this.baseUrl}${path}`, {
      method: "GET",
      headers: {
        "X-Teamrc-Version": API_VERSION,
        "x-trc-signature": signature,
        "x-trc-timestamp": timestamp,
        "x-trc-token": this.token,
      },
      signal: AbortSignal.timeout(TeamrcClient.FETCH_TIMEOUT_MS),
    });
    this.checkUpgradeRequired(res);
    if (!res.ok) {
      throw new Error(await this.errorMessage(res, `GET ${path} failed`));
    }
    return (await res.json()) as T;
  }

  async createTeam(
    name: string,
    members: Array<{ name: string; role: string; platform?: string; skills?: string[] }>,
    skills?: Skill[],
    knowledge?: string,
  ): Promise<TeamrcTeam> {
    const body = JSON.stringify({
      token: this.token,
      team: {
        name,
        members,
        ...(skills?.length ? { skills } : {}),
        ...(knowledge ? { knowledge } : {}),
      },
    });
    const headers = await this.signedHeaders(body);
    const res = await fetch(`${this.baseUrl}/api/teams`, {
      method: "POST",
      headers,
      body,
      signal: AbortSignal.timeout(TeamrcClient.FETCH_TIMEOUT_MS),
    });
    this.checkUpgradeRequired(res);
    if (!res.ok) {
      throw new Error(await this.errorMessage(res, "createTeam failed"));
    }
    const data = (await res.json()) as { team: TeamrcTeam };
    return data.team;
  }

  async getTeam(): Promise<TeamrcTeam> {
    const url = this.teamId
      ? `/api/teams/${this.token}?team_id=${encodeURIComponent(this.teamId)}`
      : `/api/teams/${this.token}`;
    try {
      const data = await this.signedGet<{ team: TeamrcTeam }>(url);
      return data.team;
    } catch (err) {
      if (err instanceof Error && err.message.includes(": 404")) throw new TeamNotFoundError();
      throw err;
    }
  }

  async joinByInvite(inviteCode: string): Promise<TeamrcTeam> {
    const body = JSON.stringify({ invite_code: inviteCode, token: this.token });
    const headers = await this.signedHeaders(body);
    const res = await fetch(`${this.baseUrl}/api/join`, {
      method: "POST",
      headers,
      body,
      signal: AbortSignal.timeout(TeamrcClient.FETCH_TIMEOUT_MS),
    });
    this.checkUpgradeRequired(res);
    if (!res.ok) {
      throw new Error(await this.errorMessage(res, "join failed"));
    }
    const data = (await res.json()) as { team: TeamrcTeam };
    return data.team;
  }

  async pushTeam(team: TeamDefinition, knowledge?: string, basePath?: string, baseHash?: string): Promise<TeamrcTeam> {
    // Resolve source-body skills to their actual content before sending
    const resolvedSkills = team.skills?.map((s) => {
      if (typeof s.body === "object" && s.body.source) {
        const resolved = resolveBody(s.body, basePath ?? process.cwd());
        if (!resolved) {
          throw new Error(`Skill "${s.id}" references source "${s.body.source}" which could not be read`);
        }
        return { ...s, body: resolved };
      }
      return s;
    });
    const body = JSON.stringify({
      token: this.token,
      ...(this.teamId ? { team_id: this.teamId } : {}),
      ...(baseHash ? { base_hash: baseHash } : {}),
      team: {
        name: team.name,
        members: team.members.map((m) => ({
          name: m.name,
          role: m.role,
          ...(m.soul ? { soul: m.soul } : {}),
          ...(m.skills?.length ? { skills: m.skills } : {}),
        })),
        ...(resolvedSkills?.length ? { skills: resolvedSkills } : {}),
        ...(knowledge ? { knowledge } : {}),
      },
    });
    const headers = await this.signedHeaders(body);
    const res = await fetch(`${this.baseUrl}/api/teams`, {
      method: "POST",
      headers,
      body,
      signal: AbortSignal.timeout(TeamrcClient.FETCH_TIMEOUT_MS),
    });
    this.checkUpgradeRequired(res);
    if (res.status === 409) {
      let serverHash = "";
      try {
        const conflict = (await res.json()) as { server_hash?: string; error?: string };
        serverHash = conflict.server_hash ?? "";
      } catch { /* not JSON */ }
      throw new SyncConflictError(
        `Remote has changes. Run \`${cliCmd("pull")}\` first.`,
        serverHash,
      );
    }
    if (!res.ok) {
      throw new Error(await this.errorMessage(res, "pushTeam failed"));
    }
    const data = (await res.json()) as { team: TeamrcTeam };
    return data.team;
  }

  async pushKnowledge(content: string): Promise<{ knowledge_hash: string; knowledge_size: number }> {
    const body = JSON.stringify({
      token: this.token,
      ...(this.teamId ? { team_id: this.teamId } : {}),
      content,
    });
    const headers = await this.signedHeaders(body);
    const res = await fetch(`${this.baseUrl}/api/teams/knowledge`, {
      method: "POST",
      headers,
      body,
      signal: AbortSignal.timeout(TeamrcClient.FETCH_TIMEOUT_MS),
    });
    this.checkUpgradeRequired(res);
    if (res.status === 404) throw new TeamNotFoundError();
    if (!res.ok) {
      throw new Error(await this.errorMessage(res, "pushKnowledge failed"));
    }
    return (await res.json()) as { knowledge_hash: string; knowledge_size: number };
  }

  async getTeamHead(): Promise<TeamHeadResponse> {
    const url = this.teamId
      ? `/api/teams/${this.token}/head?team_id=${encodeURIComponent(this.teamId)}`
      : `/api/teams/${this.token}/head`;
    try {
      return await this.signedGet<TeamHeadResponse>(url);
    } catch (err) {
      if (err instanceof Error && err.message.includes(": 404")) throw new TeamNotFoundError();
      throw err;
    }
  }

  async createDeviceAuth(): Promise<{
    device_code: string;
    user_code: string;
    verification_url: string;
    expires_in: number;
    interval: number;
  }> {
    const body = JSON.stringify({ token: this.token });
    const headers = await this.signedHeaders(body);
    const res = await fetch(`${this.baseUrl}/api/auth/device`, {
      method: "POST",
      headers,
      body,
      signal: AbortSignal.timeout(TeamrcClient.FETCH_TIMEOUT_MS),
    });
    this.checkUpgradeRequired(res);
    if (!res.ok) {
      throw new Error(await this.errorMessage(res, "createDeviceAuth failed"));
    }
    return (await res.json()) as {
      device_code: string;
      user_code: string;
      verification_url: string;
      expires_in: number;
      interval: number;
    };
  }

  async pollDeviceAuth(deviceCode: string): Promise<{
    status: "pending" | "confirmed";
    email?: string;
    machine_count?: number;
    team_count?: number;
  }> {
    return this.signedGet<{
      status: "pending" | "confirmed";
      email?: string;
      machine_count?: number;
      team_count?: number;
    }>(`/api/auth/device/${encodeURIComponent(deviceCode)}`);
  }

  async previewByInvite(inviteCode: string): Promise<TeamrcTeam> {
    const body = JSON.stringify({ invite_code: inviteCode, token: this.token });
    const headers = await this.signedHeaders(body);
    const res = await fetch(`${this.baseUrl}/api/teams/preview`, {
      method: "POST",
      headers,
      body,
      signal: AbortSignal.timeout(TeamrcClient.FETCH_TIMEOUT_MS),
    });
    this.checkUpgradeRequired(res);
    if (!res.ok) throw new Error(await this.errorMessage(res, "preview failed"));
    const data = (await res.json()) as { team: TeamrcTeam };
    return data.team;
  }

  async cloneByToken(cloneToken: string): Promise<TeamrcTeam> {
    const res = await fetch(`${this.baseUrl}/api/teams/clone/${encodeURIComponent(cloneToken)}`, {
      headers: { "X-Teamrc-Version": API_VERSION },
      signal: AbortSignal.timeout(TeamrcClient.FETCH_TIMEOUT_MS),
    });
    this.checkUpgradeRequired(res);
    if (!res.ok) {
      throw new Error(await this.errorMessage(res, "clone failed"));
    }
    const data = (await res.json()) as { team: TeamrcTeam };
    return data.team;
  }

  private async signedDelete<T>(path: string): Promise<T> {
    const timestamp = Math.floor(Date.now() / 1000).toString();
    const message = `${timestamp}.DELETE ${path}`;
    const signature = await signMessage(this.privateKey, message);
    const res = await fetch(`${this.baseUrl}${path}`, {
      method: "DELETE",
      headers: {
        "X-Teamrc-Version": API_VERSION,
        "x-trc-signature": signature,
        "x-trc-timestamp": timestamp,
        "x-trc-token": this.token,
      },
      signal: AbortSignal.timeout(TeamrcClient.FETCH_TIMEOUT_MS),
    });
    this.checkUpgradeRequired(res);
    if (!res.ok) {
      throw new Error(await this.errorMessage(res, `DELETE ${path} failed`));
    }
    return (await res.json()) as T;
  }

  async disconnect(teamId?: string): Promise<{ status: string; teams_removed: number }> {
    const base = `/api/token/${encodeURIComponent(this.token)}/erase`;
    const path = teamId ? `${base}?team_id=${encodeURIComponent(teamId)}` : base;
    return this.signedDelete<{ status: string; teams_removed: number }>(path);
  }

  async claimOwnership(claimSecret: string): Promise<{ status: string }> {
    const body = JSON.stringify({
      token: this.token,
      claim_secret: claimSecret,
      ...(this.teamId ? { team_id: this.teamId } : {}),
    });
    const headers = await this.signedHeaders(body);
    const res = await fetch(`${this.baseUrl}/api/teams/claim`, {
      method: "POST",
      headers,
      body,
      signal: AbortSignal.timeout(TeamrcClient.FETCH_TIMEOUT_MS),
    });
    this.checkUpgradeRequired(res);
    if (!res.ok) throw new Error(await this.errorMessage(res, "claimOwnership failed"));
    return (await res.json()) as { status: string };
  }

  async setVisibility(visibility: "public" | "private"): Promise<{ visibility: string; clone_token: string | null }> {
    const body = JSON.stringify({
      token: this.token,
      visibility,
      ...(this.teamId ? { team_id: this.teamId } : {}),
    });
    const headers = await this.signedHeaders(body);
    const res = await fetch(`${this.baseUrl}/api/teams/visibility`, {
      method: "POST",
      headers,
      body,
      signal: AbortSignal.timeout(TeamrcClient.FETCH_TIMEOUT_MS),
    });
    this.checkUpgradeRequired(res);
    if (!res.ok) throw new Error(await this.errorMessage(res, "setVisibility failed"));
    return (await res.json()) as { visibility: string; clone_token: string | null };
  }

  async createInvite(ttlHours: number = 24): Promise<{ invite_code: string; expires_at: string }> {
    const body = JSON.stringify({
      token: this.token,
      ttl_hours: ttlHours,
      ...(this.teamId ? { team_id: this.teamId } : {}),
    });
    const headers = await this.signedHeaders(body);
    const res = await fetch(`${this.baseUrl}/api/teams/invite`, {
      method: "POST",
      headers,
      body,
      signal: AbortSignal.timeout(TeamrcClient.FETCH_TIMEOUT_MS),
    });
    this.checkUpgradeRequired(res);
    if (!res.ok) throw new Error(await this.errorMessage(res, "createInvite failed"));
    return (await res.json()) as { invite_code: string; expires_at: string };
  }

  async createViewToken(ttlHours: number = 24): Promise<{ view_token: string; team_id: string; expires_at: string }> {
    const body = JSON.stringify({
      token: this.token,
      ttl_hours: ttlHours,
      ...(this.teamId ? { team_id: this.teamId } : {}),
    });
    const headers = await this.signedHeaders(body);
    const res = await fetch(`${this.baseUrl}/api/teams/view-token`, {
      method: "POST",
      headers,
      body,
      signal: AbortSignal.timeout(TeamrcClient.FETCH_TIMEOUT_MS),
    });
    this.checkUpgradeRequired(res);
    if (!res.ok) throw new Error(await this.errorMessage(res, "createViewToken failed"));
    return (await res.json()) as { view_token: string; team_id: string; expires_at: string };
  }

  async createTask(description: string, assignee: string): Promise<TaskItem> {
    const body = JSON.stringify({
      token: this.token,
      ...(this.teamId ? { team_id: this.teamId } : {}),
      description,
      assignee,
    });
    const headers = await this.signedHeaders(body);
    const res = await fetch(`${this.baseUrl}/api/teams/tasks`, {
      method: "POST",
      headers,
      body,
      signal: AbortSignal.timeout(TeamrcClient.FETCH_TIMEOUT_MS),
    });
    this.checkUpgradeRequired(res);
    if (!res.ok) throw new Error(await this.errorMessage(res, "createTask failed"));
    const data = (await res.json()) as { task: TaskItem };
    return data.task;
  }

  async listTasks(opts?: { status?: string; assignee?: string }): Promise<TaskItem[]> {
    const params = new URLSearchParams();
    if (this.teamId) params.set("team_id", this.teamId);
    if (opts?.status) params.set("status", opts.status);
    if (opts?.assignee) params.set("assignee", opts.assignee);
    const qs = params.toString();
    const path = `/api/teams/tasks/${this.token}${qs ? `?${qs}` : ""}`;
    const data = await this.signedGet<{ tasks: TaskItem[] }>(path);
    return data.tasks;
  }

  async updateTask(number: number, status: string): Promise<TaskItem> {
    const body = JSON.stringify({
      token: this.token,
      ...(this.teamId ? { team_id: this.teamId } : {}),
      status,
    });
    const headers = await this.signedHeaders(body);
    const res = await fetch(`${this.baseUrl}/api/teams/tasks/${number}`, {
      method: "PATCH",
      headers,
      body,
      signal: AbortSignal.timeout(TeamrcClient.FETCH_TIMEOUT_MS),
    });
    this.checkUpgradeRequired(res);
    if (!res.ok) throw new Error(await this.errorMessage(res, "updateTask failed"));
    const data = (await res.json()) as { task: TaskItem };
    return data.task;
  }

}
