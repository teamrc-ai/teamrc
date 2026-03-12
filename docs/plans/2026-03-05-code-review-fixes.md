# Code Review Fixes Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix all issues from the code review: rename app to `:teamrc`, consolidate directories, fix API contracts, persist token mappings, and targeted bug fixes.

**Architecture:** The Elixir app name changes from `:relay` to `:teamrc`. All files under `lib/relay_web/` and `lib/relay/` move to `lib/teamrc_web/` and `lib/teamrc/`. Tests follow. The CLI renames `RelayClient`/`RelayTeam` to `TeamrcClient`/`teamrcTeam`. API response shapes are aligned between server and client. Token-to-team mappings get persisted to Postgres.

**Tech Stack:** Elixir/Phoenix 1.8, Ecto, PostgreSQL, TypeScript/Node.js CLI

---

### Task 1: Move Elixir files from relay_web/ and relay/ to teamrc_web/ and teamrc/

This task moves files only. No content changes yet.

**Files:**
- Move: `relay/lib/relay_web.ex` -> `relay/lib/teamrc_web.ex`
- Move: `relay/lib/relay.ex` -> `relay/lib/teamrc.ex`
- Move: `relay/lib/relay/application.ex` -> `relay/lib/teamrc/application.ex`
- Move: `relay/lib/relay_web/endpoint.ex` -> `relay/lib/teamrc_web/endpoint.ex`
- Move: `relay/lib/relay_web/router.ex` -> `relay/lib/teamrc_web/router.ex`
- Move: `relay/lib/relay_web/telemetry.ex` -> `relay/lib/teamrc_web/telemetry.ex`
- Move: `relay/lib/relay_web/gettext.ex` -> `relay/lib/teamrc_web/gettext.ex`
- Move: `relay/lib/relay_web/controllers/error_json.ex` -> `relay/lib/teamrc_web/controllers/error_json.ex`
- Move: `relay/lib/relay_web/controllers/error_html.ex` -> `relay/lib/teamrc_web/controllers/error_html.ex`
- Move: `relay/lib/relay_web/controllers/page_controller.ex` -> `relay/lib/teamrc_web/controllers/page_controller.ex`
- Move: `relay/lib/relay_web/controllers/page_html.ex` -> `relay/lib/teamrc_web/controllers/page_html.ex`
- Move: `relay/lib/relay_web/controllers/page_html/home.html.heex` -> `relay/lib/teamrc_web/controllers/page_html/home.html.heex`
- Move: `relay/lib/relay_web/components/core_components.ex` -> `relay/lib/teamrc_web/components/core_components.ex`
- Move: `relay/lib/relay_web/components/layouts.ex` -> `relay/lib/teamrc_web/components/layouts.ex`
- Move: `relay/lib/relay_web/components/layouts/root.html.heex` -> `relay/lib/teamrc_web/components/layouts/root.html.heex`
- Move: `relay/lib/relay_web/live/team_live.ex` -> `relay/lib/teamrc_web/live/team_live.ex`
- Move: `relay/test/relay_web/controllers/error_json_test.exs` -> `relay/test/teamrc_web/controllers/error_json_test.exs`
- Move: `relay/test/relay_web/controllers/error_html_test.exs` -> `relay/test/teamrc_web/controllers/error_html_test.exs`
- Move: `relay/test/relay_web/controllers/page_controller_test.exs` -> `relay/test/teamrc_web/controllers/page_controller_test.exs`
- Move: `relay/test/relay_web/live/team_live_test.exs` -> `relay/test/teamrc_web/live/team_live_test.exs`
- Delete: empty `relay/lib/relay/`, `relay/lib/relay_web/`, `relay/test/relay_web/`

**Step 1: Create target directories and move files**

