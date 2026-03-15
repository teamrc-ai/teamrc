defmodule TeamrcWeb.TasksChannelTest do
  use TeamrcWeb.ChannelCase, async: false

  alias TeamrcWeb.{UserSocket, TasksChannel}

  setup do
    keypair = Teamrc.TestSigning.generate_keypair()
    ticket = generate_ticket(keypair)
    {:ok, socket} = connect(UserSocket, %{"ticket" => ticket})

    # Create team with a member
    token = keypair.token

    team_attrs = %{
      "name" => "task-test-team-#{:erlang.unique_integer([:positive])}",
      "members" => [%{"name" => "dev", "role" => "developer"}]
    }

    {:ok, team_data} = Teamrc.Teams.put_team(token, team_attrs)
    team_id = team_data["id"]

    %{socket: socket, keypair: keypair, team_id: team_id, token: token}
  end

  describe "join/3" do
    test "join with valid token succeeds and returns empty task list", %{
      socket: socket,
      team_id: team_id
    } do
      assert {:ok, reply, _socket} =
               subscribe_and_join(socket, TasksChannel, "tasks:#{team_id}")

      assert reply.tasks == []
    end

    test "join returns existing tasks", %{
      socket: socket,
      team_id: team_id,
      token: token
    } do
      {:ok, _task} =
        Teamrc.Tasks.create_task(token, team_id, %{
          description: "test task",
          assignee: "dev"
        })

      assert {:ok, reply, _socket} =
               subscribe_and_join(socket, TasksChannel, "tasks:#{team_id}")

      assert length(reply.tasks) == 1
      assert hd(reply.tasks).description == "test task"
    end

    test "join with wrong token is rejected", %{team_id: _team_id} do
      other_keypair = Teamrc.TestSigning.generate_keypair()
      other_ticket = generate_ticket(other_keypair)
      {:ok, other_socket} = connect(UserSocket, %{"ticket" => other_ticket})

      assert {:error, %{reason: "not_found"}} =
               subscribe_and_join(
                 other_socket,
                 TasksChannel,
                 "tasks:#{Ecto.UUID.generate()}"
               )
    end
  end

  describe "PubSub broadcasts" do
    test "task_created is forwarded to connected client", %{
      socket: socket,
      team_id: team_id,
      token: token
    } do
      {:ok, _reply, _socket} =
        subscribe_and_join(socket, TasksChannel, "tasks:#{team_id}")

      # Create a task which triggers PubSub broadcast
      {:ok, task} =
        Teamrc.Tasks.create_task(token, team_id, %{
          description: "broadcast test",
          assignee: "dev"
        })

      assert_push "tasks:created", %{task: pushed_task}
      assert pushed_task.description == "broadcast test"
      assert pushed_task.number == task.number
    end

    test "task_updated is forwarded to connected client", %{
      socket: socket,
      team_id: team_id,
      token: token
    } do
      {:ok, task} =
        Teamrc.Tasks.create_task(token, team_id, %{
          description: "update test",
          assignee: "dev"
        })

      {:ok, _reply, _socket} =
        subscribe_and_join(socket, TasksChannel, "tasks:#{team_id}")

      # Update task status
      {:ok, _updated} =
        Teamrc.Tasks.update_task_status(token, team_id, task.number, "in_progress")

      assert_push "tasks:updated", %{task: pushed_task}
      assert pushed_task.status == "in_progress"
    end
  end
end
