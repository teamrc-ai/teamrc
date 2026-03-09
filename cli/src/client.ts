import { signMessage } from "./auth.js";
import type { Skill, TeamDefinition } from "./adapters/base.js";

import { validateSkillId } from "./team-yaml.js";

export interface TeamrcTeam {
  id: string;
  name: string;
  members: Array<{ name: string; role: string; platform?: string; skills?: string[]; soul?: string }>;
  skills?: Skill[];
  knowledge?: string;
  updated_at?: string;
  created_at?: string;
}

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
  return s.replace(/^---\s*$/gm, "– – –");
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

export class TeamrcClient {
  private baseUrl: string;
  private privateKey: Uint8Array;
  private token: string;
  private teamId?: string;

  constructor(baseUrl: string, privateKey: Uint8Array, token: string, teamId?: string) {
    this.baseUrl = baseUrl.replace(/\/$/, "");
    this.privateKey = privateKey;
    this.token = token;
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

  private async signedHeaders(
    body: string,
  ): Promise<Record<string, string>> {
    const timestamp = Math.floor(Date.now() / 1000).toString();
    const message = `${timestamp}.${body}`;
    const signature = await signMessage(this.privateKey, message);
    return {
      "Content-Type": "application/json",
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
        "x-trc-signature": signature,
        "x-trc-timestamp": timestamp,
      },
    });
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
    });
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
    const data = await this.signedGet<{ team: TeamrcTeam }>(url);
    return data.team;
  }

  async joinByInvite(inviteCode: string): Promise<TeamrcTeam> {
    const body = JSON.stringify({ invite_code: inviteCode, token: this.token });
    const headers = await this.signedHeaders(body);
    const res = await fetch(`${this.baseUrl}/api/join`, {
      method: "POST",
      headers,
      body,
    });
    if (!res.ok) {
      throw new Error(await this.errorMessage(res, "join failed"));
    }
    const data = (await res.json()) as { team: TeamrcTeam };
    return data.team;
  }

  async pushTeam(team: TeamDefinition, knowledge?: string): Promise<TeamrcTeam> {
    const body = JSON.stringify({
      token: this.token,
      ...(this.teamId ? { team_id: this.teamId } : {}),
      team: {
        name: team.name,
        members: team.members.map((m) => ({
          name: m.name,
          role: m.role,
          ...(m.skills?.length ? { skills: m.skills } : {}),
        })),
        ...(team.skills?.length ? { skills: team.skills } : {}),
        ...(knowledge ? { knowledge } : {}),
      },
    });
    const headers = await this.signedHeaders(body);
    const res = await fetch(`${this.baseUrl}/api/teams`, {
      method: "POST",
      headers,
      body,
    });
    if (!res.ok) {
      throw new Error(await this.errorMessage(res, "pushTeam failed"));
    }
    const data = (await res.json()) as { team: TeamrcTeam };
    return data.team;
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
    });
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
    });
    if (!res.ok) throw new Error(await this.errorMessage(res, "preview failed"));
    const data = (await res.json()) as { team: TeamrcTeam };
    return data.team;
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
    });
    if (!res.ok) throw new Error(await this.errorMessage(res, "createInvite failed"));
    return (await res.json()) as { invite_code: string; expires_at: string };
  }

}