```bash
cd /Users/benjamincates/Dev/agent-sync/relay

# Create target directories
mkdir -p lib/teamrc_web/controllers/page_html
mkdir -p lib/teamrc_web/components/layouts
mkdir -p lib/teamrc_web/live
mkdir -p test/teamrc_web/controllers
mkdir -p test/teamrc_web/live

# Move lib files
mv lib/relay_web.ex lib/teamrc_web.ex
mv lib/relay.ex lib/teamrc.ex
mv lib/relay/application.ex lib/teamrc/application.ex
mv lib/relay_web/endpoint.ex lib/teamrc_web/endpoint.ex
mv lib/relay_web/router.ex lib/teamrc_web/router.ex
mv lib/relay_web/telemetry.ex lib/teamrc_web/telemetry.ex
mv lib/relay_web/gettext.ex lib/teamrc_web/gettext.ex
mv lib/relay_web/controllers/error_json.ex lib/teamrc_web/controllers/error_json.ex
mv lib/relay_web/controllers/error_html.ex lib/teamrc_web/controllers/error_html.ex
mv lib/relay_web/controllers/page_controller.ex lib/teamrc_web/controllers/page_controller.ex
mv lib/relay_web/controllers/page_html.ex lib/teamrc_web/controllers/page_html.ex
mv lib/relay_web/controllers/page_html/home.html.heex lib/teamrc_web/controllers/page_html/home.html.heex
mv lib/relay_web/components/core_components.ex lib/teamrc_web/components/core_components.ex
mv lib/relay_web/components/layouts.ex lib/teamrc_web/components/layouts.ex
mv lib/relay_web/components/layouts/root.html.heex lib/teamrc_web/components/layouts/root.html.heex
mv lib/relay_web/live/team_live.ex lib/teamrc_web/live/team_live.ex

# Move test files
mv test/relay_web/controllers/error_json_test.exs test/teamrc_web/controllers/error_json_test.exs
mv test/relay_web/controllers/error_html_test.exs test/teamrc_web/controllers/error_html_test.exs
mv test/relay_web/controllers/page_controller_test.exs test/teamrc_web/controllers/page_controller_test.exs
mv test/relay_web/live/team_live_test.exs test/teamrc_web/live/team_live_test.exs

# Remove empty directories
rm -rf lib/relay lib/relay_web test/relay_web
```

**Step 2: Commit**

```bash
git add -A
git commit -m "refactor: move files from relay_web/ to teamrc_web/"
```

---

### Task 2: Rename app from :relay to :teamrc in all Elixir config and source files

**Files:**
- Modify: `relay/mix.exs` — app name, esbuild/tailwind keys, aliases
- Modify: `relay/config/config.exs` — all `config :relay` -> `config :teamrc`
- Modify: `relay/config/dev.exs` — all `config :relay` -> `config :teamrc`, watcher keys, live_reload patterns
- Modify: `relay/config/test.exs` — all `config :relay` -> `config :teamrc`
- Modify: `relay/config/prod.exs` — all `config :relay` -> `config :teamrc`
- Modify: `relay/config/runtime.exs` — all `config :relay` -> `config :teamrc`
- Modify: `relay/lib/teamrc_web/endpoint.ex` — `otp_app: :relay` -> `otp_app: :teamrc`, `from: :relay` -> `from: :teamrc`
- Modify: `relay/lib/teamrc/repo.ex` — `otp_app: :relay` -> `otp_app: :teamrc`
- Modify: `relay/lib/teamrc_web/plugs/verify_signature.ex` — `Application.get_env(:relay,` -> `Application.get_env(:teamrc,`
- Modify: `relay/lib/teamrc_web/plugs/cors.ex` — `Application.get_env(:relay,` -> `Application.get_env(:teamrc,`
- Modify: `relay/assets/css/app.css` — `@source "../../lib/relay_web"` -> `@source "../../lib/teamrc_web"`
- Modify: `relay/assets/js/app.js` — `phoenix-colocated/relay` -> `phoenix-colocated/teamrc`

**Step 1: Update mix.exs**

In `relay/mix.exs`, make these changes:
- Line 6: `app: :relay` -> `app: :teamrc`
- Line 80: `"assets.build": ["compile", "tailwind relay", "esbuild relay"]` -> `"assets.build": ["compile", "tailwind teamrc", "esbuild teamrc"]`
- Line 82-84: `"tailwind relay --minify"` -> `"tailwind teamrc --minify"`, `"esbuild relay --minify"` -> `"esbuild teamrc --minify"`

**Step 2: Update config/config.exs**

Replace all occurrences of `config :relay` with `config :teamrc`. There are 3 occurrences (lines 10, 16, and the esbuild/tailwind sections).

In esbuild config (line 29): `relay:` -> `teamrc:`
In tailwind config (line 39): `relay:` -> `teamrc:`

**Step 3: Update config/dev.exs**

