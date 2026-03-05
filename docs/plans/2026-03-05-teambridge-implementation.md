# TeamBridge v1 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build TeamBridge v1 — a stateless Elixir relay with Phoenix LiveView web UI for team definition, plus a Node.js CLI for platform sync.

**Architecture:** Two packages: (1) an Elixir/Phoenix app serving the relay API, MCP endpoint, and LiveView web UI for team configuration; (2) a Node.js CLI (`npx teambridge`) for init/join/sync/push on each machine. The relay holds state in-memory only (ETS/GenServer). The CLI handles all local filesystem operations.

**Tech Stack:**
- Relay: Elixir 1.18+, Phoenix 1.8, LiveView, no database (`--no-ecto`)
- CLI: Node.js 20+, TypeScript, Commander.js
- Auth: Ed25519 via Erlang `:crypto` (relay) and `@noble/ed25519` (CLI)
- Mono-repo: `relay/` (Elixir) + `cli/` (Node.js)

---

## Repo Structure

```
teambridge/
  relay/                    # Elixir Phoenix app
    lib/
      teambridge/
        teams.ex            # GenServer — in-memory team state
        auth.ex             # Ed25519 signature verification
        sync.ex             # Sync logic — diff, merge, conflict detect
        adapters/
          canonical.ex      # Canonical team format (internal)
      teambridge_web/
        router.ex
        controllers/
          api_controller.ex # REST API for CLI sync/push/pull
        live/
          team_live.ex      # LiveView — define/edit teams in browser
          team_form.ex      # LiveView component — team member form
        channels/           # (future: WebSocket push)
    config/
    test/
  cli/                      # Node.js CLI
    src/
      index.ts              # CLI entry point (Commander.js)
      commands/
        init.ts             # Detect platform, gen keypair, register
        join.ts             # Join existing team, scaffold locally
        sync.ts             # Bidirectional sync
        push.ts             # Push memory changes
        status.ts           # Show sync state
      adapters/
        base.ts             # Adapter interface
        claude-code.ts      # Claude Code file locations + formats
        openclaw.ts         # OpenClaw file locations + formats
      auth.ts               # Ed25519 keypair gen + request signing
      relay-client.ts       # HTTP client for relay API
      config.ts             # ~/.teambridge/ config management
    package.json
    tsconfig.json
    test/
  docs/
    plans/
```

---

## Task 1: Scaffold the Mono-Repo

**Files:**
- Create: `README.md`
- Create: `.gitignore`

**Step 1: Initialize git repo**

```bash
cd /Users/benjamincates/Dev/agent-sync
git init
```

**Step 2: Create .gitignore**

```gitignore
# Elixir
relay/_build/
relay/deps/
relay/.elixir_ls/
relay/priv/static/assets/

# Node
cli/node_modules/
cli/dist/

# TeamBridge
.teambridge/

# OS
.DS_Store
```

**Step 3: Create README.md**

```markdown
# TeamBridge

Stateless relay that keeps multi-agent teams in sync across platforms.

- **CLI:** `npx teambridge init` / `join` / `sync`
- **Relay:** Elixir/Phoenix — in-memory only, no database
- **Platforms:** Claude Code, OpenClaw, Claude Desktop
```

**Step 4: Commit**

```bash
git add .gitignore README.md docs/
git commit -m "feat: initial repo with PRD and implementation plan"
```

---

## Task 2: Scaffold the Phoenix Relay App

**Files:**
- Create: `relay/` (entire Phoenix project)

**Step 1: Generate Phoenix app**

```bash
cd /Users/benjamincates/Dev/agent-sync
mix phx.new relay --no-ecto --no-mailer --no-dashboard
cd relay
mix deps.get
```

Note: `--no-ecto` means no database. `--no-mailer` and `--no-dashboard` strip unnecessary deps.

**Step 2: Verify it runs**

```bash
cd /Users/benjamincates/Dev/agent-sync/relay
mix phx.server
```

Expected: Server starts on http://localhost:4000, shows default Phoenix page.

**Step 3: Commit**

```bash
cd /Users/benjamincates/Dev/agent-sync
git add relay/
git commit -m "feat: scaffold Phoenix relay app (no-ecto)"
```

---

## Task 3: In-Memory Team State (GenServer)

**Files:**
- Create: `relay/lib/teambridge/teams.ex`
- Create: `relay/test/teambridge/teams_test.exs`

The Teams GenServer holds all team data in memory. No persistence. If it restarts, clients resync.

**Step 1: Write the failing test**

```elixir
# relay/test/teambridge/teams_test.exs
defmodule Teambridge.TeamsTest do
  use ExUnit.Case, async: true

  alias Teambridge.Teams

  setup do
    {:ok, pid} = Teams.start_link(name: :"test_#{System.unique_integer()}")
    %{pid: pid}
  end

  test "create and get a team", %{pid: pid} do
    team = %{
      "name" => "my-project",
      "members" => [
        %{"name" => "architect", "role" => "System design and API contracts"},
        %{"name" => "implementer", "role" => "Write clean, tested code"}
      ]
    }

    assert :ok = Teams.put_team(pid, "tb_ak_test123", team)
    assert {:ok, ^team} = Teams.get_team(pid, "tb_ak_test123")
  end

  test "get nonexistent team returns error", %{pid: pid} do
    assert :error = Teams.get_team(pid, "tb_ak_nonexistent")
  end

  test "put buffer entry and pull it", %{pid: pid} do
    entry = %{
      "type" => "memory",
      "content" => "Fixed auth bug, root cause was JWT rotation",
      "source_platform" => "claude-code",
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601()
    }

    Teams.put_team(pid, "tb_ak_test123", %{"name" => "test", "members" => []})
    assert :ok = Teams.push_buffer(pid, "tb_ak_test123", entry)
    assert {:ok, [^entry]} = Teams.pull_buffer(pid, "tb_ak_test123", "openclaw")
    # Second pull returns empty — already consumed
    assert {:ok, []} = Teams.pull_buffer(pid, "tb_ak_test123", "openclaw")
  end

  test "put hashes and detect changes", %{pid: pid} do
    Teams.put_team(pid, "tb_ak_test123", %{"name" => "test", "members" => []})

    hashes_a = %{"memory.md" => "abc123", "team.json" => "def456"}
    Teams.put_hashes(pid, "tb_ak_test123", "claude-code", hashes_a)

    hashes_b = %{"memory.md" => "abc123", "team.json" => "xyz789"}
    Teams.put_hashes(pid, "tb_ak_test123", "openclaw", hashes_b)

    # claude-code asks: what changed on other platforms?
    {:ok, changes} = Teams.get_changes(pid, "tb_ak_test123", "claude-code")
    assert changes["team.json"] == :changed
    assert changes["memory.md"] == nil  # same hash, no change
  end
end
```

**Step 2: Run test to verify it fails**

```bash
cd /Users/benjamincates/Dev/agent-sync/relay
mix test test/teambridge/teams_test.exs
```

Expected: FAIL — module `Teambridge.Teams` not found.

**Step 3: Write minimal implementation**

