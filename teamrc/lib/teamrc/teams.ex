defmodule Teamrc.Teams do
  use GenServer

  import Ecto.Query
  alias Teamrc.Repo
  alias Teamrc.Schema.{Team, Member, Invite, TokenTeam}

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

  @doc "Get all teams for a token. Returns {:ok, [team_map]} or :error."
  def get_teams(pid \\ __MODULE__, token) do
    GenServer.call(pid, {:get_teams, token})
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

  # --- GenServer Callbacks ---

  @impl true
  def init(_opts) do
    token_teams =
      Repo.all(TokenTeam)
      |> Enum.group_by(& &1.token, & &1.team_id)
      |> Map.new(fn {token, team_ids} -> {token, MapSet.new(team_ids)} end)

    {:ok, %{token_teams: token_teams}}
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
        case %Invite{}
             |> Invite.changeset(%{code: invite_code, expires_at: expires_at, team_id: team.id})
             |> Repo.insert() do
          {:ok, _invite} ->
            {:reply, {:ok, invite_code}, state}

          {:error, _changeset} ->
            {:reply, {:error, :invite_creation_failed}, state}
        end

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

        case %Invite{}
             |> Invite.changeset(%{code: invite_code, expires_at: expires_at, team_id: team_id})
             |> Repo.insert() do
          {:ok, _invite} ->
            {:reply, {:ok, invite_code, expires_at}, state}

          {:error, _changeset} ->
            {:reply, {:error, :invite_creation_failed}, state}
        end
    end
  end

  @impl true
  def handle_cast({:token_revoked, token}, state) do
    {:noreply, update_in(state.token_teams, &Map.delete(&1, token))}
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

  defp generate_invite_code do
    "trc_inv_" <> Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false)
  end

  defp create_team_in_db(team_data) do
    Repo.transaction(fn ->
      case %Team{}
           |> Team.changeset(%{name: team_data.name, skills: team_data.skills, platforms: team_data.platforms, knowledge: team_data.knowledge})
           |> Repo.insert() do
        {:ok, team} ->
          Enum.each(team_data.members, fn m ->
            case %Member{team_id: team.id}
                 |> Member.changeset(%{name: m.name, role: m.role, soul: m[:soul], skills: m.skills})
                 |> Repo.insert() do
              {:ok, _member} -> :ok
              {:error, changeset} -> Repo.rollback(changeset)
            end
          end)

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
           |> Team.changeset(%{name: team_data.name, skills: team_data.skills, platforms: team_data.platforms, knowledge: team_data.knowledge})
           |> Repo.update() do
        {:ok, team} ->
          # Replace members atomically within the transaction
          from(m in Member, where: m.team_id == ^team_id) |> Repo.delete_all()

          Enum.each(team_data.members, fn m ->
            case %Member{team_id: team_id}
                 |> Member.changeset(%{name: m.name, role: m.role, soul: m[:soul], skills: m.skills})
                 |> Repo.insert() do
              {:ok, _member} -> :ok
              {:error, changeset} -> Repo.rollback(changeset)
            end
          end)

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
    knowledge = attrs["knowledge"] || attrs[:knowledge]

    %{name: attrs["name"] || attrs[:name] || "", members: members, skills: skills, platforms: platforms, knowledge: knowledge}
  end

  defp put_if_present(map, _key, nil), do: map
  defp put_if_present(map, _key, []), do: map
  defp put_if_present(map, key, val), do: Map.put(map, key, val)

  defp team_to_map(%Team{} = team) do
    %{
      "id" => team.id,
      "name" => team.name,
      "updated_at" => team.updated_at && DateTime.to_iso8601(team.updated_at),
      "knowledge" => team.knowledge,
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