Replace all `config :relay` with `config :teamrc` (lines 3, 19, 56, 71).
Line 28: `[:relay, ~w(--sourcemap=inline --watch)]` -> `[:teamrc, ~w(--sourcemap=inline --watch)]`
Line 29: `[:relay, ~w(--watch)]` -> `[:teamrc, ~w(--watch)]`
Lines 65-66: `~r"lib/relay_web/router\.ex$"` -> `~r"lib/teamrc_web/router\.ex$"`, `~r"lib/relay_web/(controllers|live|components)/.*\.(ex|heex)$"` -> `~r"lib/teamrc_web/(controllers|live|components)/.*\.(ex|heex)$"`

**Step 4: Update config/test.exs**

Replace all `config :relay` with `config :teamrc` (lines 3, 14, 21).

**Step 5: Update config/prod.exs**

Read file first, then replace `config :relay` with `config :teamrc`.

**Step 6: Update config/runtime.exs**

Replace all `config :relay` with `config :teamrc` (lines 20, 23, 34, 53, 55, and comments).

**Step 7: Update endpoint.ex**

In `relay/lib/teamrc_web/endpoint.ex`:
- Line 2: `otp_app: :relay` -> `otp_app: :teamrc`
- Line 26: `from: :relay` -> `from: :teamrc`

**Step 8: Update repo.ex**

In `relay/lib/teamrc/repo.ex`:
- Line 3: `otp_app: :relay` -> `otp_app: :teamrc`

**Step 9: Update verify_signature.ex**

In `relay/lib/teamrc_web/plugs/verify_signature.ex`:
- Line 40: `Application.get_env(:relay, :skip_auth, false)` -> `Application.get_env(:teamrc, :skip_auth, false)`

**Step 10: Update cors.ex**

In `relay/lib/teamrc_web/plugs/cors.ex`:
- Line 14: `Application.get_env(:relay, :cors_origins, [])` -> `Application.get_env(:teamrc, :cors_origins, [])`

**Step 11: Update verify_signature_test.exs**

In `relay/test/teamrc_web/plugs/verify_signature_test.exs`:
- Line 8: `Application.get_env(:relay, :skip_auth, false)` -> `Application.get_env(:teamrc, :skip_auth, false)`
- Line 9: `Application.put_env(:relay, :skip_auth, false)` -> `Application.put_env(:teamrc, :skip_auth, false)`
- Line 10: `Application.put_env(:relay, :skip_auth, original)` -> `Application.put_env(:teamrc, :skip_auth, original)`

**Step 12: Update app.css**

In `relay/assets/css/app.css`:
- Line 7: `@source "../../lib/relay_web"` -> `@source "../../lib/teamrc_web"`

**Step 13: Update app.js**

In `relay/assets/js/app.js`:
- Line 25: `import {hooks as colocatedHooks} from "phoenix-colocated/relay"` -> `import {hooks as colocatedHooks} from "phoenix-colocated/teamrc"`

**Step 14: Verify compilation**

```bash
cd /Users/benjamincates/Dev/agent-sync/relay && mix compile
```

Expected: compiles with no errors.

**Step 15: Commit**

```bash
git add -A
git commit -m "refactor: rename OTP app from :relay to :teamrc"
```

---

### Task 3: Add token_teams persistence (new migration + schema + GenServer changes)

**Files:**
- Create: `relay/priv/repo/migrations/20260305000002_create_token_teams.exs`
- Create: `relay/lib/teamrc/schema/token_team.ex`
- Modify: `relay/lib/teamrc/teams.ex` — load token_teams on init, persist on put_team/join_by_invite

**Step 1: Create migration**

Create `relay/priv/repo/migrations/20260305000002_create_token_teams.exs`:

```elixir
defmodule Teamrc.Repo.Migrations.CreateTokenTeams do
  use Ecto.Migration

  def change do
    create table(:token_teams, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :token, :string, null: false
      add :team_id, references(:teams, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:token_teams, [:token])
    create index(:token_teams, [:team_id])
  end
end
```

**Step 2: Create schema**

Create `relay/lib/teamrc/schema/token_team.ex`:

```elixir
defmodule Teamrc.Schema.TokenTeam do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "token_teams" do
    field :token, :string
    belongs_to :team, Teamrc.Schema.Team, type: :binary_id

    timestamps(type: :utc_datetime)
  end

  def changeset(token_team, attrs) do
    token_team
    |> cast(attrs, [:token, :team_id])
    |> validate_required([:token, :team_id])
    |> unique_constraint(:token)
  end
end
```

**Step 3: Update Teams GenServer — add alias and update init**

In `relay/lib/teamrc/teams.ex`:

