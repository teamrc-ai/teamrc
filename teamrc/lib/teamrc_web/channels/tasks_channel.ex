defmodule TeamrcWeb.TasksChannel do
  @moduledoc """
  Channel for real-time task updates between CLI daemons.

  Topic: `tasks:<team_id>`

  Handles:
  - Join: verify token access, subscribe to PubSub, reply with current tasks
  - PubSub messages from task mutations broadcast updates to connected clients
  """

  use Phoenix.Channel

  alias Teamrc.Tasks

  @impl true
  def join("tasks:" <> team_id, _params, socket) do
    token = socket.assigns.token

    # Verify this token has access to the team
    case Teamrc.Teams.resolve_team_id(token, team_id) do
      nil ->
        {:error, %{reason: "not_found"}}

      {:error, :team_id_required} ->
        {:error, %{reason: "team_id_required"}}

      ^team_id ->
        # Subscribe to PubSub for task changes
        Phoenix.PubSub.subscribe(Teamrc.PubSub, "team_tasks:#{team_id}")

        socket = assign(socket, :team_id, team_id)

        # Reply with current tasks
        tasks = Tasks.list_tasks_internal(team_id)
        task_list = Enum.map(tasks, &task_to_map/1)

        {:ok, %{tasks: task_list}, socket}
    end
  end

  @impl true
  def handle_info({:task_created, %{task: task}}, socket) do
    push(socket, "tasks:created", %{task: task_to_map(task)})
    {:noreply, socket}
  end

  def handle_info({:task_updated, %{task: task}}, socket) do
    push(socket, "tasks:updated", %{task: task_to_map(task)})
    {:noreply, socket}
  end

  # Ignore unexpected PubSub messages
  def handle_info(_msg, socket), do: {:noreply, socket}

  # --- Private helpers ---

  defp task_to_map(%Teamrc.Schema.Task{} = task) do
    %{
      number: task.number,
      description: task.description,
      assignee: task.assignee,
      status: task.status,
      created_by: task.created_by,
      claimed_by: task.claimed_by,
      claimed_at: task.claimed_at && DateTime.to_iso8601(task.claimed_at),
      completed_at: task.completed_at && DateTime.to_iso8601(task.completed_at),
      inserted_at: DateTime.to_iso8601(task.inserted_at),
      updated_at: DateTime.to_iso8601(task.updated_at)
    }
  end
end
