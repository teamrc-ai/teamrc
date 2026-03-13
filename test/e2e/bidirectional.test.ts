import { describe, it, before } from "node:test";
import assert from "node:assert/strict";
import {
  waitForServer,
  generateTestKeypair,
  signedPost,
  signedGet,
  createTeamWithKeypair,
  testSetup,
} from "./helpers.ts";

before(async () => {
  await waitForServer();
});

describe("Bidirectional (web ↔ CLI)", () => {
  it("web-created team is joinable and pullable via CLI", async () => {
    // Create team via test helper (simulates web wizard)
    const { user_id } = await testSetup("create_user") as { user_id: string };
    const webTeam = (await testSetup("create_team_web", {
      owner_user_id: user_id,
      team: {
        name: "web-created",
        members: [{ name: "WebAgent", role: "Assistant" }],
      },
    })) as { invite_code: string; team_id: string };

    // CLI user joins via invite
    const cli = await generateTestKeypair();
    const joinRes = await signedPost(
      "/api/join",
      { invite_code: webTeam.invite_code, token: cli.token },
      cli,
    );
    assert.equal(joinRes.status, 200);

    // CLI pulls full team data
    const getRes = await signedGet(
      `/api/teams/${cli.token}?team_id=${webTeam.team_id}`,
      cli,
    );
    assert.equal(getRes.status, 200);
    const data = (await getRes.json()) as { team: Record<string, unknown> };
    assert.equal(data.team.name, "web-created");
    const members = data.team.members as Array<{ name: string }>;
    assert.equal(members[0].name, "WebAgent");
  });

  it("CLI-created team is readable via server-side context", async () => {
    // CLI creates a team
    const cli = await createTeamWithKeypair("cli-created", [
      { name: "CliAgent", role: "Developer" },
    ]);

    // Verify via test helper (simulates web dashboard reading)
    const serverData = (await testSetup("get_team", {
      token: cli.token,
      team_id: cli.teamId,
    })) as { team: Record<string, unknown> };
    assert.equal(serverData.team.name, "cli-created");
  });

  it("web updates member → CLI pull sees changes", async () => {
    // CLI creates team
    const cli = await createTeamWithKeypair("web-update", [
      { name: "Agent", role: "Original role" },
    ]);

    // Simulate web update via test helper
    await testSetup("update_team", {
      token: cli.token,
      team_id: cli.teamId,
      team: {
        name: "web-update",
        members: [{ name: "Agent", role: "Updated via web" }],
      },
    });

    // CLI pulls and sees the web update
    const getRes = await signedGet(
      `/api/teams/${cli.token}?team_id=${cli.teamId}`,
      cli,
    );
    assert.equal(getRes.status, 200);
    const data = (await getRes.json()) as { team: Record<string, unknown> };
    const members = data.team.members as Array<{ name: string; role: string }>;
    assert.equal(members[0].role, "Updated via web");
  });

  it("CLI pushes update → server-side context reads it", async () => {
    const cli = await createTeamWithKeypair("cli-push", [
      { name: "Agent", role: "Original" },
    ]);
    const baseHash = cli.team.hash as string;

    // CLI pushes update
    await signedPost(
      "/api/teams",
      {
        token: cli.token,
        team_id: cli.teamId,
        base_hash: baseHash,
        team: {
          name: "cli-push",
          members: [{ name: "Agent", role: "Pushed from CLI" }],
        },
      },
      cli,
    );

    // Server-side reads the update
    const serverData = (await testSetup("get_team", {
      token: cli.token,
      team_id: cli.teamId,
    })) as { team: Record<string, unknown> };
    const members = (serverData.team as Record<string, unknown>).members as Array<{
      name: string;
      role: string;
    }>;
    assert.equal(members[0].role, "Pushed from CLI");
  });
});