Add to the aliases at line 6:
```elixir
alias Teamrc.Schema.{Team, Member, Invite, TokenTeam}
```

Replace `init/1` (lines 84-97) with:
```elixir
@impl true
def init(_opts) do
  schedule_cleanup()

  # Load persisted token->team mappings from DB
  token_teams =
    Repo.all(TokenTeam)
    |> Map.new(fn tt -> {tt.token, tt.team_id} end)

  {:ok, %{
    token_teams: token_teams,
    hashes: %{},
    content: %{},
    last_updated_at: %{}
  }}
end
```

**Step 4: Update handle_call for :put_team to persist token mapping**

Replace the `handle_call({:put_team, ...})` function (lines 100-118) with:
```elixir
@impl true
def handle_call({:put_team, token, team_attrs}, _from, state) do
  team_data = normalize_team(team_attrs)

  case Map.get(state.token_teams, token) do
    nil ->
      case create_team_in_db(team_data) do
        {:ok, team} ->
          upsert_token_team(token, team.id)
          state = put_in(state, [:token_teams, token], team.id)
          {:reply, {:ok, team_to_map(team)}, state}

        {:error, reason} ->
          {:reply, {:error, reason}, state}
      end

    team_id ->
      team = update_team_in_db(team_id, team_data)
      {:reply, {:ok, team_to_map(team)}, state}
  end
end
```

**Step 5: Update handle_call for :join_by_invite to persist token mapping**

Replace lines 138-158 with:
```elixir
def handle_call({:join_by_invite, invite_code, token}, _from, state) do
  now = DateTime.utc_now() |> DateTime.truncate(:second)

  invite =
    from(i in Invite,
      where: i.code == ^invite_code and i.expires_at > ^now,
      preload: [team: :members]
    )
    |> Repo.one()

  case invite do
    nil ->
      {:reply, :error, state}

    %Invite{team: team} ->
      # Track invite claim
      invite
      |> Invite.changeset(%{claimed_at: now, claimed_by_token: token})
      |> Repo.update()

      # Persist and cache token->team mapping
      upsert_token_team(token, team.id)
      state = put_in(state, [:token_teams, token], team.id)

      {:reply, {:ok, team_to_map(team)}, state}
  end
end
```

**Step 6: Add upsert_token_team helper**

Add before the `schedule_cleanup` private function (before line 333):
```elixir
defp upsert_token_team(token, team_id) do
  %TokenTeam{}
  |> TokenTeam.changeset(%{token: token, team_id: team_id})
  |> Repo.insert(
    on_conflict: {:replace, [:team_id, :updated_at]},
    conflict_target: :token
  )
end
```

**Step 7: Run migration**

```bash
cd /Users/benjamincates/Dev/agent-sync/relay && mix ecto.migrate
```

Expected: migration runs successfully.

**Step 8: Run tests**

```bash
cd /Users/benjamincates/Dev/agent-sync/relay && mix test test/teamrc/teams_test.exs
```

Expected: all tests pass.

**Step 9: Commit**

```bash
git add -A
git commit -m "feat: persist token-to-team mappings in Postgres"
```

---

### Task 4: Add team ID to team_to_map and fix API response shapes

**Files:**
- Modify: `relay/lib/teamrc/teams.ex:391-400` — add `"id"` to team_to_map
- Modify: `relay/lib/teamrc_web/controllers/api_controller.ex:17-31` — fix create_team response
- Modify: `relay/test/teamrc_web/controllers/api_controller_test.exs` — update assertion
- Modify: `relay/test/teamrc_web/plugs/verify_signature_test.exs:44-47` — update assertion

**Step 1: Update team_to_map in teams.ex**

Replace `team_to_map/1` (lines 391-400) with:
```elixir
defp team_to_map(%Team{} = team) do
  %{
    "id" => team.id,
    "name" => team.name,
    "members" =>
      Enum.map(team.members, fn m ->
        member = %{"name" => m.name, "role" => m.role}
        if m.soul, do: Map.put(member, "soul", m.soul), else: member
      end)
  }
end
```

**Step 2: Fix create_team response in api_controller.ex**

Replace `create_team` function (lines 17-31) with:
```elixir
def create_team(conn, %{"token" => token, "team" => team}) do
  with :ok <- validate_team(team) do
    team = sanitize_team(team)
    {:ok, team_data} = Teams.put_team(token, team)

    conn
    |> put_status(:created)
    |> json(%{team: team_data})
  else
    {:error, reason} ->
      conn
      |> put_status(:bad_request)
      |> json(%{error: reason})
  end
end
```