```elixir
# relay/lib/teambridge/teams.ex
defmodule Teambridge.Teams do
  use GenServer

  # State shape:
  # %{
  #   teams: %{token => team_data},
  #   hashes: %{token => %{platform => %{file => hash}}},
  #   buffer: %{token => [%{entry | delivered_to: MapSet}]}
  # }

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  def put_team(pid \\ __MODULE__, token, team) do
    GenServer.call(pid, {:put_team, token, team})
  end

  def get_team(pid \\ __MODULE__, token) do
    GenServer.call(pid, {:get_team, token})
  end

  def push_buffer(pid \\ __MODULE__, token, entry) do
    GenServer.call(pid, {:push_buffer, token, entry})
  end

  def pull_buffer(pid \\ __MODULE__, token, platform) do
    GenServer.call(pid, {:pull_buffer, token, platform})
  end

  def put_hashes(pid \\ __MODULE__, token, platform, hashes) do
    GenServer.call(pid, {:put_hashes, token, platform, hashes})
  end

  def get_changes(pid \\ __MODULE__, token, requesting_platform) do
    GenServer.call(pid, {:get_changes, token, requesting_platform})
  end

  # --- Callbacks ---

  @impl true
  def init(_) do
    {:ok, %{teams: %{}, hashes: %{}, buffer: %{}}}
  end

  @impl true
  def handle_call({:put_team, token, team}, _from, state) do
    state = put_in(state, [:teams, token], team)
    {:reply, :ok, state}
  end

  def handle_call({:get_team, token}, _from, state) do
    case Map.get(state.teams, token) do
      nil -> {:reply, :error, state}
      team -> {:reply, {:ok, team}, state}
    end
  end

  def handle_call({:push_buffer, token, entry}, _from, state) do
    entry = Map.put(entry, "delivered_to", MapSet.new())
    entries = Map.get(state.buffer, token, [])
    state = put_in(state, [:buffer, token], entries ++ [entry])
    {:reply, :ok, state}
  end

  def handle_call({:pull_buffer, token, platform}, _from, state) do
    entries = Map.get(state.buffer, token, [])

    {to_deliver, _rest} =
      Enum.split_with(entries, fn e ->
        not MapSet.member?(e["delivered_to"], platform) and
          e["source_platform"] != platform
      end)

    clean_entries = Enum.map(to_deliver, &Map.delete(&1, "delivered_to"))

    updated_buffer =
      Enum.map(entries, fn e ->
        if e in to_deliver do
          Map.update!(e, "delivered_to", &MapSet.put(&1, platform))
        else
          e
        end
      end)

    state = put_in(state, [:buffer, token], updated_buffer)
    {:reply, {:ok, clean_entries}, state}
  end

  def handle_call({:put_hashes, token, platform, hashes}, _from, state) do
    state = put_in(state, [:hashes, Access.key(token, %{}), platform], hashes)
    {:reply, :ok, state}
  end

  def handle_call({:get_changes, token, requesting_platform}, _from, state) do
    all_hashes = Map.get(state.hashes, token, %{})
    my_hashes = Map.get(all_hashes, requesting_platform, %{})

    other_hashes =
      all_hashes
      |> Map.delete(requesting_platform)
      |> Map.values()

    changes =
      other_hashes
      |> Enum.flat_map(&Map.to_list/1)
      |> Enum.reduce(%{}, fn {file, hash}, acc ->
        my_hash = Map.get(my_hashes, file)

        cond do
          my_hash == nil -> Map.put(acc, file, :new)
          my_hash != hash -> Map.put(acc, file, :changed)
          true -> acc
        end
      end)

    {:reply, {:ok, changes}, state}
  end
end
```

**Step 4: Run test to verify it passes**

```bash
cd /Users/benjamincates/Dev/agent-sync/relay
mix test test/teambridge/teams_test.exs
```

Expected: All tests pass.

**Step 5: Add Teams to application supervision tree**

Edit `relay/lib/teambridge/application.ex`, add `Teambridge.Teams` to the children list:

```elixir
children = [
  TeambridgeWeb.Telemetry,
  {Teambridge.Teams, name: Teambridge.Teams},
  # ... existing children
  TeambridgeWeb.Endpoint
]
```

**Step 6: Commit**

```bash
git add relay/lib/teambridge/teams.ex relay/test/teambridge/teams_test.exs relay/lib/teambridge/application.ex
git commit -m "feat: in-memory team state GenServer with buffer and hash tracking"
```

---

## Task 4: Auth Module (Ed25519 Verification)

**Files:**
- Create: `relay/lib/teambridge/auth.ex`
- Create: `relay/test/teambridge/auth_test.exs`

**Step 1: Write the failing test**

```elixir
# relay/test/teambridge/auth_test.exs
defmodule Teambridge.AuthTest do
  use ExUnit.Case, async: true

  alias Teambridge.Auth

  test "verify valid signature" do
    {pub, priv} = :crypto.generate_key(:eddsa, :ed25519)
    message = "test message"
    signature = :crypto.sign(:eddsa, :none, message, [priv, :ed25519])

    assert Auth.verify(pub, message, signature) == true
  end

  test "reject invalid signature" do
    {pub, _priv} = :crypto.generate_key(:eddsa, :ed25519)
    message = "test message"
    bad_sig = <<0::256>>

    assert Auth.verify(pub, message, bad_sig) == false
  end

  test "derive token from public key" do
    {pub, _priv} = :crypto.generate_key(:eddsa, :ed25519)
    token = Auth.to_token(pub)

    assert String.starts_with?(token, "tb_ak_")
    assert Auth.from_token(token) == {:ok, pub}
  end
end
```

**Step 2: Run test to verify it fails**

```bash
cd /Users/benjamincates/Dev/agent-sync/relay
mix test test/teambridge/auth_test.exs
```

**Step 3: Write minimal implementation**

```elixir
# relay/lib/teambridge/auth.ex
defmodule Teambridge.Auth do
  def verify(public_key, message, signature) do
    :crypto.verify(:eddsa, :none, message, signature, [public_key, :ed25519])
  rescue
    _ -> false
  end

  def to_token(public_key) do
    "tb_ak_" <> Base.url_encode64(public_key, padding: false)
  end

  def from_token("tb_ak_" <> encoded) do
    case Base.url_decode64(encoded, padding: false) do
      {:ok, key} -> {:ok, key}
      :error -> {:error, :invalid_token}
    end
  end

  def from_token(_), do: {:error, :invalid_token}
end
```

**Step 4: Run tests, verify pass**

```bash
cd /Users/benjamincates/Dev/agent-sync/relay
mix test test/teambridge/auth_test.exs
```

**Step 5: Commit**

```bash
git add relay/lib/teambridge/auth.ex relay/test/teambridge/auth_test.exs
git commit -m "feat: Ed25519 auth module with token encoding"
```

---

## Task 5: REST API for CLI Sync

**Files:**
- Create: `relay/lib/teambridge_web/controllers/api_controller.ex`
- Modify: `relay/lib/teambridge_web/router.ex`
- Create: `relay/test/teambridge_web/controllers/api_controller_test.exs`

**Step 1: Write the failing test**

