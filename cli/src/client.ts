import { signMessage } from "./auth.js";
import type { Rule, Skill, TeamDefinition } from "./adapters/base.js";
import { validateRuleId } from "./team-yaml.js";

export interface TeamBridgeTeam {
  id: string;
  name: string;
  members: Array<{ name: string; role: string; platform?: string; rules?: string[]; skills?: string[] }>;
  rules?: Rule[];
  skills?: Skill[];
  created_at?: string;
}

export function remoteTeamToDefinition(team: TeamBridgeTeam): TeamDefinition {
  // Validate rule/skill IDs from the relay to prevent path traversal
  const rules = team.rules?.filter((r) => {
    try { validateRuleId(r.id); return true; } catch { return false; }
  });
  const skills = team.skills?.filter((s) => {
    try { validateRuleId(s.id); return true; } catch { return false; }
  });

  return {
    name: team.name,
    members: team.members.map((m) => ({
      name: m.name,
      role: m.role,
      ...(m.rules?.length ? { rules: m.rules } : {}),
      ...(m.skills?.length ? { skills: m.skills } : {}),
    })),
    ...(rules?.length ? { rules } : {}),
    ...(skills?.length ? { skills } : {}),
  };
}

export interface SyncChange {
  content: string;
  updated_at: number; // unix timestamp
}

export interface SyncResult {
  changes: Record<string, SyncChange>;
}

export class TeamBridgeClient {
  private baseUrl: string;
  private privateKey: Uint8Array;
  private token: string;

  constructor(baseUrl: string, privateKey: Uint8Array, token: string) {
    this.baseUrl = baseUrl.replace(/\/$/, "");
    this.privateKey = privateKey;
    this.token = token;
  }

  private async signedHeaders(
    body: string,
  ): Promise<Record<string, string>> {
    const timestamp = Math.floor(Date.now() / 1000).toString();
    const message = `${timestamp}.${body}`;
    const signature = await signMessage(this.privateKey, message);
    return {
      "Content-Type": "application/json",
      "x-tb-signature": signature,
      "x-tb-timestamp": timestamp,
    };
  }

  private async signedGet<T>(path: string): Promise<T> {
    const timestamp = Math.floor(Date.now() / 1000).toString();
    const message = `${timestamp}.GET ${path}`;
    const signature = await signMessage(this.privateKey, message);
    const res = await fetch(`${this.baseUrl}${path}`, {
      method: "GET",
      headers: {
        "x-tb-signature": signature,
        "x-tb-timestamp": timestamp,
      },
    });
    if (!res.ok) {
      throw new Error(`GET ${path} failed: ${res.status} ${await res.text()}`);
    }
    return (await res.json()) as T;
  }

  async createTeam(
    name: string,
    members: Array<{ name: string; role: string; platform: string }>,
  ): Promise<TeamBridgeTeam> {
    const body = JSON.stringify({
      token: this.token,
      team: { name, members },
    });
    const headers = await this.signedHeaders(body);
    const res = await fetch(`${this.baseUrl}/api/teams`, {
      method: "POST",
      headers,
      body,
    });
    if (!res.ok) {
      throw new Error(`createTeam failed: ${res.status} ${await res.text()}`);
    }
    const data = (await res.json()) as { team: TeamBridgeTeam };
    return data.team;
  }

  async getTeam(token: string): Promise<TeamBridgeTeam> {
    const data = await this.signedGet<{ team: TeamBridgeTeam }>(`/api/teams/${token}`);
    return data.team;
  }

  async joinByInvite(inviteCode: string): Promise<TeamBridgeTeam> {
    const body = JSON.stringify({ invite_code: inviteCode, token: this.token });
    const headers = await this.signedHeaders(body);
    const res = await fetch(`${this.baseUrl}/api/join`, {
      method: "POST",
      headers,
      body,
    });
    if (!res.ok) {
      throw new Error(`join failed: ${res.status} ${await res.text()}`);
    }
    const data = (await res.json()) as { team: TeamBridgeTeam };
    return data.team;
  }

  async sync(
    platform: string,
    hashes: Record<string, string>,
    files: Record<string, string> = {},
  ): Promise<SyncResult> {
    const body = JSON.stringify({
      token: this.token,
      platform,
      hashes,
      files,
    });
    const headers = await this.signedHeaders(body);
    const res = await fetch(`${this.baseUrl}/api/sync`, {
      method: "POST",
      headers,
      body,
    });
    if (!res.ok) {
      throw new Error(`sync failed: ${res.status} ${await res.text()}`);
    }
    return (await res.json()) as SyncResult;
  }

  async syncCheck(since: number): Promise<boolean> {
    const params = `token=${encodeURIComponent(this.token)}&since=${since}`;
    const data = await this.signedGet<{ changed: boolean }>(`/api/sync/check?${params}`);
    return data.changed;
  }

  async push(
    platform: string,
    entry: Record<string, string>,
  ): Promise<void> {
    const body = JSON.stringify({ token: this.token, platform, entry });
    const headers = await this.signedHeaders(body);
    const res = await fetch(`${this.baseUrl}/api/push`, {
      method: "POST",
      headers,
      body,
    });
    if (!res.ok) {
      throw new Error(`push failed: ${res.status} ${await res.text()}`);
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
    });
    if (!res.ok) {
      throw new Error(`createDeviceAuth failed: ${res.status} ${await res.text()}`);
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

  async pull(
    platform: string,
  ): Promise<Array<{ key: string; value: string; author: string }>> {
    const params = `token=${encodeURIComponent(this.token)}&platform=${encodeURIComponent(platform)}`;
    const data = await this.signedGet<{ data: Array<{ key: string; value: string; author: string }> }>(`/api/pull?${params}`);
    return data.data;
  }
}
