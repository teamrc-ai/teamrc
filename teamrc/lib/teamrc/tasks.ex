defmodule Teamrc.Tasks do
  @moduledoc "Context module for task operations."

  import Ecto.Query
  alias Teamrc.Repo
  alias Teamrc.Schema.{Task, Member}
  alias Teamrc.Teams

  @doc "Create a task for a team. Validates assignee is a team member and auto-increments number."
  def create_task(token, team_id, %{description: description, assignee: assignee} = attrs) do
    case Teams.resolve_team_id(token, team_id) do
      {:error, :team_id_required} ->
        {:error, :team_id_required}

      nil ->
        {:error, :not_found}

      resolved_id ->
        # Validate assignee is an actual team member
        member_exists =
          from(m in Member, where: m.team_id == ^resolved_id and m.name == ^assignee)
          |> Repo.exists?()

        if member_exists do
          do_create_task(resolved_id, token, description, assignee, attrs)
        else
          {:error, :invalid_assignee}
        end
    end
  end

  @max_tasks_per_team 1000

  defp do_create_task(team_id, token, description, assignee, attrs) do
    result =
      Repo.transaction(fn ->
        # Advisory lock on team_id to safely auto-increment task number.
        # Use a 64-bit hash to avoid cross-team collisions (phash2 is only 27-bit).
        <<lock_key::signed-integer-64, _rest::binary>> = :crypto.hash(:sha256, team_id)
        Repo.query!("SELECT pg_advisory_xact_lock($1)", [lock_key])

        # Guard against unbounded task creation
        count = from(t in Task, where: t.team_id == ^team_id, select: count(t.id)) |> Repo.one()
        if count >= @max_tasks_per_team, do: Repo.rollback(:task_limit_exceeded)

        next_number =
          from(t in Task,
            where: t.team_id == ^team_id,
            select: max(t.number)
          )
          |> Repo.one()
          |> case do
            nil -> 1
            max -> max + 1
          end

        task_attrs = %{
          number: next_number,
          description: description,
          assignee: assignee,
          status: "todo",
          created_by: Map.get(attrs, :created_by, token)
        }

        case %Task{team_id: team_id}
             |> Task.changeset(task_attrs)
             |> Repo.insert() do
          {:ok, task} -> task
          {:error, changeset} -> Repo.rollback(changeset)
        end
      end)

    case result do
      {:ok, task} ->
        broadcast_task_update(team_id, {:task_created, task})
        {:ok, task}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "List tasks for a team with optional filters."
  def list_tasks(token, team_id, opts \\ []) do
    case Teams.resolve_team_id(token, team_id) do
      {:error, :team_id_required} ->
        {:error, :team_id_required}

      nil ->
        {:error, :not_found}

      resolved_id ->
        {:ok, do_list_tasks(resolved_id, opts)}
    end
  end

  defp do_list_tasks(team_id, opts) do
    query = from(t in Task, where: t.team_id == ^team_id, order_by: [asc: t.number])

    query =
      case Keyword.get(opts, :status) do
        nil -> query
        status -> from(t in query, where: t.status == ^status)
      end

    query =
      case Keyword.get(opts, :assignee) do
        nil -> query
        assignee -> from(t in query, where: t.assignee == ^assignee)
      end

    Repo.all(query)
  end

  @doc "Update a task's status with state machine validation."
  def update_task_status(token, team_id, task_number, new_status) do
    case Teams.resolve_team_id(token, team_id) do
      {:error, :team_id_required} ->
        {:error, :team_id_required}

      nil ->
        {:error, :not_found}

      resolved_id ->
        do_update_task_status(resolved_id, token, task_number, new_status)
    end
  end

  defp do_update_task_status(team_id, token, task_number, new_status) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    result =
      Repo.transaction(fn ->
        task =
          from(t in Task,
            where: t.team_id == ^team_id and t.number == ^task_number,
            lock: "FOR UPDATE"
          )
          |> Repo.one()

        case task do
          nil ->
            Repo.rollback(:not_found)

          %Task{} = task ->
            case validate_transition(task.status, new_status) do
              :ok ->
                extra_attrs = transition_attrs(task.status, new_status, token, now)
                attrs = Map.merge(%{status: new_status}, extra_attrs)

                case task |> Task.changeset(attrs) |> Repo.update() do
                  {:ok, updated} -> updated
                  {:error, changeset} -> Repo.rollback(changeset)
                end

              {:error, :invalid_transition} ->
                Repo.rollback(:invalid_transition)
            end
        end
      end)

    case result do
      {:ok, task} ->
        broadcast_task_update(team_id, {:task_updated, task})
        {:ok, task}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "List tasks for a team without auth (for channel join reply)."
  def list_tasks_internal(team_id) do
    from(t in Task, where: t.team_id == ^team_id, order_by: [asc: t.number])
    |> Repo.all()
  end

  # State machine validation
  defp validate_transition("todo", "in_progress"), do: :ok
  defp validate_transition("in_progress", "done"), do: :ok
  defp validate_transition("todo", "cancelled"), do: :ok
  defp validate_transition("in_progress", "cancelled"), do: :ok
  defp validate_transition("in_progress", "failed"), do: :ok
  defp validate_transition(_from, _to), do: {:error, :invalid_transition}

  # Extra attributes for specific transitions
  defp transition_attrs("todo", "in_progress", token, now) do
    %{claimed_by: token, claimed_at: now}
  end

  defp transition_attrs("in_progress", "done", _token, now) do
    %{completed_at: now}
  end

  defp transition_attrs(_from, _to, _token, _now), do: %{}

  defp broadcast_task_update(team_id, message) do
    Phoenix.PubSub.broadcast(
      Teamrc.PubSub,
      "team_tasks:#{team_id}",
      message
    )
  end
end