```elixir
# relay/test/teambridge_web/controllers/api_controller_test.exs
defmodule TeambridgeWeb.ApiControllerTest do
  use TeambridgeWeb.ConnCase

  setup do
    {pub, priv} = :crypto.generate_key(:eddsa, :ed25519)
    token = Teambridge.Auth.to_token(pub)
    %{pub: pub, priv: priv, token: token}
  end

  defp sign_request(conn, priv, body_string) do
    signature = :crypto.sign(:eddsa, :none, body_string, [priv, :ed25519])
    put_req_header(conn, "x-tb-signature", Base.url_encode64(signature, padding: false))
  end

  describe "POST /api/teams" do
    test "creates a team", %{conn: conn, priv: priv, token: token} do
      body = Jason.encode!(%{
        "token" => token,
        "team" => %{
          "name" => "my-project",
          "members" => [
            %{"name" => "architect", "role" => "System design"}
          ]
        }
      })

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> sign_request(priv, body)
        |> post("/api/teams", body)

      assert json_response(conn, 200)["ok"] == true
    end
  end

  describe "GET /api/teams/:token" do
    test "returns a team", %{conn: conn, priv: priv, token: token} do
      team = %{"name" => "my-project", "members" => []}
      Teambridge.Teams.put_team(token, team)

      message = "GET /api/teams/#{token}"
      signature = :crypto.sign(:eddsa, :none, message, [priv, :ed25519])

      conn =
        conn
        |> put_req_header("x-tb-signature", Base.url_encode64(signature, padding: false))
        |> get("/api/teams/#{token}")

      assert json_response(conn, 200)["team"]["name"] == "my-project"
    end

    test "returns 404 for unknown team", %{conn: conn, priv: priv} do
      token = "tb_ak_nonexistent"
      message = "GET /api/teams/#{token}"
      signature = :crypto.sign(:eddsa, :none, message, [priv, :ed25519])

      conn =
        conn
        |> put_req_header("x-tb-signature", Base.url_encode64(signature, padding: false))
        |> get("/api/teams/#{token}")

      assert json_response(conn, 404)
    end
  end

  describe "POST /api/sync" do
    test "returns changes from other platforms", %{conn: conn, priv: priv, token: token} do
      Teambridge.Teams.put_team(token, %{"name" => "test", "members" => []})
      Teambridge.Teams.put_hashes(token, "openclaw", %{"memory.md" => "hash1"})

      body = Jason.encode!(%{
        "token" => token,
        "platform" => "claude-code",
        "hashes" => %{"memory.md" => "different_hash"}
      })

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> sign_request(priv, body)
        |> post("/api/sync", body)

      resp = json_response(conn, 200)
      assert resp["changes"]["memory.md"] == "changed"
    end
  end

  describe "POST /api/push" do
    test "buffers a memory entry", %{conn: conn, priv: priv, token: token} do
      Teambridge.Teams.put_team(token, %{"name" => "test", "members" => []})

      body = Jason.encode!(%{
        "token" => token,
        "platform" => "claude-code",
        "entry" => %{
          "type" => "memory",
          "content" => "Agent learned something"
        }
      })

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> sign_request(priv, body)
        |> post("/api/push", body)

      assert json_response(conn, 200)["ok"] == true
    end
  end

  describe "POST /api/pull" do
    test "returns buffered entries for platform", %{conn: conn, priv: priv, token: token} do
      Teambridge.Teams.put_team(token, %{"name" => "test", "members" => []})

      entry = %{
        "type" => "memory",
        "content" => "Agent learned something",
        "source_platform" => "claude-code"
      }
      Teambridge.Teams.push_buffer(token, entry)

      body = Jason.encode!(%{
        "token" => token,
        "platform" => "openclaw"
      })

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> sign_request(priv, body)
        |> post("/api/pull", body)

      resp = json_response(conn, 200)
      assert length(resp["entries"]) == 1
      assert hd(resp["entries"])["content"] == "Agent learned something"
    end
  end
end
```

**Step 2: Run test to verify it fails**

```bash
cd /Users/benjamincates/Dev/agent-sync/relay
mix test test/teambridge_web/controllers/api_controller_test.exs
```

**Step 3: Add routes**

Add to `relay/lib/teambridge_web/router.ex` inside the existing router:

```elixir
  scope "/api", TeambridgeWeb do
    pipe_through :api

    post "/teams", ApiController, :create_team
    get "/teams/:token", ApiController, :get_team
    post "/sync", ApiController, :sync
    post "/push", ApiController, :push
    post "/pull", ApiController, :pull
  end
```

**Step 4: Write controller**

```elixir
# relay/lib/teambridge_web/controllers/api_controller.ex
defmodule TeambridgeWeb.ApiController do
  use TeambridgeWeb, :controller

  alias Teambridge.Teams

  def create_team(conn, %{"token" => token, "team" => team}) do
    :ok = Teams.put_team(token, team)
    json(conn, %{"ok" => true, "token" => token})
  end

  def get_team(conn, %{"token" => token}) do
    case Teams.get_team(token) do
      {:ok, team} -> json(conn, %{"team" => team})
      :error -> conn |> put_status(404) |> json(%{"error" => "team not found"})
    end
  end

  def sync(conn, %{"token" => token, "platform" => platform, "hashes" => hashes}) do
    Teams.put_hashes(token, platform, hashes)
    {:ok, changes} = Teams.get_changes(token, platform)
    {:ok, buffered} = Teams.pull_buffer(token, platform)

    json(conn, %{
      "changes" => Enum.into(changes, %{}, fn {k, v} -> {k, Atom.to_string(v)} end),
      "buffered" => buffered
    })
  end

  def push(conn, %{"token" => token, "platform" => platform, "entry" => entry}) do
    entry = Map.put(entry, "source_platform", platform)
    :ok = Teams.push_buffer(token, entry)
    json(conn, %{"ok" => true})
  end

  def pull(conn, %{"token" => token, "platform" => platform}) do
    {:ok, entries} = Teams.pull_buffer(token, platform)
    json(conn, %{"entries" => entries})
  end
end
```

**Step 5: Run tests, verify pass**

```bash
cd /Users/benjamincates/Dev/agent-sync/relay
mix test test/teambridge_web/controllers/api_controller_test.exs
```

**Step 6: Commit**

```bash
git add relay/lib/teambridge_web/controllers/ relay/lib/teambridge_web/router.ex relay/test/teambridge_web/controllers/
git commit -m "feat: REST API for team CRUD, sync, push, pull"
```

---

## Task 6: Phoenix LiveView — Team Definition UI

**Files:**
- Create: `relay/lib/teambridge_web/live/team_live.ex`
- Modify: `relay/lib/teambridge_web/router.ex`

This is the web UI for users who don't have a team on any platform yet. They define their team here and get an `npx teambridge join <token>` command to run on each machine.

**Step 1: Add LiveView route**

Add to `relay/lib/teambridge_web/router.ex` inside the existing browser scope:

```elixir
  scope "/", TeambridgeWeb do
    pipe_through :browser

    live "/", TeamLive, :index
  end
```

Remove or replace the existing `get "/", PageController, :home` route.

**Step 2: Build the LiveView**

