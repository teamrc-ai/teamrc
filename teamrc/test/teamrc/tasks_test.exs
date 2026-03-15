defmodule Teamrc.TasksTest do
  use Teamrc.DataCase, async: false

  alias Teamrc.Tasks
  alias Teamrc.Teams

  defp create_team_with_members(token, members) do
    {:ok, team_data} =
      Teams.put_team(token, %{
        "name" => "task-team-#{:erlang.unique_integer([:positive])}",
        "members" => members
      })

    team_data
  end

  describe "create_task" do
    test "with valid params succeeds and returns task with auto-incremented number" do
      token = "trc_ak_task_create_#{:erlang.unique_integer([:positive])}"
      team = create_team_with_members(token, [%{"name" => "agent1", "role" => "dev"}])

      {:ok, task1} =
        Tasks.create_task(token, team["id"], %{description: "First task", assignee: "agent1"})

      assert task1.number == 1
      assert task1.description == "First task"
      assert task1.assignee == "agent1"
      assert task1.status == "todo"
      assert task1.created_by == token

      {:ok, task2} =
        Tasks.create_task(token, team["id"], %{description: "Second task", assignee: "agent1"})

      assert task2.number == 2
    end

    test "validates assignee is team member" do
      token = "trc_ak_task_assignee_#{:erlang.unique_integer([:positive])}"
      team = create_team_with_members(token, [%{"name" => "agent1", "role" => "dev"}])

      assert {:error, :invalid_assignee} =
               Tasks.create_task(token, team["id"], %{
                 description: "Bad assignee",
                 assignee: "nonexistent"
               })
    end

    test "with invalid token returns error" do
      token = "trc_ak_task_invalid_#{:erlang.unique_integer([:positive])}"
      _team = create_team_with_members(token, [%{"name" => "agent1", "role" => "dev"}])

      bad_token = "trc_ak_task_bad_#{:erlang.unique_integer([:positive])}"

      assert {:error, :not_found} =
               Tasks.create_task(bad_token, nil, %{
                 description: "Should fail",
                 assignee: "agent1"
               })
    end
  end

  describe "list_tasks" do
    test "returns tasks ordered by number" do
      token = "trc_ak_task_list_#{:erlang.unique_integer([:positive])}"

      team =
        create_team_with_members(token, [
          %{"name" => "agent1", "role" => "dev"},
          %{"name" => "agent2", "role" => "qa"}
        ])

      {:ok, _} =
        Tasks.create_task(token, team["id"], %{description: "Task 1", assignee: "agent1"})

      {:ok, _} =
        Tasks.create_task(token, team["id"], %{description: "Task 2", assignee: "agent2"})

      {:ok, _} =
        Tasks.create_task(token, team["id"], %{description: "Task 3", assignee: "agent1"})

      {:ok, tasks} = Tasks.list_tasks(token, team["id"])
      assert length(tasks) == 3
      assert Enum.map(tasks, & &1.number) == [1, 2, 3]
    end

    test "with status filter works" do
      token = "trc_ak_task_filter_status_#{:erlang.unique_integer([:positive])}"
      team = create_team_with_members(token, [%{"name" => "agent1", "role" => "dev"}])

      {:ok, _} =
        Tasks.create_task(token, team["id"], %{description: "Task 1", assignee: "agent1"})

      {:ok, _} =
        Tasks.create_task(token, team["id"], %{description: "Task 2", assignee: "agent1"})

      # Move task 1 to in_progress
      {:ok, _} = Tasks.update_task_status(token, team["id"], 1, "in_progress")

      {:ok, todo_tasks} = Tasks.list_tasks(token, team["id"], status: "todo")
      assert length(todo_tasks) == 1
      assert hd(todo_tasks).number == 2

      {:ok, in_progress_tasks} = Tasks.list_tasks(token, team["id"], status: "in_progress")
      assert length(in_progress_tasks) == 1
      assert hd(in_progress_tasks).number == 1
    end

    test "with assignee filter works" do
      token = "trc_ak_task_filter_assignee_#{:erlang.unique_integer([:positive])}"

      team =
        create_team_with_members(token, [
          %{"name" => "agent1", "role" => "dev"},
          %{"name" => "agent2", "role" => "qa"}
        ])

      {:ok, _} =
        Tasks.create_task(token, team["id"], %{description: "Task 1", assignee: "agent1"})

      {:ok, _} =
        Tasks.create_task(token, team["id"], %{description: "Task 2", assignee: "agent2"})

      {:ok, agent1_tasks} = Tasks.list_tasks(token, team["id"], assignee: "agent1")
      assert length(agent1_tasks) == 1
      assert hd(agent1_tasks).assignee == "agent1"

      {:ok, agent2_tasks} = Tasks.list_tasks(token, team["id"], assignee: "agent2")
      assert length(agent2_tasks) == 1
      assert hd(agent2_tasks).assignee == "agent2"
    end
  end

  describe "update_task_status valid transitions" do
    setup do
      token = "trc_ak_task_transition_#{:erlang.unique_integer([:positive])}"
      team = create_team_with_members(token, [%{"name" => "agent1", "role" => "dev"}])
      %{token: token, team_id: team["id"]}
    end

    test "todo -> in_progress sets claimed_by and claimed_at", %{
      token: token,
      team_id: team_id
    } do
      {:ok, _} =
        Tasks.create_task(token, team_id, %{description: "Task", assignee: "agent1"})

      {:ok, task} = Tasks.update_task_status(token, team_id, 1, "in_progress")
      assert task.status == "in_progress"
      assert task.claimed_by == token
      assert %DateTime{} = task.claimed_at
    end

    test "in_progress -> done sets completed_at", %{token: token, team_id: team_id} do
      {:ok, _} =
        Tasks.create_task(token, team_id, %{description: "Task", assignee: "agent1"})

      {:ok, _} = Tasks.update_task_status(token, team_id, 1, "in_progress")
      {:ok, task} = Tasks.update_task_status(token, team_id, 1, "done")
      assert task.status == "done"
      assert %DateTime{} = task.completed_at
    end

    test "todo -> cancelled", %{token: token, team_id: team_id} do
      {:ok, _} =
        Tasks.create_task(token, team_id, %{description: "Task", assignee: "agent1"})

      {:ok, task} = Tasks.update_task_status(token, team_id, 1, "cancelled")
      assert task.status == "cancelled"
    end

    test "in_progress -> cancelled", %{token: token, team_id: team_id} do
      {:ok, _} =
        Tasks.create_task(token, team_id, %{description: "Task", assignee: "agent1"})

      {:ok, _} = Tasks.update_task_status(token, team_id, 1, "in_progress")
      {:ok, task} = Tasks.update_task_status(token, team_id, 1, "cancelled")
      assert task.status == "cancelled"
    end

    test "in_progress -> failed", %{token: token, team_id: team_id} do
      {:ok, _} =
        Tasks.create_task(token, team_id, %{description: "Task", assignee: "agent1"})

      {:ok, _} = Tasks.update_task_status(token, team_id, 1, "in_progress")
      {:ok, task} = Tasks.update_task_status(token, team_id, 1, "failed")
      assert task.status == "failed"
    end
  end

  describe "update_task_status invalid transitions" do
    setup do
      token = "trc_ak_task_invalid_trans_#{:erlang.unique_integer([:positive])}"
      team = create_team_with_members(token, [%{"name" => "agent1", "role" => "dev"}])
      %{token: token, team_id: team["id"]}
    end

    test "done -> in_progress returns :invalid_transition", %{
      token: token,
      team_id: team_id
    } do
      {:ok, _} =
        Tasks.create_task(token, team_id, %{description: "Task", assignee: "agent1"})

      {:ok, _} = Tasks.update_task_status(token, team_id, 1, "in_progress")
      {:ok, _} = Tasks.update_task_status(token, team_id, 1, "done")

      assert {:error, :invalid_transition} =
               Tasks.update_task_status(token, team_id, 1, "in_progress")
    end

    test "todo -> done returns :invalid_transition", %{token: token, team_id: team_id} do
      {:ok, _} =
        Tasks.create_task(token, team_id, %{description: "Task", assignee: "agent1"})

      assert {:error, :invalid_transition} = Tasks.update_task_status(token, team_id, 1, "done")
    end

    test "todo -> failed returns :invalid_transition", %{token: token, team_id: team_id} do
      {:ok, _} =
        Tasks.create_task(token, team_id, %{description: "Task", assignee: "agent1"})

      assert {:error, :invalid_transition} =
               Tasks.update_task_status(token, team_id, 1, "failed")
    end

    test "cancelled -> todo returns :invalid_transition", %{token: token, team_id: team_id} do
      {:ok, _} =
        Tasks.create_task(token, team_id, %{description: "Task", assignee: "agent1"})

      {:ok, _} = Tasks.update_task_status(token, team_id, 1, "cancelled")

      assert {:error, :invalid_transition} = Tasks.update_task_status(token, team_id, 1, "todo")
    end
  end

  describe "update_task_status concurrent claims" do
    test "only one concurrent claim wins" do
      token = "trc_ak_task_concurrent_#{:erlang.unique_integer([:positive])}"
      team = create_team_with_members(token, [%{"name" => "agent1", "role" => "dev"}])
      team_id = team["id"]

      # Create a second token that can access the team
      token2 = "trc_ak_task_concurrent2_#{:erlang.unique_integer([:positive])}"
      {:ok, invite_code, _} = Teams.create_invite(token, 24, team_id)
      {:ok, _} = Teams.join_by_invite(invite_code, token2)

      {:ok, _} =
        Tasks.create_task(token, team_id, %{description: "Race task", assignee: "agent1"})

      # Spawn two concurrent tasks trying to claim the same task
      parent = self()

      task1 =
        Task.async(fn ->
          result = Tasks.update_task_status(token, team_id, 1, "in_progress")
          send(parent, {:result1, result})
          result
        end)

      task2 =
        Task.async(fn ->
          result = Tasks.update_task_status(token2, team_id, 1, "in_progress")
          send(parent, {:result2, result})
          result
        end)

      result1 = Task.await(task1)
      result2 = Task.await(task2)

      # One should succeed, the other should fail with :invalid_transition
      # (since the first one already moved it to in_progress)
      results = [result1, result2]
      successes = Enum.filter(results, fn r -> match?({:ok, _}, r) end)
      failures = Enum.filter(results, fn r -> match?({:error, _}, r) end)

      assert length(successes) == 1
      assert length(failures) == 1

      {:ok, claimed_task} = hd(successes)
      assert claimed_task.status == "in_progress"

      {:error, reason} = hd(failures)
      assert reason == :invalid_transition
    end
  end

  describe "BOLA protection" do
    test "token without access to team returns error" do
      token = "trc_ak_task_bola_#{:erlang.unique_integer([:positive])}"
      team = create_team_with_members(token, [%{"name" => "agent1", "role" => "dev"}])

      other_token = "trc_ak_task_bola_other_#{:erlang.unique_integer([:positive])}"

      assert {:error, :not_found} =
               Tasks.create_task(other_token, team["id"], %{
                 description: "BOLA test",
                 assignee: "agent1"
               })

      assert {:error, :not_found} = Tasks.list_tasks(other_token, team["id"])

      assert {:error, :not_found} =
               Tasks.update_task_status(other_token, team["id"], 1, "in_progress")
    end
  end

  describe "list_tasks_internal" do
    test "returns tasks without auth" do
      token = "trc_ak_task_internal_#{:erlang.unique_integer([:positive])}"
      team = create_team_with_members(token, [%{"name" => "agent1", "role" => "dev"}])

      {:ok, _} =
        Tasks.create_task(token, team["id"], %{description: "Internal task", assignee: "agent1"})

      tasks = Tasks.list_tasks_internal(team["id"])
      assert length(tasks) == 1
      assert hd(tasks).description == "Internal task"
    end
  end

  describe "PubSub broadcasts" do
    test "create_task broadcasts to team_tasks topic" do
      token = "trc_ak_task_pubsub_#{:erlang.unique_integer([:positive])}"
      team = create_team_with_members(token, [%{"name" => "agent1", "role" => "dev"}])

      Phoenix.PubSub.subscribe(Teamrc.PubSub, "team_tasks:#{team["id"]}")

      {:ok, task} =
        Tasks.create_task(token, team["id"], %{description: "Broadcast test", assignee: "agent1"})

      assert_receive {:task_created, ^task}
    end

    test "update_task_status broadcasts to team_tasks topic" do
      token = "trc_ak_task_pubsub2_#{:erlang.unique_integer([:positive])}"
      team = create_team_with_members(token, [%{"name" => "agent1", "role" => "dev"}])

      {:ok, _} =
        Tasks.create_task(token, team["id"], %{
          description: "Status broadcast",
          assignee: "agent1"
        })

      Phoenix.PubSub.subscribe(Teamrc.PubSub, "team_tasks:#{team["id"]}")

      {:ok, task} = Tasks.update_task_status(token, team["id"], 1, "in_progress")

      assert_receive {:task_updated, ^task}
    end
  end
end
