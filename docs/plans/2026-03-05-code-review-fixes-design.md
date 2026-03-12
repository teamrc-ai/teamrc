# TeamBridge Code Review Fixes — Design

Date: 2026-03-05

## Overview

Fix all issues identified in the code review. Eight changes organized into three categories: rename/consolidation, API contract fixes, and targeted bug fixes.

## Fix 1: Rename app `:relay` to `:teambridge` and consolidate directories

### Elixir/Phoenix (relay/ directory)

**mix.exs:**
- `app: :relay` -> `app: :teambridge`
- Esbuild key: `relay:` -> `teambridge:`
- Tailwind key: `relay:` -> `teambridge:`
- Aliases referencing `relay` -> `teambridge`

**Config files (config/*.exs):**
- All `config :relay` -> `config :teambridge`
- All `Application.get_env(:relay, ...)` -> `Application.get_env(:teambridge, ...)`

**Endpoint:**
- `otp_app: :relay` -> `otp_app: :teambridge`

**Repo:**
- `otp_app: :relay` -> `otp_app: :teambridge`

**File moves (no module renames, modules are already Teambridge/TeambridgeWeb):**
- `lib/relay_web.ex` -> `lib/teambridge_web.ex`
- `lib/relay.ex` -> `lib/teambridge.ex`
- `lib/relay/application.ex` -> `lib/teambridge/application.ex`
- `lib/relay_web/endpoint.ex` -> `lib/teambridge_web/endpoint.ex`
- `lib/relay_web/router.ex` -> `lib/teambridge_web/router.ex`
- `lib/relay_web/telemetry.ex` -> `lib/teambridge_web/telemetry.ex`
- `lib/relay_web/gettext.ex` -> `lib/teambridge_web/gettext.ex`
- `lib/relay_web/controllers/*` -> `lib/teambridge_web/controllers/*`
- `lib/relay_web/components/*` -> `lib/teambridge_web/components/*`
- `lib/relay_web/live/*` -> `lib/teambridge_web/live/*`
- `test/relay_web/*` -> `test/teambridge_web/*`
- Delete empty `lib/relay/`, `lib/relay_web/`, `test/relay_web/`

**Plug.Static `from:` option:**
- `from: :relay` -> `from: :teambridge`

**app.css `@source` directive:**
- `@source "../../lib/relay_web"` -> `@source "../../lib/teambridge_web"`

### CLI (cli/ directory)

**Type renames:**
- `RelayTeam` -> `TeamBridgeTeam`
- `RelayClient` -> `TeamBridgeClient`
- `SyncChange` / `SyncResult` stay as-is (not relay-specific names)

**File renames:**
- `src/relay-client.ts` -> `src/client.ts`

**Import updates:**
- All files importing from `./relay-client.js` -> `./client.js`

### Root .gitignore
- `relay/_build/` -> update if the directory itself is renamed (TBD — may keep `relay/` as the directory name since it describes the component's role)

**Decision: keep `relay/` as the directory name.** It describes what the component is (the relay server). The app name `:teambridge` is the product name. These serve different purposes.

## Fix 2: Client/server API contract alignment

### Relay side

**`team_to_map/1` in `teams.ex`:**
- Add `"id" => team.id` to the returned map

**`create_team` in `api_controller.ex`:**
- Change response from `%{status: "ok", team: team_data}` to `%{team: team_data}`
- The team_data now includes `id` from Fix above

### CLI side

**`createTeam` in `client.ts`:**
- Change from `(await res.json()) as { data: TeamBridgeTeam }` / `return data.data`
- To `(await res.json()) as { team: TeamBridgeTeam }` / `return data.team`

**`getTeam` usage in `index.ts`:**
- `client.getTeam(config.teamId)` is wrong — the API route is `GET /api/teams/:token`
- Change to `client.getTeam(config.token)` (use token, not teamId)
- Or better: store token as the team identifier (since the relay maps token -> team internally)

**`joinByInvite` in `client.ts`:**
- Response shape `{ team: TeamBridgeTeam }` — already correct
- But the returned team map now includes `id`, so `joinedTeam.id` works

## Fix 3: Persist token-to-team mappings

### New migration

```elixir
create table(:token_teams, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :token, :string, null: false
  add :team_id, references(:teams, type: :binary_id, on_delete: :delete_all), null: false
  timestamps(type: :utc_datetime)
end

create unique_index(:token_teams, [:token])
create index(:token_teams, [:team_id])
```

### New schema: `Teambridge.Schema.TokenTeam`

Fields: `id`, `token`, `team_id`, timestamps.

### GenServer changes

**`init/1`:** Load all `token_teams` rows into in-memory `token_teams` map on startup.

**`put_team`:** After creating/updating team in DB, upsert `token_teams` row.

**`join_by_invite`:** After resolving invite, insert `token_teams` row.

**Sync state stays in-memory only:** `hashes`, `content`, `last_updated_at` are ephemeral.

## Fix 4: Track invite claims

**`join_by_invite` in `teams.ex`:**
- After successful join, update the invite record:
  ```elixir
  invite
  |> Invite.changeset(%{claimed_at: now, claimed_by_token: token})
  |> Repo.update()
  ```
- Add `claimed_at` and `claimed_by_token` to the Invite changeset's permitted fields.

## Fix 5: Harden `String.to_existing_atom` in LiveView

**`team_live.ex` `handle_event("update_member", ...)`:**

Replace:
```elixir
field = String.to_existing_atom(field)
```

With:
```elixir
field = case field do
  "name" -> :name
  "role" -> :role
  _ -> nil
end
```

Return `{:noreply, socket}` early if `field` is nil.

## Fix 6: Fix `Process.sleep` in test

**`teams_test.exs:89`:**

Replace:
```elixir
Process.sleep(50)
```

With:
```elixir
_ = :sys.get_state(pid)
```

## Fix 7: Fix agent description text in CLI

**`claude-code.ts` `buildAgentFile`:**

The generated `description` field currently says:
```
"${member.role} on the ${teamName} team. Use proactively when tasks relate to ${member.role.toLowerCase()}."
```

The existing agents in `.claude/agents/` say:
```
"${member.role} on the ${teamName} team. Use when tasks relate to ${member.role.toLowerCase()}."
```

Change to match the existing pattern (drop "proactively").

## Fix 8: Update `parseAgentFile` role extraction

The regex `description.match(/^(.+?)\s+on the\s+/)` extracts role from the description field. This works with both the old and new description format, so no change needed here. Verified.

## Files Changed (summary)

### Elixir
- `mix.exs` — app name, esbuild/tailwind keys, aliases
- `config/config.exs`, `config/dev.exs`, `config/test.exs`, `config/prod.exs`, `config/runtime.exs` — `:relay` -> `:teambridge`
- `lib/teambridge_web/endpoint.ex` — otp_app (moved from relay_web/)
- `lib/teambridge/repo.ex` — otp_app
- `lib/teambridge_web/plugs/verify_signature.ex` — Application.get_env
- `lib/teambridge_web/plugs/rate_limiter.ex` — no change needed
- `lib/teambridge/teams.ex` — add token_teams persistence, add id to team_to_map, track invite claims
- `lib/teambridge_web/controllers/api_controller.ex` — fix create_team response
- `lib/teambridge_web/live/team_live.ex` — harden field atom conversion
- `lib/teambridge/schema/token_team.ex` — new file
- `lib/teambridge/schema/invite.ex` — add claimed fields to changeset
- `priv/repo/migrations/*_create_token_teams.exs` — new migration
- `test/teambridge/teams_test.exs` — fix Process.sleep
- All moved files from relay_web/ and relay/

### TypeScript
- `cli/src/client.ts` — renamed from relay-client.ts, type renames
- `cli/src/index.ts` — import update, fix getTeam call
- `cli/src/daemon.ts` — import update
- `cli/src/adapters/claude-code.ts` — fix description text