```elixir
# relay/lib/teambridge_web/live/team_live.ex
defmodule TeambridgeWeb.TeamLive do
  use TeambridgeWeb, :live_view

  alias Teambridge.{Teams, Auth}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       team_name: "",
       members: [%{name: "", role: ""}],
       token: nil,
       step: :define
     )}
  end

  @impl true
  def handle_event("update_team_name", %{"value" => name}, socket) do
    {:noreply, assign(socket, team_name: name)}
  end

  def handle_event("update_member", %{"index" => idx, "field" => field, "value" => value}, socket) do
    idx = String.to_integer(idx)

    members =
      socket.assigns.members
      |> List.update_at(idx, &Map.put(&1, String.to_existing_atom(field), value))

    {:noreply, assign(socket, members: members)}
  end

  def handle_event("add_member", _, socket) do
    members = socket.assigns.members ++ [%{name: "", role: ""}]
    {:noreply, assign(socket, members: members)}
  end

  def handle_event("remove_member", %{"index" => idx}, socket) do
    idx = String.to_integer(idx)
    members = List.delete_at(socket.assigns.members, idx)
    members = if members == [], do: [%{name: "", role: ""}], else: members
    {:noreply, assign(socket, members: members)}
  end

  def handle_event("create_team", _, socket) do
    {pub, _priv} = :crypto.generate_key(:eddsa, :ed25519)
    token = Auth.to_token(pub)

    team = %{
      "name" => socket.assigns.team_name,
      "members" =>
        socket.assigns.members
        |> Enum.filter(fn m -> m.name != "" end)
        |> Enum.map(fn m -> %{"name" => m.name, "role" => m.role} end)
    }

    Teams.put_team(token, team)

    {:noreply, assign(socket, token: token, step: :created)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto py-12 px-4">
      <h1 class="text-3xl font-bold mb-2">TeamBridge</h1>
      <p class="text-zinc-500 mb-8">Define your agent team, then sync it to any platform.</p>

      <%= if @step == :define do %>
        <div class="space-y-6">
          <div>
            <label class="block text-sm font-medium mb-1">Team Name</label>
            <input
              type="text"
              value={@team_name}
              phx-keyup="update_team_name"
              placeholder="my-project"
              class="w-full border border-zinc-300 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500"
            />
          </div>

          <div>
            <label class="block text-sm font-medium mb-3">Team Members</label>
            <div class="space-y-3">
              <%= for {member, idx} <- Enum.with_index(@members) do %>
                <div class="flex gap-2 items-start">
                  <input
                    type="text"
                    value={member.name}
                    phx-keyup="update_member"
                    phx-value-index={idx}
                    phx-value-field="name"
                    placeholder="Agent name (e.g. architect)"
                    class="flex-1 border border-zinc-300 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500"
                  />
                  <input
                    type="text"
                    value={member.role}
                    phx-keyup="update_member"
                    phx-value-index={idx}
                    phx-value-field="role"
                    placeholder="Role description"
                    class="flex-2 border border-zinc-300 rounded-lg px-3 py-2 focus:outline-none focus:ring-2 focus:ring-blue-500"
                  />
                  <button
                    phx-click="remove_member"
                    phx-value-index={idx}
                    class="text-zinc-400 hover:text-red-500 px-2 py-2"
                  >
                    x
                  </button>
                </div>
              <% end %>
            </div>
            <button
              phx-click="add_member"
              class="mt-2 text-sm text-blue-600 hover:text-blue-800"
            >
              + Add member
            </button>
          </div>

          <button
            phx-click="create_team"
            disabled={@team_name == ""}
            class="w-full bg-zinc-900 text-white rounded-lg px-4 py-2.5 font-medium hover:bg-zinc-800 disabled:opacity-50 disabled:cursor-not-allowed"
          >
            Create Team
          </button>
        </div>
      <% end %>

      <%= if @step == :created do %>
        <div class="space-y-6">
          <div class="bg-green-50 border border-green-200 rounded-lg p-4">
            <p class="font-medium text-green-800">Team "<%= @team_name %>" created.</p>
          </div>

          <div>
            <label class="block text-sm font-medium mb-2">
              Run this on each machine to sync:
            </label>
            <div class="bg-zinc-900 text-green-400 rounded-lg p-4 font-mono text-sm">
              npx teambridge join <%= @token %>
            </div>
          </div>

          <div class="text-sm text-zinc-500">
            <p>This command will:</p>
            <ul class="list-disc ml-5 mt-1 space-y-1">
              <li>Detect your platform (Claude Code, OpenClaw, etc.)</li>
              <li>Scaffold all team agents locally</li>
              <li>Set up automatic sync hooks</li>
            </ul>
          </div>

          <button
            phx-click="create_team"
            phx-value-reset="true"
            class="text-sm text-blue-600 hover:text-blue-800"
          >
            Create another team
          </button>
        </div>
      <% end %>
    </div>
    """
  end
end
```

**Step 3: Verify it renders**

```bash
cd /Users/benjamincates/Dev/agent-sync/relay
mix phx.server
```

Visit http://localhost:4000 — should show the team definition form.

**Step 4: Commit**

```bash
git add relay/lib/teambridge_web/live/ relay/lib/teambridge_web/router.ex
git commit -m "feat: LiveView team definition UI with token generation"
```

---

## Task 7: Scaffold the Node.js CLI

**Files:**
- Create: `cli/package.json`
- Create: `cli/tsconfig.json`
- Create: `cli/src/index.ts`
- Create: `cli/src/auth.ts`
- Create: `cli/src/relay-client.ts`
- Create: `cli/src/config.ts`

**Step 1: Initialize Node project**

```bash
cd /Users/benjamincates/Dev/agent-sync
mkdir -p cli/src/commands cli/src/adapters
cd cli
npm init -y
npm install commander @noble/ed25519 @noble/hashes
npm install -D typescript @types/node tsx
```

**Step 2: Create tsconfig.json**

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "Node16",
    "moduleResolution": "Node16",
    "outDir": "./dist",
    "rootDir": "./src",
    "strict": true,
    "esModuleInterop": true,
    "declaration": true
  },
  "include": ["src/**/*"]
}
```

**Step 3: Create package.json bin entry**

Update `cli/package.json` to include:

```json
{
  "name": "teambridge",
  "version": "0.1.0",
  "bin": {
    "teambridge": "./dist/index.js"
  },
  "type": "module",
  "scripts": {
    "build": "tsc",
    "dev": "tsx src/index.ts"
  }
}
```

**Step 4: Create auth module**

```typescript
// cli/src/auth.ts
import * as ed from "@noble/ed25519";
import { sha512 } from "@noble/hashes/sha512";
import * as fs from "fs";
import * as path from "path";
import * as os from "os";

// ed25519 requires sha512
ed.etc.sha512Sync = (...m: Uint8Array[]) => {
  const h = sha512.create();
  m.forEach((msg) => h.update(msg));
  return h.digest();
};

const TB_DIR = path.join(os.homedir(), ".teambridge");
const KEY_PATH = path.join(TB_DIR, "key");

export interface Keypair {
  privateKey: Uint8Array;
  publicKey: Uint8Array;
}

export function generateKeypair(): Keypair {
  const privateKey = ed.utils.randomPrivateKey();
  const publicKey = ed.getPublicKey(privateKey);
  return { privateKey, publicKey };
}

export function saveKeypair(kp: Keypair): void {
  fs.mkdirSync(TB_DIR, { recursive: true });
  fs.writeFileSync(
    KEY_PATH,
    JSON.stringify({
      privateKey: Buffer.from(kp.privateKey).toString("base64url"),
      publicKey: Buffer.from(kp.publicKey).toString("base64url"),
    }),
    { mode: 0o600 }
  );
}

