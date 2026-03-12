# Implementation Plan: CLI Enhancements & Sync Attribution

**Date:** 2026-03-07
**Status:** Batch 1 + 2 complete, Batch 3 in progress

## Overview

Three batches of work, ordered by priority. Each batch is a logical commit.

---

## Batch 1: Invite Cleanup + Sync Attribution (P0)

### 1a. Remove dead invite columns

The `claimed_at` and `claimed_by_token` fields on invites are unused now that invites are multi-use.

**Files to change:**

1. **New migration** `teamrc/priv/repo/migrations/20260307000001_remove_invite_claimed_fields.exs`
   - `alter table(:invites), do: remove(:claimed_at); remove(:claimed_by_token)`

2. **`teamrc/lib/teamrc/schema/invite.ex`**
   - Remove `field :claimed_at` and `field :claimed_by_token`
   - Remove them from the `cast/3` call

3. **`teamrc/lib/teamrc/teams.ex`**
   - Already cleaned up in this session. Verify no remaining references.

### 1b. Add sync attribution

Track which token pushed each content entry. In-memory only (same lifecycle as content).

**Files to change:**

1. **`teamrc/lib/teamrc/teams.ex`**
   - `do_sync/5`: Add `pushed_by: token` param. When storing content, include `pushed_by` in the content metadata map:
     ```elixir
     Map.put(acc, file, %{content: content, source: platform, pushed_by: token, timestamp: now})
     ```
   - `do_push_buffer/3`: Already receives the full state — extract token from the caller. Change `handle_call({:push_buffer, token, entry}, ...)` to pass token through:
     ```elixir
     team_content = Map.put(team_content, file_key, %{
       content: content_val,
       source: source,
       pushed_by: token,
       timestamp: ...
     })
     ```
   - `do_sync` result: Include `pushed_by` in the changed_files map entries alongside `content` and `updated_at`:
     ```elixir
     Map.put(acc2, file, %{content: content, updated_at: updated_at, pushed_by: meta.pushed_by})
     ```
   - `pull_buffer`: Include `pushed_by` in returned entries:
     ```elixir
     %{"type" => file, "content" => meta.content, "source_platform" => meta.source,
       "pushed_by" => meta.pushed_by, "timestamp" => meta.timestamp}
     ```

2. **`cli/src/client.ts`**
   - Update `SyncChange` interface:
     ```typescript
     export interface SyncChange {
       content: string;
       updated_at: number;
       pushed_by?: string;
     }
     ```
   - No other client changes needed (the field is just passed through).

3. **Tests:**
   - **`teamrc/test/teamrc/teams_test.exs`**: Update sync tests to assert `pushed_by` is present in results. Add a test that verifies the correct token is attributed.
   - **`teamrc/test/teamrc_web/controllers/api_controller_test.exs`**: Update sync response assertions to check for `pushed_by`.

---

## Batch 2: `teamrc clone` + `teamrc invite` + Preview Endpoint (P0/P1)

### 2a. Preview endpoint (backend)

A read-only endpoint that returns a team definition for an invite code without creating a `token_teams` association.

**Files to change:**

1. **`teamrc/lib/teamrc/teams.ex`**
   - Add new client API function:
     ```elixir
     def preview_by_invite(pid \\ __MODULE__, invite_code)
     ```
   - Add GenServer handler that queries the invite (same TTL check as join) and returns the team data WITHOUT calling `upsert_token_team`.

2. **`teamrc/lib/teamrc_web/controllers/api_controller.ex`**
   - Add `preview_team/2` action:
     ```elixir
     def preview_team(conn, %{"invite_code" => invite_code}) do
       case Teams.preview_by_invite(invite_code) do
         {:ok, team} -> json(conn, %{team: team})
         :error -> conn |> put_status(:not_found) |> json(%{error: "invalid_invite"})
       end
     end
     ```

3. **`teamrc/lib/teamrc_web/router.ex`**
   - Add route in the `:api` scope:
     ```elixir
     post "/teams/preview", ApiController, :preview_team
     ```

4. **Tests:**
   - **`teamrc/test/teamrc/teams_test.exs`**: Test `preview_by_invite` returns team without creating token_teams.
   - **`teamrc/test/teamrc_web/controllers/api_controller_test.exs`**: Test the endpoint returns team data, test expired invite returns 404, test that no token_teams row is created.

### 2b. Invite generation endpoint (backend)

Allow existing team members to generate new invite codes from CLI.

