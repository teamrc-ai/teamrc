import { signMessage } from "./auth.js";

export interface RelayTeam {
  id: string;
  name: string;
  members: Array<{ name: string; role: string; platform: string }>;
  created_at?: string;
}

export interface SyncResult {
  status: string;
  buffered_entries: Array<{ key: string; value: string; author: string }>;
  team?: RelayTeam;
}

export class RelayClient {
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
    const timestamp = Date.now().toString();
    const signPayload = `${timestamp}:${body}`;
    const signature = await signMessage(this.privateKey, signPayload);
    return {
      "Content-Type": "application/json",
      Authorization: `Bearer ${this.token}`,
      "x-tb-signature": signature,
      "x-tb-timestamp": timestamp,
    };
  }

  async createTeam(
    name: string,
    members: Array<{ name: string; role: string; platform: string }>,
  ): Promise<RelayTeam> {
    const body = JSON.stringify({ name, members });
    const headers = await this.signedHeaders(body);
    const res = await fetch(`${this.baseUrl}/api/teams`, {
      method: "POST",
      headers,
      body,
    });
    if (!res.ok) {
      throw new Error(`createTeam failed: ${res.status} ${await res.text()}`);
    }
    const data = (await res.json()) as { data: RelayTeam };
    return data.data;
  }

  async getTeam(teamId: string): Promise<RelayTeam> {
    const body = "";
    const headers = await this.signedHeaders(body);
    const res = await fetch(`${this.baseUrl}/api/teams/${teamId}`, {
      method: "GET",
      headers,
    });
    if (!res.ok) {
      throw new Error(`getTeam failed: ${res.status} ${await res.text()}`);
    }
    const data = (await res.json()) as { data: RelayTeam };
    return data.data;
  }

  async sync(
    teamId: string,
    hashes: Record<string, string>,
  ): Promise<SyncResult> {
    const body = JSON.stringify({ hashes });
    const headers = await this.signedHeaders(body);
    const res = await fetch(`${this.baseUrl}/api/teams/${teamId}/sync`, {
      method: "POST",
      headers,
      body,
    });
    if (!res.ok) {
      throw new Error(`sync failed: ${res.status} ${await res.text()}`);
    }
    const data = (await res.json()) as { data: SyncResult };
    return data.data;
  }

  async push(
    teamId: string,
    entries: Array<{ key: string; value: string }>,
  ): Promise<void> {
    const body = JSON.stringify({ entries });
    const headers = await this.signedHeaders(body);
    const res = await fetch(`${this.baseUrl}/api/teams/${teamId}/push`, {
      method: "POST",
      headers,
      body,
    });
    if (!res.ok) {
      throw new Error(`push failed: ${res.status} ${await res.text()}`);
    }
  }

  async pull(
    teamId: string,
  ): Promise<Array<{ key: string; value: string; author: string }>> {
    const body = "";
    const headers = await this.signedHeaders(body);
    const res = await fetch(`${this.baseUrl}/api/teams/${teamId}/pull`, {
      method: "GET",
      headers,
    });
    if (!res.ok) {
      throw new Error(`pull failed: ${res.status} ${await res.text()}`);
    }
    const data = (await res.json()) as {
      data: Array<{ key: string; value: string; author: string }>;
    };
    return data.data;
  }
}