export function loadKeypair(): Keypair | null {
  if (!fs.existsSync(KEY_PATH)) return null;
  const data = JSON.parse(fs.readFileSync(KEY_PATH, "utf-8"));
  return {
    privateKey: new Uint8Array(Buffer.from(data.privateKey, "base64url")),
    publicKey: new Uint8Array(Buffer.from(data.publicKey, "base64url")),
  };
}

export function toToken(publicKey: Uint8Array): string {
  return "tb_ak_" + Buffer.from(publicKey).toString("base64url");
}

export async function signMessage(
  privateKey: Uint8Array,
  message: string
): Promise<string> {
  const sig = ed.sign(new TextEncoder().encode(message), privateKey);
  return Buffer.from(sig).toString("base64url");
}
```

**Step 5: Create relay client**

```typescript
// cli/src/relay-client.ts
import { signMessage } from "./auth.js";

export class RelayClient {
  constructor(
    private baseUrl: string,
    private privateKey: Uint8Array,
    private token: string
  ) {}

  private async request(
    method: string,
    path: string,
    body?: object
  ): Promise<any> {
    const bodyStr = body ? JSON.stringify(body) : "";
    const sigMessage = body ? bodyStr : `${method} ${path}`;
    const signature = await signMessage(this.privateKey, sigMessage);

    const res = await fetch(`${this.baseUrl}${path}`, {
      method,
      headers: {
        "Content-Type": "application/json",
        "x-tb-signature": signature,
      },
      body: body ? bodyStr : undefined,
    });

    if (!res.ok) {
      throw new Error(`Relay error: ${res.status} ${await res.text()}`);
    }

    return res.json();
  }

  async createTeam(team: object): Promise<{ ok: boolean; token: string }> {
    return this.request("POST", "/api/teams", { token: this.token, team });
  }

  async getTeam(): Promise<{ team: any }> {
    return this.request("GET", `/api/teams/${this.token}`);
  }

  async sync(
    platform: string,
    hashes: Record<string, string>
  ): Promise<{ changes: Record<string, string>; buffered: any[] }> {
    return this.request("POST", "/api/sync", {
      token: this.token,
      platform,
      hashes,
    });
  }

  async push(platform: string, entry: object): Promise<{ ok: boolean }> {
    return this.request("POST", "/api/push", {
      token: this.token,
      platform,
      entry,
    });
  }

  async pull(platform: string): Promise<{ entries: any[] }> {
    return this.request("POST", "/api/pull", {
      token: this.token,
      platform,
    });
  }
}
```

**Step 6: Create config module**

```typescript
// cli/src/config.ts
import * as fs from "fs";
import * as path from "path";
import * as os from "os";

const TB_DIR = path.join(os.homedir(), ".teambridge");
const CONFIG_PATH = path.join(TB_DIR, "config.json");

const DEFAULT_RELAY = "http://localhost:4000";

export interface TBConfig {
  relay: string;
  token: string;
  platform: string;
}

export function loadConfig(): TBConfig | null {
  if (!fs.existsSync(CONFIG_PATH)) return null;
  return JSON.parse(fs.readFileSync(CONFIG_PATH, "utf-8"));
}

export function saveConfig(config: TBConfig): void {
  fs.mkdirSync(TB_DIR, { recursive: true });
  fs.writeFileSync(CONFIG_PATH, JSON.stringify(config, null, 2));
}

export function detectPlatform(): string | null {
  const home = os.homedir();

  if (fs.existsSync(path.join(home, ".claude"))) {
    return "claude-code";
  }

  if (fs.existsSync(path.join(home, ".openclaw"))) {
    return "openclaw";
  }

  return null;
}

export function getRelayUrl(): string {
  const config = loadConfig();
  return config?.relay ?? process.env.TEAMBRIDGE_RELAY ?? DEFAULT_RELAY;
}
```

**Step 7: Create CLI entry point**

```typescript
// cli/src/index.ts
#!/usr/bin/env node
import { Command } from "commander";
import {
  generateKeypair,
  saveKeypair,
  loadKeypair,
  toToken,
} from "./auth.js";
import { RelayClient } from "./relay-client.js";
import {
  detectPlatform,
  saveConfig,
  loadConfig,
  getRelayUrl,
} from "./config.js";
import { getAdapter } from "./adapters/base.js";

const program = new Command();

program
  .name("teambridge")
  .description("Sync multi-agent teams across platforms")
  .version("0.1.0");

program
  .command("init")
  .description("Initialize TeamBridge on this machine")
  .option("--relay <url>", "Relay server URL")
  .action(async (opts) => {
    const platform = detectPlatform();
    if (!platform) {
      console.error(
        "Could not detect platform. Ensure Claude Code or OpenClaw is installed."
      );
      process.exit(1);
    }
    console.log(`Detected platform: ${platform}`);

    let kp = loadKeypair();
    if (!kp) {
      kp = generateKeypair();
      saveKeypair(kp);
      console.log("Generated keypair.");
    }

    const token = toToken(kp.publicKey);
    const relay = opts.relay ?? getRelayUrl();

    saveConfig({ relay, token, platform });

    const adapter = getAdapter(platform);
    const existingTeam = adapter.readTeam();

    if (existingTeam) {
      console.log(
        `Found team "${existingTeam.name}" (${existingTeam.members.length} agents)`
      );
      const client = new RelayClient(relay, kp.privateKey, token);
      await client.createTeam(existingTeam);
      console.log("Pushed team to relay.");
    }

    adapter.installHooks(relay, token);
    console.log("Installed sync hooks.");

    console.log(`\nYour team token: ${token}`);
    console.log(`\nTo connect another machine:`);
    console.log(
      `  npx teambridge join ${token}${opts.relay ? ` --relay ${relay}` : ""}`
    );
  });

program
  .command("join <token>")
  .description("Join an existing team")
  .option("--relay <url>", "Relay server URL")
  .action(async (token, opts) => {
    const platform = detectPlatform();
    if (!platform) {
      console.error(
        "Could not detect platform. Ensure Claude Code or OpenClaw is installed."
      );
      process.exit(1);
    }
    console.log(`Detected platform: ${platform}`);

    let kp = loadKeypair();
    if (!kp) {
      kp = generateKeypair();
      saveKeypair(kp);
    }

    const relay = opts.relay ?? getRelayUrl();
    const client = new RelayClient(relay, kp.privateKey, token);

    try {
      const { team } = await client.getTeam();
      console.log(`\nFound team "${team.name}":`);
      for (const member of team.members) {
        console.log(`  - ${member.name}: ${member.role}`);
      }

      saveConfig({ relay, token, platform });

      const adapter = getAdapter(platform);
      adapter.writeTeam(team);
      console.log("\nScaffolded team agents locally.");

      adapter.installHooks(relay, token);
      console.log("Installed sync hooks.");
      console.log("\nDone. Sync is automatic from now on.");
    } catch (e: any) {
      console.error(`Failed to join team: ${e.message}`);
      process.exit(1);
    }
  });