**Files to change:**

1. **`teamrc/lib/teamrc/teams.ex`**
   - Add client API:
     ```elixir
     def create_invite(pid \\ __MODULE__, token, ttl_hours \\ 24)
     ```
   - GenServer handler: look up team_id from token, create Invite record, return code + expires_at.
   - Reuse existing `generate_invite_code/0` helper.

2. **`teamrc/lib/teamrc_web/controllers/api_controller.ex`**
   - Add `create_invite/2` action:
     ```elixir
     def create_invite(conn, %{"ttl_hours" => ttl_hours}) do
       token = conn.assigns[:verified_token]
       ttl = min(String.to_integer(ttl_hours), 168)
       case Teams.create_invite(token, ttl) do
         {:ok, invite_code, expires_at} ->
           json(conn, %{invite_code: invite_code, expires_at: DateTime.to_iso8601(expires_at)})
         :error ->
           conn |> put_status(:forbidden) |> json(%{error: "not a team member"})
       end
     end
     ```
   - Handle missing `ttl_hours` with default 24.

3. **`teamrc/lib/teamrc_web/router.ex`**
   - Add route:
     ```elixir
     post "/teams/invite", ApiController, :create_invite
     ```

4. **Tests:** Test invite creation by member, test non-member gets 403, test TTL capping at 168h.

### 2c. CLI client methods

**`cli/src/client.ts`** — add two methods:

```typescript
async previewByInvite(inviteCode: string): Promise<TeamrcTeam> {
  const body = JSON.stringify({ invite_code: inviteCode });
  const headers = await this.signedHeaders(body);
  const res = await fetch(`${this.baseUrl}/api/teams/preview`, {
    method: "POST", headers, body,
  });
  if (!res.ok) throw new Error(await this.errorMessage(res, "preview failed"));
  const data = (await res.json()) as { team: TeamrcTeam };
  return data.team;
}

async createInvite(ttlHours: number = 24): Promise<{ invite_code: string; expires_at: string }> {
  const body = JSON.stringify({ token: this.token, ttl_hours: ttlHours });
  const headers = await this.signedHeaders(body);
  const res = await fetch(`${this.baseUrl}/api/teams/invite`, {
    method: "POST", headers, body,
  });
  if (!res.ok) throw new Error(await this.errorMessage(res, "createInvite failed"));
  return (await res.json()) as { invite_code: string; expires_at: string };
}
```

### 2d. `teamrc clone` command

**`cli/src/index.ts`** — add after the `join` command:

```
teamrc clone <invite-code>
  --relay <url>
  --platform <platform>
  --scope <scope>
  --name <name>        Override cloned team name
```

Logic:
1. `requireKeypair()` + build client
2. Call `client.previewByInvite(inviteCode)` (NOT `joinByInvite`)
3. Convert to TeamDefinition via `remoteTeamToDefinition`
4. If `--name`, override `team.name`
5. Write `agent-team.yaml`
6. Apply to platform(s) via adapters
7. Do NOT save `teamId` to config — print guidance: "This is a local copy. Run `teamrc init` to create your own synced team."
8. Do NOT prompt for account linking

### 2e. `teamrc invite` command

**`cli/src/index.ts`** — add after `clone`:

```
teamrc invite
  --ttl <hours>    (default: 24, max: 168)
```

Logic:
1. `requireClient()`
2. Call `client.createInvite(ttl)`
3. Print invite code + `npx teamrc join <code>` + expiry info

---

## Batch 3: Daemon Sync Modes + `--no-sync` + CLI Polish (P1/P2)

### 3a. Daemon sync modes

**`cli/src/daemon.ts`**:

- Add `syncMode` option to `DaemonOptions`: `"all" | "knowledge" | "none"` (default: `"knowledge"`)
- In `applyRemoteChanges`: filter by sync mode
  - `"knowledge"`: only apply entries where `key.startsWith("knowledge:")`
  - `"none"`: skip all writes, just log what would have changed
  - `"all"`: current behavior (apply everything)
- In `doPushChanges`: same filter — only push changes matching the sync mode
- Update `pollRelay` similarly

**`cli/src/index.ts`** — update daemon command:
```
teamrc daemon
  --sync-mode <mode>    all | knowledge | none (default: knowledge)
  --poll-interval <ms>
```

**`cli/src/__tests__/daemon.test.ts`**: Add tests for each sync mode.

### 3b. `--no-sync` flag on `join`