**Step 3: Update api_controller_test.exs create_team assertion**

In `relay/test/teamrc_web/controllers/api_controller_test.exs`, line 14:
Replace:
```elixir
assert resp["status"] == "ok"
assert resp["team"]["name"] == "Test Team"
```
With:
```elixir
assert resp["team"]["name"] == "Test Team"
assert resp["team"]["id"]
```

**Step 4: Update verify_signature_test.exs create_team assertion**

In `relay/test/teamrc_web/plugs/verify_signature_test.exs`, lines 44-46:
Replace:
```elixir
resp = json_response(conn, 201)
assert resp["status"] == "ok"
assert resp["team"]["name"] == "test-team"
```
With:
```elixir
resp = json_response(conn, 201)
assert resp["team"]["name"] == "test-team"
assert resp["team"]["id"]
```

**Step 5: Run tests**

```bash
cd /Users/benjamincates/Dev/agent-sync/relay && mix test
```

Expected: all tests pass.

**Step 6: Commit**

```bash
git add -A
git commit -m "fix: add team ID to API responses and fix create_team shape"
```

---

### Task 5: Update Invite changeset to accept claimed fields

**Files:**
- Modify: `relay/lib/teamrc/schema/invite.ex:19` — add claimed fields to cast

**Step 1: Update invite changeset**

In `relay/lib/teamrc/schema/invite.ex`, replace line 19:
```elixir
|> cast(attrs, [:code, :expires_at, :team_id])
```
With:
```elixir
|> cast(attrs, [:code, :expires_at, :team_id, :claimed_at, :claimed_by_token])
```

**Step 2: Run tests**

```bash
cd /Users/benjamincates/Dev/agent-sync/relay && mix test
```

Expected: all tests pass.

**Step 3: Commit**

```bash
git add -A
git commit -m "fix: allow invite changeset to track claim data"
```

---

### Task 6: Harden String.to_existing_atom in TeamLive

**Files:**
- Modify: `relay/lib/teamrc_web/live/team_live.ex:121-131`

**Step 1: Replace handle_event("update_member")**

Replace lines 121-131 with:
```elixir
def handle_event("update_member", %{"index" => idx, "field" => field, "value" => value}, socket) do
  field_atom =
    case field do
      "name" -> :name
      "role" -> :role
      _ -> nil
    end

  if field_atom == nil do
    {:noreply, socket}
  else
    index = String.to_integer(idx)

    members =
      List.update_at(socket.assigns.members, index, fn member ->
        Map.put(member, field_atom, value)
      end)

    {:noreply, assign(socket, members: members)}
  end
end
```

**Step 2: Run tests**

```bash
cd /Users/benjamincates/Dev/agent-sync/relay && mix test test/teamrc_web/live/team_live_test.exs
```

Expected: all tests pass.

**Step 3: Commit**

```bash
git add -A
git commit -m "fix: harden field atom conversion in TeamLive"
```

---

### Task 7: Fix Process.sleep in teams_test.exs

**Files:**
- Modify: `relay/test/teamrc/teams_test.exs:89`

**Step 1: Replace Process.sleep with :sys.get_state**

In `relay/test/teamrc/teams_test.exs`, replace line 89:
```elixir
Process.sleep(50)
```
With:
```elixir
_ = :sys.get_state(pid)
```

**Step 2: Run test**

```bash
cd /Users/benjamincates/Dev/agent-sync/relay && mix test test/teamrc/teams_test.exs
```

Expected: all tests pass.

**Step 3: Commit**

```bash
git add -A
git commit -m "fix: replace Process.sleep with :sys.get_state in teams test"
```

---

### Task 8: Rename CLI types and fix API contract

**Files:**
- Move + Modify: `cli/src/relay-client.ts` -> `cli/src/client.ts` (rename types)
- Modify: `cli/src/index.ts` (import path, fix getTeam call)
- Modify: `cli/src/daemon.ts` (import path)
- Modify: `cli/src/__tests__/daemon.test.ts` (import path)

**Step 1: Move and rename relay-client.ts**

```bash
cd /Users/benjamincates/Dev/agent-sync/cli
mv src/relay-client.ts src/client.ts
```

**Step 2: Rename types in client.ts**