program
  .command("sync")
  .description("Sync team state with relay")
  .action(async () => {
    const config = loadConfig();
    if (!config) {
      console.error("Not initialized. Run: npx teambridge init");
      process.exit(1);
    }

    const kp = loadKeypair();
    if (!kp) {
      console.error("Keypair not found. Run: npx teambridge init");
      process.exit(1);
    }

    const client = new RelayClient(config.relay, kp.privateKey, config.token);
    const adapter = getAdapter(config.platform);
    const hashes = adapter.getHashes();

    console.log(`Syncing ${config.platform} with relay...`);

    try {
      const result = await client.sync(config.platform, hashes);

      if (result.buffered.length > 0) {
        const memoryEntries = result.buffered
          .filter((e: any) => e.type === "memory")
          .map((e: any) => e.content);
        if (memoryEntries.length > 0) {
          adapter.writeMemory(memoryEntries);
          console.log(`Applied ${memoryEntries.length} memory entries.`);
        }
      }

      const changedKeys = Object.keys(result.changes);
      if (changedKeys.length > 0) {
        const { team } = await client.getTeam();
        adapter.writeTeam(team);
        console.log("Updated team definition.");
      }

      if (result.buffered.length === 0 && changedKeys.length === 0) {
        console.log("Already up to date.");
      }
    } catch (e: any) {
      console.error(`Sync failed: ${e.message}`);
      process.exit(1);
    }
  });

program
  .command("push")
  .description("Push local changes to relay")
  .action(async () => {
    const config = loadConfig();
    if (!config) {
      console.error("Not initialized. Run: npx teambridge init");
      process.exit(1);
    }

    const kp = loadKeypair();
    if (!kp) {
      console.error("Keypair not found. Run: npx teambridge init");
      process.exit(1);
    }

    const client = new RelayClient(config.relay, kp.privateKey, config.token);
    const adapter = getAdapter(config.platform);
    const memory = adapter.readMemory();

    if (memory.length > 0) {
      await client.push(config.platform, {
        type: "memory",
        content: memory.join("\n\n---\n\n"),
        timestamp: new Date().toISOString(),
      });
      console.log("Pushed memory to relay.");
    } else {
      console.log("Nothing to push.");
    }
  });

program
  .command("status")
  .description("Show current sync status")
  .action(() => {
    const config = loadConfig();
    if (!config) {
      console.log("Not initialized. Run: npx teambridge init");
      return;
    }
    console.log(`Platform: ${config.platform}`);
    console.log(`Relay:    ${config.relay}`);
    console.log(`Token:    ${config.token}`);
  });

program.parse();
```

**Step 8: Verify it builds and runs**

```bash
cd /Users/benjamincates/Dev/agent-sync/cli
npm run build
node dist/index.js --help
node dist/index.js status
```

Expected: CLI shows help output, status shows "Not initialized."

**Step 9: Commit**

```bash
cd /Users/benjamincates/Dev/agent-sync
git add cli/
git commit -m "feat: Node.js CLI with init, join, sync, push, status commands"
```

---

## Task 8: Claude Code Platform Adapter (CLI)

**Files:**
- Create: `cli/src/adapters/base.ts`
- Create: `cli/src/adapters/claude-code.ts`

**Step 1: Define adapter interface**

```typescript
// cli/src/adapters/base.ts
export interface TeamMember {
  name: string;
  role: string;
}

export interface TeamDefinition {
  name: string;
  members: TeamMember[];
}

export interface PlatformAdapter {
  readTeam(): TeamDefinition | null;
  writeTeam(team: TeamDefinition): void;
  readMemory(): string[];
  writeMemory(entries: string[]): void;
  getHashes(): Record<string, string>;
  installHooks(relay: string, token: string): void;
}

export function getAdapter(platform: string): PlatformAdapter {
  switch (platform) {
    case "claude-code": {
      const { ClaudeCodeAdapter } = require("./claude-code.js");
      return new ClaudeCodeAdapter();
    }
    case "openclaw": {
      const { OpenClawAdapter } = require("./openclaw.js");
      return new OpenClawAdapter();
    }
    default:
      throw new Error(`Unknown platform: ${platform}`);
  }
}
```

**Step 2: Write Claude Code adapter**

```typescript
// cli/src/adapters/claude-code.ts
import * as fs from "fs";
import * as path from "path";
import * as os from "os";
import * as crypto from "crypto";
import { PlatformAdapter, TeamDefinition } from "./base.js";

export class ClaudeCodeAdapter implements PlatformAdapter {
  private claudeDir = path.join(os.homedir(), ".claude");

  readTeam(): TeamDefinition | null {
    const teamsDir = path.join(this.claudeDir, "teams");
    if (!fs.existsSync(teamsDir)) return null;

    const teamDirs = fs.readdirSync(teamsDir).filter((d) =>
      fs.statSync(path.join(teamsDir, d)).isDirectory()
    );
    if (teamDirs.length === 0) return null;

    const teamName = teamDirs[0];
    const configPath = path.join(teamsDir, teamName, "config.json");
    if (!fs.existsSync(configPath)) return null;

    const config = JSON.parse(fs.readFileSync(configPath, "utf-8"));
    return {
      name: teamName,
      members: (config.members || []).map((m: any) => ({
        name: m.name,
        role: m.role || m.description || "",
      })),
    };
  }

  writeTeam(team: TeamDefinition): void {
    const teamDir = path.join(this.claudeDir, "teams", team.name);
    fs.mkdirSync(teamDir, { recursive: true });

    const config = {
      name: team.name,
      members: team.members.map((m) => ({
        name: m.name,
        role: m.role,
      })),
      created_at: new Date().toISOString(),
      source: "teambridge",
    };

    fs.writeFileSync(
      path.join(teamDir, "config.json"),
      JSON.stringify(config, null, 2)
    );

    const claudeMdPath = path.join(process.cwd(), "CLAUDE.md");
    const teamSection = [
      "",
      "## Team (synced by TeamBridge)",
      "",
      ...team.members.map((m) => `- **${m.name}**: ${m.role}`),
      "",
    ].join("\n");

    if (fs.existsSync(claudeMdPath)) {
      let content = fs.readFileSync(claudeMdPath, "utf-8");
      const marker = "## Team (synced by TeamBridge)";
      const markerIdx = content.indexOf(marker);
      if (markerIdx !== -1) {
        const nextSection = content.indexOf("\n## ", markerIdx + 1);
        content =
          content.slice(0, markerIdx) +
          teamSection.trim() +
          "\n" +
          (nextSection !== -1 ? content.slice(nextSection) : "");
      } else {
        content += teamSection;
      }
      fs.writeFileSync(claudeMdPath, content);
    }
  }

  readMemory(): string[] {
    const projectsDir = path.join(this.claudeDir, "projects");
    if (!fs.existsSync(projectsDir)) return [];

    const entries: string[] = [];
    for (const project of fs.readdirSync(projectsDir)) {
      const memDir = path.join(projectsDir, project, "memory");
      if (!fs.existsSync(memDir) || !fs.statSync(memDir).isDirectory())
        continue;

      for (const file of fs.readdirSync(memDir)) {
        if (file.endsWith(".md")) {
          entries.push(fs.readFileSync(path.join(memDir, file), "utf-8"));
        }
      }
    }
    return entries;
  }

