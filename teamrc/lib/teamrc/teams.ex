defmodule Teamrc.Teams do
  use GenServer

  import Ecto.Query
  alias Teamrc.Repo
  alias Teamrc.Schema.{Team, Member, Invite, TokenTeam}

  @content_ttl_ms :timer.hours(24)
  @cleanup_interval_ms :timer.minutes(5)
  @invite_ttl_hours 24
  @max_content_bytes_per_team 50 * 1024 * 1024  # 50MB

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

  @doc "Get all teams for a token. Returns {:ok, [team_map]} or :error."
  def get_teams(pid \\ __MODULE__, token) do
    GenServer.call(pid, {:get_teams, token})
  end

  @doc """
  Sync files for a platform.

  Accepts: token, platform name, hashes map, files map, and optional team_id.
  Returns: {:ok, %{files: changed_files_from_others}} or :error.

  The relay:
  1. Resolves token → team_id (using explicit team_id if provided)
  2. Stores the platform's hashes
  3. Stores any file content the platform sent
  4. Compares hashes across all platforms
  5. Returns content for any files where other platforms have newer versions
  """
  def sync(token, platform, hashes, files \\ %{}, team_id \\ nil, opts \\ []) do
    GenServer.call(__MODULE__, {:sync, token, platform, hashes, files, team_id, opts})
  end

  def sync_to(pid, token, platform, hashes, files, team_id \\ nil) when is_pid(pid) do
    GenServer.call(pid, {:sync, token, platform, hashes, files, team_id})
  end

  def push_buffer(token, entry, team_id \\ nil) do
    GenServer.call(__MODULE__, {:push_buffer, token, entry, team_id})
  end

  def push_buffer_to(pid, token, entry, team_id \\ nil) when is_pid(pid) do
    GenServer.call(pid, {:push_buffer, token, entry, team_id})
  end

  def pull_buffer(token, platform, team_id \\ nil) do
    GenServer.call(__MODULE__, {:pull_buffer, token, platform, team_id})
  end

  def pull_buffer_from(pid, token, platform, team_id \\ nil) when is_pid(pid) do
    GenServer.call(pid, {:pull_buffer, token, platform, team_id})
  end

  @doc "Preview a team by invite code without joining. Returns {:ok, team_map} or :error."
  def preview_by_invite(pid \\ __MODULE__, invite_code) do
    GenServer.call(pid, {:preview_by_invite, invite_code})
  end

  @doc "Create a new invite code for a team the token belongs to. Returns {:ok, code, expires_at} or :error."
  def create_invite(token, ttl_hours, team_id \\ nil) do
    GenServer.call(__MODULE__, {:create_invite, token, ttl_hours, team_id})
  end

  def create_invite_from(pid, token, ttl_hours, team_id \\ nil) when is_pid(pid) do
    GenServer.call(pid, {:create_invite, token, ttl_hours, team_id})
  end

  @doc "Check if a team has changes since a given Unix timestamp. Returns {:ok, boolean}."
  def check_changed(token, since, team_id \\ nil) do
    GenServer.call(__MODULE__, {:check_changed, token, since, team_id})
  end

  def check_changed_from(pid, token, since, team_id \\ nil) when is_pid(pid) do
    GenServer.call(pid, {:check_changed, token, since, team_id})
  end

  @doc "Get all content entries for a team (for audit log). Returns {:ok, entries} or {:error, :not_joined}."
  def get_log(token, team_id \\ nil) do
    GenServer.call(__MODULE__, {:get_log, token, team_id})
  end

  def get_log_from(pid, token, team_id \\ nil) when is_pid(pid) do
    GenServer.call(pid, {:get_log, token, team_id})
  end

  # --- GenServer Callbacks ---

  @impl true
  def init(_opts) do
    schedule_cleanup()

    token_teams =
      Repo.all(TokenTeam)
      |> Enum.group_by(& &1.token, & &1.team_id)
      |> Map.new(fn {token, team_ids} -> {token, MapSet.new(team_ids)} end)

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

    case first_team_id(state, token) do
      nil ->
        case create_team_in_db(team_data) do
          {:ok, team} ->
            upsert_token_team(token, team.id)
            token_teams = Map.update(state.token_teams, token, MapSet.new([team.id]), &MapSet.put(&1, team.id))
            state = %{state | token_teams: token_teams}
            {:reply, {:ok, team_to_map(team)}, state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end

      team_id ->
        case update_team_in_db(team_id, team_data) do
          {:ok, team} ->
            {:reply, {:ok, team_to_map(team)}, state}

          {:error, reason} ->
            {:reply, {:error, reason}, state}
        end
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

    result =
      from(i in Invite,
        where: i.code == ^invite_code and i.expires_at > ^now,
        preload: [team: :members]
      )
      |> Repo.one()

    case result do
      nil ->
        {:reply, :error, state}

      %Invite{team: team} ->
        upsert_token_team(token, team.id)
        token_teams = Map.update(state.token_teams, token, MapSet.new([team.id]), &MapSet.put(&1, team.id))
        state = %{state | token_teams: token_teams}
        {:reply, {:ok, team_to_map(team)}, state}
    end
  end

  def handle_call({:get_team, token}, _from, state) do
    case first_team_id(state, token) do
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

  def handle_call({:get_teams, token}, _from, state) do
    case Map.get(state.token_teams, token) do
      nil ->
        {:reply, :error, state}

      team_ids ->
        teams =
          team_ids
          |> MapSet.to_list()
          |> Enum.map(fn team_id ->
            Repo.get(Team, team_id) |> Repo.preload(:members)
          end)
          |> Enum.reject(&is_nil/1)
          |> Enum.map(&team_to_map/1)

        {:reply, {:ok, teams}, state}
    end
  end

  def handle_call({:sync, token, platform, incoming_hashes, incoming_files, team_id_param}, from, state) do
    handle_call({:sync, token, platform, incoming_hashes, incoming_files, team_id_param, []}, from, state)
  end

  def handle_call({:sync, token, platform, incoming_hashes, incoming_files, team_id_param, opts}, _from, state) do
    case resolve_team_id(state, token, team_id_param) do
      nil ->
        {:reply, {:error, :not_joined}, state}

      team_id ->
        # Update token_team metadata (scope, project_name, last_seen_at)
        scope = Keyword.get(opts, :scope)
        project_name = Keyword.get(opts, :project_name)
        if scope || project_name do
          now = DateTime.utc_now() |> DateTime.truncate(:second)
          upsert_token_team(token, team_id, scope: scope, project_name: project_name, last_seen_at: now)
        end

        {result, state} = do_sync(state, team_id, platform, incoming_hashes, incoming_files, token)
        {:reply, {:ok, result}, state}
    end
  end

  # push_buffer and pull_buffer — used by /api/push and /api/pull
  def handle_call({:push_buffer, token, entry, team_id_param}, _from, state) do
    case resolve_team_id(state, token, team_id_param) do
      nil -> {:reply, {:error, :not_joined}, state}
      team_id -> do_push_buffer(state, team_id, entry, token)
    end
  end

  def handle_call({:pull_buffer, token, platform, team_id_param}, _from, state) do
    case resolve_team_id(state, token, team_id_param) do
      nil -> {:reply, {:error, :not_joined}, state}
      team_id ->
        team_content = Map.get(state.content, team_id, %{})

        entries =
          team_content
          |> Enum.reject(fn {_file, meta} -> meta.source == platform end)
          |> Enum.map(fn {file, meta} ->
            %{"type" => file, "content" => meta.content, "source_platform" => meta.source,
              "pushed_by" => meta[:pushed_by], "timestamp" => meta.timestamp}
          end)

        {:reply, {:ok, entries}, state}
    end
  end

  def handle_call({:preview_by_invite, invite_code}, _from, state) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    result =
      from(i in Invite,
        where: i.code == ^invite_code and i.expires_at > ^now,
        preload: [team: :members]
      )
      |> Repo.one()

    case result do
      nil ->
        {:reply, :error, state}

      %Invite{team: team} ->
        {:reply, {:ok, team_to_map(team)}, state}
    end
  end

  def handle_call({:create_invite, token, ttl_hours, team_id_param}, _from, state) do
    case resolve_team_id(state, token, team_id_param) do
      nil ->
        {:reply, :error, state}

      team_id ->
        invite_code = generate_invite_code()
        expires_at = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.add(ttl_hours * 3600)

        %Invite{}
        |> Invite.changeset(%{code: invite_code, expires_at: expires_at, team_id: team_id})
        |> Repo.insert!()

        {:reply, {:ok, invite_code, expires_at}, state}
    end
  end

  def handle_call({:check_changed, token, since, team_id_param}, _from, state) do
    case resolve_team_id(state, token, team_id_param) do
      nil -> {:reply, {:error, :not_joined}, state}
      team_id ->
        last = Map.get(state.last_updated_at, team_id, 0)
        {:reply, {:ok, last > since}, state}
    end
  end

  def handle_call({:get_log, token, team_id_param}, _from, state) do
    case resolve_team_id(state, token, team_id_param) do
      nil ->
        {:reply, {:error, :not_joined}, state}

      team_id ->
        team_content = Map.get(state.content, team_id, %{})

        entries =
          team_content
          |> Enum.map(fn {file, meta} ->
            %{
              "type" => file,
              "content" => String.slice(meta.content, 0, 100),
              "source_platform" => meta.source,
              "pushed_by" => meta[:pushed_by],
              "timestamp" => meta.timestamp
            }
          end)
          |> Enum.sort_by(& &1["timestamp"], :desc)

        {:reply, {:ok, entries}, state}
    end
  end

  defp do_push_buffer(state, team_id, entry, token) do
    source = Map.get(entry, "source_platform") || Map.get(entry, :source_platform) || "unknown"
    file_key = Map.get(entry, "type") || Map.get(entry, :type) || "buffer"
    content_val = Map.get(entry, "content") || Map.get(entry, :content) || ""

    # Check per-team content size cap
    if exceeds_content_cap?(state, team_id, byte_size(content_val)) do
      {:reply, {:error, :buffer_full}, state}
    else
      team_content = Map.get(state.content, team_id, %{})
      team_content = Map.put(team_content, file_key, %{
        content: content_val,
        source: source,
        pushed_by: token,
        timestamp: DateTime.to_iso8601(DateTime.utc_now())
      })
      state = put_in(state, [:content, team_id], team_content)
      state = put_in(state, [:last_updated_at, team_id], System.system_time(:second))

      {:reply, :ok, state}
    end
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

  defp do_sync(state, team_id, platform, incoming_hashes, incoming_files, token) do
    # Check per-team content size cap before accepting new files
    new_content_size = incoming_files |> Enum.reduce(0, fn {_f, c}, acc -> acc + byte_size(c) end)

    if new_content_size > 0 and exceeds_content_cap?(state, team_id, new_content_size) do
      {%{files: %{}, error: "content_limit_exceeded"}, state}
    else
      # 1. Store this platform's hashes
      team_hashes = Map.get(state.hashes, team_id, %{})
      team_hashes = Map.put(team_hashes, platform, incoming_hashes)
      state = put_in(state, [:hashes, team_id], team_hashes)

      # 2. Store any content this platform is pushing
      now = DateTime.to_iso8601(DateTime.utc_now())
      team_content = Map.get(state.content, team_id, %{})

      team_content =
        Enum.reduce(incoming_files, team_content, fn {file, content}, acc ->
          Map.put(acc, file, %{content: content, source: platform, pushed_by: token, timestamp: now})
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
                %{content: content, timestamp: ts} = meta ->
                  updated_at =
                    case DateTime.from_iso8601(ts) do
                      {:ok, dt, _} -> DateTime.to_unix(dt)
                      _ -> 0
                    end

                  Map.put(acc2, file, %{content: content, updated_at: updated_at, pushed_by: meta[:pushed_by]})

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
  end

  # --- Private: Content size tracking ---

  defp exceeds_content_cap?(state, team_id, additional_bytes) do
    team_content = Map.get(state.content, team_id, %{})
    current_size = Enum.reduce(team_content, 0, fn {_k, meta}, acc -> acc + byte_size(meta.content) end)
    current_size + additional_bytes > @max_content_bytes_per_team
  end

  # --- Private helpers ---

  defp first_team_id(state, token) do
    case Map.get(state.token_teams, token) do
      nil -> nil
      %MapSet{} = set ->
        if MapSet.size(set) == 0, do: nil, else: Enum.at(set, 0)
    end
  end

  # Resolve team_id for a token. If team_id is provided, verify the token belongs to that team.
  # Otherwise fall back to the first team (backward compat).
  defp resolve_team_id(state, token, nil), do: first_team_id(state, token)
  defp resolve_team_id(state, token, team_id) do
    case Map.get(state.token_teams, token) do
      nil -> nil
      %MapSet{} = set ->
        if MapSet.member?(set, team_id), do: team_id, else: nil
    end
  end

  defp upsert_token_team(token, team_id, opts \\ []) do
    attrs =
      %{token: token, team_id: team_id}
      |> maybe_put(:scope, Keyword.get(opts, :scope))
      |> maybe_put(:project_name, Keyword.get(opts, :project_name))
      |> maybe_put(:last_seen_at, Keyword.get(opts, :last_seen_at))

    replace_fields = Enum.filter([:scope, :project_name, :last_seen_at], &Map.has_key?(attrs, &1))

    on_conflict = if replace_fields == [], do: :nothing, else: {:replace, replace_fields}

    %TokenTeam{}
    |> TokenTeam.changeset(attrs)
    |> Repo.insert(on_conflict: on_conflict, conflict_target: [:token, :team_id])
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, val), do: Map.put(map, key, val)

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval_ms)
  end

  defp generate_invite_code do
    "trc_inv_" <> Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false)
  end

  defp create_team_in_db(team_data) do
    Repo.transaction(fn ->
      case %Team{}
           |> Team.changeset(%{name: team_data.name, skills: team_data.skills, platforms: team_data.platforms})
           |> Repo.insert() do
        {:ok, team} ->
          for m <- team_data.members do
            %Member{team_id: team.id}
            |> Member.changeset(%{name: m.name, role: m.role, soul: m[:soul], skills: m.skills})
            |> Repo.insert!()
          end

          Repo.preload(team, :members)

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  defp update_team_in_db(team_id, team_data) do
    Repo.transaction(fn ->
      team = Repo.get!(Team, team_id)

      case team
           |> Team.changeset(%{name: team_data.name, skills: team_data.skills, platforms: team_data.platforms})
           |> Repo.update() do
        {:ok, team} ->
          # Replace members atomically within the transaction
          from(m in Member, where: m.team_id == ^team_id) |> Repo.delete_all()

          for m <- team_data.members do
            %Member{team_id: team_id}
            |> Member.changeset(%{name: m.name, role: m.role, soul: m[:soul], skills: m.skills})
            |> Repo.insert!()
          end

          Repo.preload(team, :members, force: true)

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  defp normalize_team(attrs) when is_map(attrs) do
    members =
      (attrs["members"] || attrs[:members] || [])
      |> Enum.map(fn m ->
        %{
          name: m["name"] || m[:name] || "",
          role: m["role"] || m[:role] || "",
          soul: m["soul"] || m[:soul],
          skills: m["skills"] || m[:skills] || []
        }
      end)

    skills =
      (attrs["skills"] || attrs[:skills] || [])
      |> Enum.map(fn s ->
        %{
          "id" => s["id"] || s[:id] || "",
          "title" => s["title"] || s[:title],
          "description" => s["description"] || s[:description],
          "alwaysApply" => s["alwaysApply"] || s[:alwaysApply],
          "body" => s["body"] || s[:body]
        }
        |> Enum.reject(fn {_k, v} -> is_nil(v) end)
        |> Map.new()
      end)

    platforms = attrs["platforms"] || attrs[:platforms] || []

    %{name: attrs["name"] || attrs[:name] || "", members: members, skills: skills, platforms: platforms}
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
          |> put_if_present("skills", m.skills)
        end)
    }
    |> put_if_present("skills", team.skills)
    |> put_if_present("platforms", team.platforms)
  end
end
