defmodule Teambridge.Teams do
  use GenServer

  import Ecto.Query
  alias Teambridge.Repo
  alias Teambridge.Schema.{Team, Member, Invite, TokenTeam}

  @content_ttl_ms :timer.hours(24)
  @cleanup_interval_ms :timer.minutes(5)
  @invite_ttl_hours 24

  # --- Client API ---

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  @doc "Store a team under a token (used by authenticated API create)."
  def put_team(pid \\ __MODULE__, token, team_attrs) do
    GenServer.call(pid, {:put_team, token, team_attrs})
  end

  @doc "Create a team with a random invite code. Returns {:ok, invite_code}."
  def create_team_with_invite(pid \\ __MODULE__, team_attrs) do
    GenServer.call(pid, {:create_team_with_invite, team_attrs})
  end

  @doc "Join a team by invite code. Returns {:ok, team_map} or :error."
  def join_by_invite(pid \\ __MODULE__, invite_code, token) do
    GenServer.call(pid, {:join_by_invite, invite_code, token})
  end

  @doc "Get a team by token. Returns {:ok, team_map} or :error."
  def get_team(pid \\ __MODULE__, token) do
    GenServer.call(pid, {:get_team, token})
  end

  @doc """
  Sync files for a platform.

  Accepts: token, platform name, hashes map, and files map (content for changed files).
  Returns: {:ok, %{files: changed_files_from_others}} or :error.

  The relay:
  1. Resolves token → team_id
  2. Stores the platform's hashes
  3. Stores any file content the platform sent
  4. Compares hashes across all platforms
  5. Returns content for any files where other platforms have newer versions
  """
  def sync(token, platform, hashes, files \\ %{}) do
    GenServer.call(__MODULE__, {:sync, token, platform, hashes, files})
  end

  def sync(pid, token, platform, hashes, files) when is_pid(pid) do
    GenServer.call(pid, {:sync, token, platform, hashes, files})
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

  @doc "Check if a team has changes since a given Unix timestamp. Returns {:ok, boolean}."
  def check_changed(pid \\ __MODULE__, token, since) do
    GenServer.call(pid, {:check_changed, token, since})
  end

  # --- GenServer Callbacks ---

  @impl true
  def init(_opts) do
    schedule_cleanup()

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

  def handle_call({:create_team_with_invite, team_attrs}, _from, state) do
    team_data = normalize_team(team_attrs)
    invite_code = generate_invite_code()
    expires_at = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(@invite_ttl_hours * 3600)

    case create_team_in_db(team_data) do
      {:ok, team} ->
        %Invite{}
        |> Invite.changeset(%{code: invite_code, expires_at: expires_at, team_id: team.id})
        |> Repo.insert!()

        {:reply, {:ok, invite_code}, state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

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
        invite
        |> Invite.changeset(%{claimed_at: now, claimed_by_token: token})
        |> Repo.update()

        upsert_token_team(token, team.id)
        state = put_in(state, [:token_teams, token], team.id)

        {:reply, {:ok, team_to_map(team)}, state}
    end
  end

  def handle_call({:get_team, token}, _from, state) do
    case Map.get(state.token_teams, token) do
      nil ->
        {:reply, :error, state}

      team_id ->
        team = Repo.get(Team, team_id) |> Repo.preload(:members)

        if team do
          {:reply, {:ok, team_to_map(team)}, state}
        else
          {:reply, :error, state}
        end
    end
  end

  def handle_call({:sync, token, platform, incoming_hashes, incoming_files}, _from, state) do
    case Map.get(state.token_teams, token) do
      nil ->
        {:reply, {:error, :not_joined}, state}

      team_id ->
        {result, state} = do_sync(state, team_id, platform, incoming_hashes, incoming_files)
        {:reply, {:ok, result}, state}
    end
  end

  # Legacy support for tests — push_buffer, pull_buffer, put_hashes, get_changes
  def handle_call({:push_buffer, token, entry}, _from, state) do
    case Map.get(state.token_teams, token) do
      nil -> {:reply, {:error, :not_joined}, state}
      team_id -> do_push_buffer(state, team_id, entry)
    end
  end

  def handle_call({:pull_buffer, token, platform}, _from, state) do
    case Map.get(state.token_teams, token) do
      nil -> {:reply, {:error, :not_joined}, state}
      team_id ->
        team_content = Map.get(state.content, team_id, %{})

        entries =
          team_content
          |> Enum.reject(fn {_file, meta} -> meta.source == platform end)
          |> Enum.map(fn {file, meta} ->
            %{"type" => file, "content" => meta.content, "source_platform" => meta.source, "timestamp" => meta.timestamp}
          end)

        {:reply, {:ok, entries}, state}
    end
  end

  def handle_call({:put_hashes, token, platform, hashes}, _from, state) do
    case Map.get(state.token_teams, token) do
      nil -> {:reply, {:error, :not_joined}, state}
      team_id ->
        team_hashes = Map.get(state.hashes, team_id, %{})
        team_hashes = Map.put(team_hashes, platform, hashes)
        state = put_in(state, [:hashes, team_id], team_hashes)
        {:reply, :ok, state}
    end
  end

  def handle_call({:get_changes, token, requesting_platform}, _from, state) do
    case Map.get(state.token_teams, token) do
      nil -> {:reply, {:error, :not_joined}, state}
      team_id ->
        team_hashes = Map.get(state.hashes, team_id, %{})
        changes = Map.drop(team_hashes, [requesting_platform])
        {:reply, {:ok, changes}, state}
    end
  end

  def handle_call({:check_changed, token, since}, _from, state) do
    case Map.get(state.token_teams, token) do
      nil -> {:reply, {:error, :not_joined}, state}
      team_id ->
        last = Map.get(state.last_updated_at, team_id, 0)
        {:reply, {:ok, last > since}, state}
    end
  end

  defp do_push_buffer(state, team_id, entry) do
    source = Map.get(entry, "source_platform") || Map.get(entry, :source_platform) || "unknown"
    file_key = Map.get(entry, "type") || Map.get(entry, :type) || "buffer"
    content_val = Map.get(entry, "content") || Map.get(entry, :content) || ""

    team_content = Map.get(state.content, team_id, %{})
    team_content = Map.put(team_content, file_key, %{
      content: content_val,
      source: source,
      timestamp: DateTime.to_iso8601(DateTime.utc_now())
    })
    state = put_in(state, [:content, team_id], team_content)
    state = put_in(state, [:last_updated_at, team_id], System.system_time(:second))

    {:reply, :ok, state}
  end

  @impl true
  def handle_cast({:token_revoked, token}, state) do
    {:noreply, update_in(state.token_teams, &Map.delete(&1, token))}
  end

  @impl true
  def handle_info(:cleanup, state) do
    now = DateTime.utc_now()

    cleaned_content =
      Map.new(state.content, fn {team_id, files} ->
        filtered =
          Map.new(
            Enum.filter(files, fn {_file, meta} ->
              case DateTime.from_iso8601(meta.timestamp) do
                {:ok, ts, _offset} ->
                  DateTime.diff(now, ts, :millisecond) < @content_ttl_ms

                _ ->
                  true
              end
            end)
          )

        {team_id, filtered}
      end)

    schedule_cleanup()
    {:noreply, %{state | content: cleaned_content}}
  end

  # --- Private: Sync Logic ---

  defp do_sync(state, team_id, platform, incoming_hashes, incoming_files) do
    # 1. Store this platform's hashes
    team_hashes = Map.get(state.hashes, team_id, %{})
    team_hashes = Map.put(team_hashes, platform, incoming_hashes)
    state = put_in(state, [:hashes, team_id], team_hashes)

    # 2. Store any content this platform is pushing
    now = DateTime.to_iso8601(DateTime.utc_now())
    team_content = Map.get(state.content, team_id, %{})

    team_content =
      Enum.reduce(incoming_files, team_content, fn {file, content}, acc ->
        Map.put(acc, file, %{content: content, source: platform, timestamp: now})
      end)

    state = put_in(state, [:content, team_id], team_content)

    # 2b. Update last_updated_at if content was pushed
    state =
      if map_size(incoming_files) > 0 or map_size(incoming_hashes) > 0 do
        put_in(state, [:last_updated_at, team_id], System.system_time(:second))
      else
        state
      end

    # 3. Find files where other platforms have different hashes
    other_platforms = Map.drop(team_hashes, [platform])

    changed_files =
      Enum.reduce(other_platforms, %{}, fn {_other_platform, other_hashes}, acc ->
        Enum.reduce(other_hashes, acc, fn {file, hash}, acc2 ->
          my_hash = Map.get(incoming_hashes, file)

          if my_hash != hash do
            # Check if we have the content stored
            case Map.get(team_content, file) do
              %{content: content, timestamp: ts} ->
                updated_at =
                  case DateTime.from_iso8601(ts) do
                    {:ok, dt, _} -> DateTime.to_unix(dt)
                    _ -> 0
                  end

                Map.put(acc2, file, %{content: content, updated_at: updated_at})

              nil ->
                acc2
            end
          else
            acc2
          end
        end)
      end)

    {%{files: changed_files}, state}
  end

  # --- Private helpers ---

  defp upsert_token_team(token, team_id) do
    %TokenTeam{}
    |> TokenTeam.changeset(%{token: token, team_id: team_id})
    |> Repo.insert(
      on_conflict: {:replace, [:team_id, :updated_at]},
      conflict_target: :token
    )
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval_ms)
  end

  defp generate_invite_code do
    "tb_inv_" <> Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false)
  end

  defp create_team_in_db(team_data) do
    Repo.transaction(fn ->
      {:ok, team} =
        %Team{}
        |> Team.changeset(%{name: team_data.name, rules: team_data.rules, skills: team_data.skills})
        |> Repo.insert()

      for m <- team_data.members do
        %Member{team_id: team.id}
        |> Member.changeset(%{name: m.name, role: m.role, soul: m[:soul], rules: m.rules, skills: m.skills})
        |> Repo.insert!()
      end

      Repo.preload(team, :members)
    end)
  end

  defp update_team_in_db(team_id, team_data) do
    team = Repo.get!(Team, team_id)

    team =
      team
      |> Team.changeset(%{name: team_data.name, rules: team_data.rules, skills: team_data.skills})
      |> Repo.update!()

    # Replace members
    from(m in Member, where: m.team_id == ^team_id) |> Repo.delete_all()

    for m <- team_data.members do
      %Member{team_id: team_id}
      |> Member.changeset(%{name: m.name, role: m.role, soul: m[:soul], rules: m.rules, skills: m.skills})
      |> Repo.insert!()
    end

    Repo.preload(team, :members, force: true)
  end

  defp normalize_team(attrs) when is_map(attrs) do
    members =
      (attrs["members"] || attrs[:members] || [])
      |> Enum.map(fn m ->
        %{
          name: m["name"] || m[:name] || "",
          role: m["role"] || m[:role] || "",
          soul: m["soul"] || m[:soul],
          rules: m["rules"] || m[:rules] || [],
          skills: m["skills"] || m[:skills] || []
        }
      end)

    rules =
      (attrs["rules"] || attrs[:rules] || [])
      |> Enum.map(fn r ->
        %{
          "id" => r["id"] || r[:id] || "",
          "title" => r["title"] || r[:title],
          "body" => r["body"] || r[:body] || ""
        }
        |> Enum.reject(fn {_k, v} -> is_nil(v) end)
        |> Map.new()
      end)

    skills =
      (attrs["skills"] || attrs[:skills] || [])
      |> Enum.map(fn s ->
        %{
          "id" => s["id"] || s[:id] || "",
          "title" => s["title"] || s[:title],
          "description" => s["description"] || s[:description],
          "body" => s["body"] || s[:body]
        }
        |> Enum.reject(fn {_k, v} -> is_nil(v) end)
        |> Map.new()
      end)

    %{name: attrs["name"] || attrs[:name] || "", members: members, rules: rules, skills: skills}
  end

  defp put_if_present(map, _key, nil), do: map
  defp put_if_present(map, _key, []), do: map
  defp put_if_present(map, key, val), do: Map.put(map, key, val)

  defp team_to_map(%Team{} = team) do
    %{
      "id" => team.id,
      "name" => team.name,
      "members" =>
        Enum.map(team.members, fn m ->
          %{"name" => m.name, "role" => m.role}
          |> put_if_present("soul", m.soul)
          |> put_if_present("rules", m.rules)
          |> put_if_present("skills", m.skills)
        end)
    }
    |> put_if_present("rules", team.rules)
    |> put_if_present("skills", team.skills)
  end
end
