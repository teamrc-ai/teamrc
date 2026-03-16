defmodule TeamrcWeb.TaskController do
  use TeamrcWeb, :controller
  use TeamrcWeb.Plugs.ApiErrorHandler

  alias Teamrc.Tasks

  def create_task(conn, %{"token" => token, "description" => description, "assignee" => assignee} = params) do
    with :ok <- validate_task_description(description),
         :ok <- validate_assignee_name(assignee) do
      team_id = params["team_id"]
      case Tasks.create_task(token, team_id, %{description: description, assignee: assignee}) do
        {:ok, task} ->
          conn |> put_status(:created) |> json(%{task: task_to_json(task)})
        {:error, :team_id_required} ->
          conn |> put_status(:conflict) |> json(%{error: "team_id required: token belongs to multiple teams"})
        {:error, :not_found} ->
          conn |> put_status(:not_found) |> json(%{error: "not_found"})
        {:error, :invalid_assignee} ->
          conn |> put_status(:bad_request) |> json(%{error: "assignee is not a team member"})
        {:error, :task_limit_exceeded} ->
          conn |> put_status(:unprocessable_entity) |> json(%{error: "task limit exceeded (max 1000 per team)"})
        {:error, reason} ->
          conn |> put_status(:bad_request) |> json(%{error: to_string(reason)})
      end
    else
      {:error, reason} -> conn |> put_status(:bad_request) |> json(%{error: reason})
    end
  end

  def list_tasks(conn, %{"token" => token} = params) do
    team_id = params["team_id"]

    with :ok <- (if params["status"], do: validate_task_status(params["status"]), else: :ok),
         :ok <- (if params["assignee"], do: validate_assignee_name(params["assignee"]), else: :ok) do
      opts = []
      opts = if params["status"], do: [{:status, params["status"]} | opts], else: opts
      opts = if params["assignee"], do: [{:assignee, params["assignee"]} | opts], else: opts

      case Tasks.list_tasks(token, team_id, opts) do
        {:ok, tasks} ->
          json(conn, %{tasks: Enum.map(tasks, &task_to_json/1)})
        {:error, :team_id_required} ->
          conn |> put_status(:conflict) |> json(%{error: "team_id required: token belongs to multiple teams"})
        {:error, :not_found} ->
          conn |> put_status(:not_found) |> json(%{error: "not_found"})
      end
    else
      {:error, reason} -> conn |> put_status(:bad_request) |> json(%{error: reason})
    end
  end

  def update_task(conn, %{"number" => number_str} = params) do
    token = conn.assigns[:verified_token]
    team_id = params["team_id"]
    status = params["status"]
    result = params["result"]

    with :ok <- validate_task_status(status),
         :ok <- validate_task_result(result),
         {number, ""} <- Integer.parse(number_str) do
      opts = if is_binary(result), do: [result: result], else: []
      case Tasks.update_task_status(token, team_id, number, status, opts) do
        {:ok, task} ->
          json(conn, %{task: task_to_json(task)})
        {:error, :invalid_transition} ->
          conn |> put_status(:conflict) |> json(%{error: "invalid status transition"})
        {:error, :not_found} ->
          conn |> put_status(:not_found) |> json(%{error: "task not found"})
        {:error, :team_id_required} ->
          conn |> put_status(:conflict) |> json(%{error: "team_id required: token belongs to multiple teams"})
        {:error, reason} ->
          conn |> put_status(:bad_request) |> json(%{error: to_string(reason)})
      end
    else
      {:error, reason} -> conn |> put_status(:bad_request) |> json(%{error: reason})
      :error -> conn |> put_status(:bad_request) |> json(%{error: "invalid task number"})
      _ -> conn |> put_status(:bad_request) |> json(%{error: "invalid task number"})
    end
  end

  # --- Validation Helpers ---

  defp validate_task_description(nil), do: {:error, "description is required"}
  defp validate_task_description(d) when is_binary(d) do
    cond do
      String.trim(d) == "" -> {:error, "description must not be empty"}
      byte_size(d) > 2000 -> {:error, "description must be 2000 characters or fewer"}
      true -> :ok
    end
  end
  defp validate_task_description(_), do: {:error, "description must be a string"}

  defp validate_assignee_name(nil), do: {:error, "assignee is required"}
  defp validate_assignee_name(a) when is_binary(a) do
    cond do
      String.trim(a) == "" -> {:error, "assignee must not be empty"}
      byte_size(a) > 64 -> {:error, "assignee must be 64 characters or fewer"}
      true -> :ok
    end
  end
  defp validate_assignee_name(_), do: {:error, "assignee must be a string"}

  @valid_task_statuses ~w(todo in_progress done cancelled failed)
  defp validate_task_status(nil), do: {:error, "status is required"}
  defp validate_task_status(s) when s in @valid_task_statuses, do: :ok
  defp validate_task_status(_), do: {:error, "status must be one of: todo, in_progress, done, cancelled, failed"}

  defp validate_task_result(nil), do: :ok
  defp validate_task_result(r) when is_binary(r) do
    if byte_size(r) > 10_000, do: {:error, "result must be 10000 characters or fewer"}, else: :ok
  end
  defp validate_task_result(_), do: {:error, "result must be a string"}

  defp task_to_json(%Teamrc.Schema.Task{} = task) do
    %{
      "number" => task.number,
      "description" => task.description,
      "assignee" => task.assignee,
      "status" => task.status,
      "created_by" => task.created_by,
      "claimed_by" => task.claimed_by,
      "claimed_at" => task.claimed_at && DateTime.to_iso8601(task.claimed_at),
      "completed_at" => task.completed_at && DateTime.to_iso8601(task.completed_at),
      "result" => task.result,
      "inserted_at" => DateTime.to_iso8601(task.inserted_at),
      "updated_at" => DateTime.to_iso8601(task.updated_at)
    }
  end
end