  writeMemory(entries: string[]): void {
    const projectsDir = path.join(this.claudeDir, "projects");
    if (!fs.existsSync(projectsDir)) return;

    const projects = fs.readdirSync(projectsDir).filter((d) =>
      fs.statSync(path.join(projectsDir, d)).isDirectory()
    );
    if (projects.length === 0) return;

    const memDir = path.join(projectsDir, projects[0], "memory");
    fs.mkdirSync(memDir, { recursive: true });

    const memPath = path.join(memDir, "teambridge-shared.md");
    const content = entries.join("\n\n---\n\n");
    fs.writeFileSync(memPath, content);
  }

  getHashes(): Record<string, string> {
    const hashes: Record<string, string> = {};

    const teamsDir = path.join(this.claudeDir, "teams");
    if (fs.existsSync(teamsDir)) {
      for (const team of fs.readdirSync(teamsDir)) {
        const configPath = path.join(teamsDir, team, "config.json");
        if (fs.existsSync(configPath)) {
          const content = fs.readFileSync(configPath);
          hashes[`team/${team}/config.json`] = crypto
            .createHash("sha256")
            .update(content)
            .digest("hex")
            .slice(0, 16);
        }
      }
    }

    const memory = this.readMemory();
    if (memory.length > 0) {
      hashes["memory"] = crypto
        .createHash("sha256")
        .update(memory.join("\n"))
        .digest("hex")
        .slice(0, 16);
    }

    return hashes;
  }

  installHooks(relay: string, token: string): void {
    const settingsPath = path.join(this.claudeDir, "settings.json");
    let settings: any = {};

    if (fs.existsSync(settingsPath)) {
      settings = JSON.parse(fs.readFileSync(settingsPath, "utf-8"));
    }

    if (!settings.hooks) settings.hooks = {};
    if (!settings.hooks.SessionStart) settings.hooks.SessionStart = [];

    const hasSyncHook = settings.hooks.SessionStart.some(
      (h: any) => h.command && h.command.includes("teambridge sync")
    );

    if (!hasSyncHook) {
      settings.hooks.SessionStart.push({
        type: "command",
        command: "npx teambridge sync 2>/dev/null || true",
      });
    }

    fs.writeFileSync(settingsPath, JSON.stringify(settings, null, 2));
  }
}
```

**Step 3: Verify build**

```bash
cd /Users/benjamincates/Dev/agent-sync/cli
npm run build
```

**Step 4: Commit**

```bash
cd /Users/benjamincates/Dev/agent-sync
git add cli/src/adapters/
git commit -m "feat: Claude Code platform adapter — read/write team, memory, hooks"
```

---

## Task 9: OpenClaw Platform Adapter (CLI)

**Files:**
- Create: `cli/src/adapters/openclaw.ts`

**Step 1: Write OpenClaw adapter**

```typescript
// cli/src/adapters/openclaw.ts
import * as fs from "fs";
import * as path from "path";
import * as os from "os";
import * as crypto from "crypto";
import { execFileSync } from "child_process";
import { PlatformAdapter, TeamDefinition } from "./base.js";

export class OpenClawAdapter implements PlatformAdapter {
  private openclawDir = path.join(os.homedir(), ".openclaw");
  private workspaceDir = path.join(os.homedir(), ".openclaw", "workspace");

  readTeam(): TeamDefinition | null {
    const agentsDir = path.join(this.openclawDir, "agents");
    if (!fs.existsSync(agentsDir)) return null;

    const agents: { name: string; role: string }[] = [];

    for (const agentId of fs.readdirSync(agentsDir)) {
      if (!fs.statSync(path.join(agentsDir, agentId)).isDirectory()) continue;

      const soulPath = path.join(
        this.workspaceDir,
        "agents",
        agentId,
        "SOUL.md"
      );
      let role = "";
      if (fs.existsSync(soulPath)) {
        role = fs.readFileSync(soulPath, "utf-8").split("\n")[0] || "";
      }

      agents.push({ name: agentId, role });
    }

    if (agents.length === 0) return null;

    return {
      name: "openclaw-team",
      members: agents,
    };
  }

  writeTeam(team: TeamDefinition): void {
    for (const member of team.members) {
      const agentWorkspace = path.join(
        this.workspaceDir,
        "agents",
        member.name
      );
      fs.mkdirSync(agentWorkspace, { recursive: true });

      const soulContent = `${member.role}\n\nYou are the ${member.name} agent. ${member.role}\n`;
      fs.writeFileSync(path.join(agentWorkspace, "SOUL.md"), soulContent);

      const agentsContent = [
        `# ${member.name}`,
        "",
        `Role: ${member.role}`,
        "",
        "## Team Members",
        "",
        ...team.members
          .filter((m) => m.name !== member.name)
          .map((m) => `- **${m.name}**: ${m.role}`),
        "",
        "_Synced by TeamBridge_",
      ].join("\n");
      fs.writeFileSync(path.join(agentWorkspace, "AGENTS.md"), agentsContent);

      // Register agent via CLI (non-interactive, safe from injection via execFileSync)
      try {
        execFileSync("openclaw", [
          "agents",
          "add",
          member.name,
          "--workspace",
          agentWorkspace,
          "--non-interactive",
        ], { stdio: "pipe" });
      } catch {
        // Agent may already exist
      }
    }
  }

  readMemory(): string[] {
    const memPath = path.join(this.workspaceDir, "MEMORY.md");
    if (!fs.existsSync(memPath)) return [];
    return [fs.readFileSync(memPath, "utf-8")];
  }

  writeMemory(entries: string[]): void {
    fs.mkdirSync(this.workspaceDir, { recursive: true });
    const memPath = path.join(this.workspaceDir, "MEMORY.md");
    let existing = "";
    if (fs.existsSync(memPath)) {
      existing = fs.readFileSync(memPath, "utf-8");
    }

    const newContent = entries.join("\n\n");
    if (!existing.includes(newContent)) {
      fs.writeFileSync(
        memPath,
        existing + (existing ? "\n\n---\n\n" : "") + newContent
      );
    }
  }

  getHashes(): Record<string, string> {
    const hashes: Record<string, string> = {};

    const memPath = path.join(this.workspaceDir, "MEMORY.md");
    if (fs.existsSync(memPath)) {
      hashes["memory"] = crypto
        .createHash("sha256")
        .update(fs.readFileSync(memPath))
        .digest("hex")
        .slice(0, 16);
    }

    const agentsDir = path.join(this.workspaceDir, "agents");
    if (fs.existsSync(agentsDir)) {
      for (const agent of fs.readdirSync(agentsDir)) {
        const soulPath = path.join(agentsDir, agent, "SOUL.md");
        if (fs.existsSync(soulPath)) {
          hashes[`agent/${agent}/SOUL.md`] = crypto
            .createHash("sha256")
            .update(fs.readFileSync(soulPath))
            .digest("hex")
            .slice(0, 16);
        }
      }
    }

    return hashes;
  }