**`cli/src/index.ts`** — add `--no-sync` option to `join`:

When set:
- Join the team on relay (get the team definition)
- Write agents locally
- Save config WITHOUT `teamId` — this prevents `sync`, `push`, `diff`, `daemon` from working
- Print: "Joined without sync. Your agents are local-only."

This is subtly different from `clone`: `join` consumes the invite (registers the token on the relay for attribution/participants), but `--no-sync` means the daemon and manual sync won't run.

Implementation: save config with a `sync: false` field. `requireClient()` checks this and exits with guidance if sync commands are attempted.

### 3c. `teamrc whoami` command

**`cli/src/index.ts`**:

```
teamrc whoami
```

Reads `~/.teamrc/config.json` only. No network calls. Prints:
- Token (truncated)
- Machine name (from config or "not named")
- Account email (or "not linked")
- Team ID (or "none")
- Relay URL
- Platform

### 3d. `teamrc log` command

**`cli/src/index.ts`**:

```
teamrc log
  --limit <n>   (default: 20)
```

Calls the existing pull buffer endpoint via `client.pull(platform)` — but since pull currently only returns entries from OTHER platforms, we need a small backend change:

**`teamrc/lib/teamrc/teams.ex`** — add `pull_all/2` that returns ALL entries (not filtered by platform). Or add an `include_own: true` option.

**`teamrc/lib/teamrc_web/controllers/api_controller.ex`** — add a `GET /api/log` endpoint that returns all recent content entries with attribution.

The CLI formats each entry as:
```
2026-03-07 14:23  knowledge:project  trc_ak_abc12...  claude-code
```

### 3e. Update docs

- **`docs/security-audit.md`**: Already updated for multi-use invites. Add note about sync attribution.
- **`README.md`**: Update CLI command reference with new commands.
- **`teamrc/README.md`**: Update API endpoint docs.

---

## File Change Summary

| File | Batch | Changes |
|---|---|---|
| `teamrc/priv/repo/migrations/20260307000001_*` | 1 | New migration: drop claimed columns |
| `teamrc/lib/teamrc/schema/invite.ex` | 1 | Remove claimed_at, claimed_by_token fields |
| `teamrc/lib/teamrc/teams.ex` | 1+2 | Attribution in content maps, `preview_by_invite`, `create_invite` |
| `teamrc/lib/teamrc_web/controllers/api_controller.ex` | 2 | `preview_team`, `create_invite` actions |
| `teamrc/lib/teamrc_web/router.ex` | 2 | New routes: preview, invite, log |
| `cli/src/client.ts` | 1+2 | `SyncChange.pushed_by`, `previewByInvite`, `createInvite` |
| `cli/src/index.ts` | 2+3 | `clone`, `invite`, `whoami`, `log` commands; `--no-sync` on join |
| `cli/src/daemon.ts` | 3 | `syncMode` option with filtering |
| `cli/src/config.ts` | 3 | `sync?: boolean` field on config |
| `teamrc/test/teamrc/teams_test.exs` | 1+2 | Attribution assertions, preview/invite tests |
| `teamrc/test/teamrc_web/controllers/api_controller_test.exs` | 1+2 | New endpoint tests |
| `cli/src/__tests__/daemon.test.ts` | 3 | Sync mode tests |
| `docs/security-audit.md` | 3 | Attribution note |

## Dead Code to Remove

- `Invite.changeset`: Remove `claimed_at` and `claimed_by_token` from cast list
- `Invite` schema: Remove the two dead fields
- After migration runs: the columns are gone from DB
- Any remaining references to `claimed_at` or `claimed_by_token` in tests

## Implementation Order

```
Batch 1 (one commit):
  1a. Migration + schema cleanup
  1b. Attribution in teams.ex + client.ts
  1c. Update tests
  → commit: "feat: sync attribution + remove dead invite columns"

Batch 2 (one commit):
  2a. Preview endpoint (backend)
  2b. Invite endpoint (backend)
  2c. Client methods
  2d. teamrc clone command
  2e. teamrc invite command
  2f. Tests
  → commit: "feat: add clone, invite, and preview commands"

Batch 3 (one commit):
  3a. Daemon sync modes (default: knowledge)
  3b. --no-sync on join
  3c. teamrc whoami
  3d. teamrc log + backend log endpoint
  3e. Doc updates
  → commit: "feat: daemon sync modes, whoami, log, --no-sync"
```