In `cli/src/client.ts`:
- Replace all `RelayTeam` with `teamrcTeam` (lines 3, 57, 77, 82-83, 87, 98)
- Replace `RelayClient` with `TeamrcClient` (line 19)
- Line 77: change `const data = (await res.json()) as { data: teamrcTeam };` to `const data = (await res.json()) as { team: teamrcTeam };`
- Line 78: change `return data.data;` to `return data.team;`

The full updated file should have these type names:
```typescript
export interface teamrcTeam {
  id: string;
  name: string;
  members: Array<{ name: string; role: string; platform: string }>;
  created_at?: string;
}

// ... SyncChange and SyncResult stay the same ...

export class TeamrcClient {
  // ... all method bodies stay the same except createTeam:

  async createTeam(...): Promise<teamrcTeam> {
    // ...
    const data = (await res.json()) as { team: teamrcTeam };
    return data.team;
  }

  async getTeam(token: string): Promise<teamrcTeam> {
    const data = await this.signedGet<{ team: teamrcTeam }>(`/api/teams/${token}`);
    return data.team;
  }

  async joinByInvite(inviteCode: string): Promise<teamrcTeam> {
    // ...
    const data = (await res.json()) as { team: teamrcTeam };
    return data.team;
  }
}
```

**Step 3: Update imports in index.ts**

In `cli/src/index.ts`:
- Line 12: change `import { RelayClient } from "./relay-client.js";` to `import { TeamrcClient } from "./client.js";`
- All occurrences of `new RelayClient(` -> `new TeamrcClient(` (lines 180, 227, 444)
- Line 306 (`diff` command): change `client.getTeam(config.teamId)` to `client.getTeam(config.token)`
- Line 446 (`status` command): change `client.getTeam(config.teamId)` to `client.getTeam(config.token)`

**Step 4: Update imports in daemon.ts**

In `cli/src/daemon.ts`:
- Line 5: change `import type { RelayClient, SyncChange } from "./relay-client.js";` to `import type { TeamrcClient, SyncChange } from "./client.js";`
- Line 13 and everywhere `RelayClient` is used as a type: change to `TeamrcClient`

The `DaemonOptions` interface (line 12) becomes:
```typescript
export interface DaemonOptions {
  adapter: PlatformAdapter;
  client: TeamrcClient;
  platform: string;
  pollInterval?: number;
}
```

**Step 5: Update imports in daemon.test.ts**

In `cli/src/__tests__/daemon.test.ts`:
- Line 8: change `import type { RelayClient } from "../relay-client.js";` to `import type { TeamrcClient } from "../client.js";`
- Line 52: change `}): RelayClient & { calls: ... }` to `}): TeamrcClient & { calls: ... }`
- Line 68: change `} as unknown as ReturnType<typeof createMockClient>;` — this stays the same since it's cast

**Step 6: Run CLI tests**

```bash
cd /Users/benjamincates/Dev/agent-sync/cli && npm test
```

Expected: all tests pass.

**Step 7: Commit**

```bash
git add -A
git commit -m "refactor: rename RelayClient/RelayTeam to TeamrcClient/teamrcTeam"
```

---

### Task 9: Fix agent description text in CLI

**Files:**
- Modify: `cli/src/adapters/claude-code.ts:381`

**Step 1: Fix description template**

In `cli/src/adapters/claude-code.ts`, line 381 (inside `buildAgentFile`), change:
```typescript
description: "${member.role} on the ${teamName} team. Use proactively when tasks relate to ${member.role.toLowerCase()}."
```
To:
```typescript
description: "${member.role} on the ${teamName} team. Use when tasks relate to ${member.role.toLowerCase()}."
```

The exact line in the template string is:
```typescript
description: "${member.role} on the ${teamName} team. Use when tasks relate to ${member.role.toLowerCase()}."
```

**Step 2: Commit**

```bash
git add -A
git commit -m "fix: align agent description text with existing generated agents"
```

---

### Task 10: Final verification

**Step 1: Run full Elixir test suite**

```bash
cd /Users/benjamincates/Dev/agent-sync/relay && mix test
```

Expected: all tests pass.

**Step 2: Run Elixir precommit**

```bash
cd /Users/benjamincates/Dev/agent-sync/relay && mix precommit
```

Expected: compiles with no warnings, formats cleanly, all tests pass.

**Step 3: Run CLI tests**

```bash
cd /Users/benjamincates/Dev/agent-sync/cli && npm test
```

Expected: all tests pass.

**Step 4: Commit any formatting changes**

```bash
git add -A
git commit -m "chore: formatting pass after refactor"
```