  installHooks(relay: string, token: string): void {
    const hooksDir = path.join(this.openclawDir, "hooks", "teambridge-sync");
    fs.mkdirSync(hooksDir, { recursive: true });

    const hookContent = `export default {
  name: 'teambridge-sync',
  events: ['agent:bootstrap'],
  handler: async () => {
    const { execFileSync } = await import('child_process');
    try {
      execFileSync('npx', ['teambridge', 'sync'], { stdio: 'pipe' });
    } catch {}
  }
};
`;

    fs.writeFileSync(path.join(hooksDir, "index.ts"), hookContent);

    try {
      execFileSync("openclaw", ["hooks", "enable", "teambridge-sync"], {
        stdio: "pipe",
      });
    } catch {
      // May not be available
    }
  }
}
```

**Step 2: Build and verify**

```bash
cd /Users/benjamincates/Dev/agent-sync/cli
npm run build
```

**Step 3: Commit**

```bash
cd /Users/benjamincates/Dev/agent-sync
git add cli/src/adapters/openclaw.ts
git commit -m "feat: OpenClaw platform adapter — read/write team, memory, hooks"
```

---

## Task 10: End-to-End Integration Test

**Files:**
- Create: `test/e2e.sh`

A shell script that spins up the relay, creates a team via the API, and verifies sync works.

**Step 1: Write e2e test script**

```bash
#!/bin/bash
# test/e2e.sh — End-to-end test for TeamBridge
set -e

echo "=== TeamBridge E2E Test ==="

# 1. Start relay in background
echo "Starting relay..."
cd relay
mix phx.server &
RELAY_PID=$!
cd ..
sleep 3

cleanup() {
  kill $RELAY_PID 2>/dev/null || true
}
trap cleanup EXIT

RELAY_URL="http://localhost:4000"

# 2. Create team via API
echo "Creating team via API..."
RESPONSE=$(curl -s -X POST "$RELAY_URL/api/teams" \
  -H "Content-Type: application/json" \
  -H "x-tb-signature: test" \
  -d '{
    "token": "tb_ak_testtoken123",
    "team": {
      "name": "test-project",
      "members": [
        {"name": "architect", "role": "System design"},
        {"name": "coder", "role": "Implementation"}
      ]
    }
  }')
echo "Create response: $RESPONSE"

# 3. Get team
echo "Getting team..."
TEAM=$(curl -s "$RELAY_URL/api/teams/tb_ak_testtoken123" \
  -H "x-tb-signature: test")
echo "Team: $TEAM"

# 4. Push a memory entry from claude-code
echo "Pushing memory..."
curl -s -X POST "$RELAY_URL/api/push" \
  -H "Content-Type: application/json" \
  -H "x-tb-signature: test" \
  -d '{
    "token": "tb_ak_testtoken123",
    "platform": "claude-code",
    "entry": {"type": "memory", "content": "Auth bug fixed via JWT rotation"}
  }'

# 5. Pull from openclaw
echo "Pulling from openclaw..."
PULL=$(curl -s -X POST "$RELAY_URL/api/pull" \
  -H "Content-Type: application/json" \
  -H "x-tb-signature: test" \
  -d '{
    "token": "tb_ak_testtoken123",
    "platform": "openclaw"
  }')
echo "Pulled: $PULL"

# 6. Verify memory was delivered
if echo "$PULL" | grep -q "JWT rotation"; then
  echo "PASS: Memory synced across platforms"
else
  echo "FAIL: Memory not found in pull"
  exit 1
fi

# 7. Pull again — should be empty
PULL2=$(curl -s -X POST "$RELAY_URL/api/pull" \
  -H "Content-Type: application/json" \
  -H "x-tb-signature: test" \
  -d '{
    "token": "tb_ak_testtoken123",
    "platform": "openclaw"
  }')

if echo "$PULL2" | grep -q '"entries":\[\]'; then
  echo "PASS: Buffer correctly emptied after delivery"
else
  echo "FAIL: Buffer not emptied"
  exit 1
fi

echo ""
echo "=== All E2E tests passed ==="
```

**Step 2: Run e2e test**

```bash
cd /Users/benjamincates/Dev/agent-sync
chmod +x test/e2e.sh
bash test/e2e.sh
```

**Step 3: Commit**

```bash
git add test/
git commit -m "feat: end-to-end integration test"
```

---

## Task 11: Buffer TTL Cleanup

**Files:**
- Modify: `relay/lib/teambridge/teams.ex`
- Modify: `relay/test/teambridge/teams_test.exs`

**Step 1: Add TTL test**

Add to `relay/test/teambridge/teams_test.exs`:

```elixir
test "expired buffer entries are cleaned up", %{pid: pid} do
  Teams.put_team(pid, "tb_ak_ttl_test", %{"name" => "test", "members" => []})

  old_entry = %{
    "type" => "memory",
    "content" => "old",
    "source_platform" => "claude-code",
    "timestamp" => "2020-01-01T00:00:00Z"
  }
  Teams.push_buffer(pid, "tb_ak_ttl_test", old_entry)

  send(pid, :cleanup)
  :timer.sleep(50)

  {:ok, entries} = Teams.pull_buffer(pid, "tb_ak_ttl_test", "openclaw")
  assert entries == []
end
```

**Step 2: Add cleanup to GenServer**

Add to `relay/lib/teambridge/teams.ex`:

```elixir
# In init/1, add:
schedule_cleanup()

# Add these module attributes:
@buffer_ttl_ms :timer.hours(1)
@cleanup_interval_ms :timer.minutes(5)

# Add handle_info callback:
@impl true
def handle_info(:cleanup, state) do
  now = DateTime.utc_now()
  cutoff = DateTime.add(now, -@buffer_ttl_ms, :millisecond)

  buffer =
    Map.new(state.buffer, fn {token, entries} ->
      filtered = Enum.filter(entries, fn entry ->
        case DateTime.from_iso8601(entry["timestamp"] || "") do
          {:ok, ts, _} -> DateTime.compare(ts, cutoff) == :gt
          _ -> true
        end
      end)
      {token, filtered}
    end)

  schedule_cleanup()
  {:noreply, %{state | buffer: buffer}}
end

defp schedule_cleanup do
  Process.send_after(self(), :cleanup, @cleanup_interval_ms)
end
```

**Step 3: Run tests**

```bash
cd /Users/benjamincates/Dev/agent-sync/relay
mix test test/teambridge/teams_test.exs
```

**Step 4: Commit**

```bash
git add relay/lib/teambridge/teams.ex relay/test/teambridge/teams_test.exs
git commit -m "feat: buffer TTL cleanup with periodic sweep"
```

---

## Summary

| Task | What | Tech | Workstream |
|---|---|---|---|
| 1 | Scaffold mono-repo | Git | Shared |
| 2 | Scaffold Phoenix relay | Elixir, Phoenix 1.8 | Relay |
| 3 | In-memory team state | GenServer | Relay |
| 4 | Ed25519 auth module | Erlang :crypto | Relay |
| 5 | REST API for CLI | Phoenix controllers | Relay |
| 6 | LiveView team definition UI | Phoenix LiveView | Relay |
| 7 | Scaffold Node.js CLI | TypeScript, Commander.js | CLI |
| 8 | Claude Code adapter | Node.js filesystem | CLI |
| 9 | OpenClaw adapter | Node.js filesystem | CLI |
| 10 | E2E integration test | Shell script | Shared |
| 11 | Buffer TTL cleanup | GenServer timer | Relay |

**Parallelization:** After Task 1, the relay (Tasks 2-6, 11) and CLI (Tasks 7-9) workstreams are independent and can run in parallel. Task 10 requires both.
