defmodule TeamrcWeb.TaskApiTest do
  use TeamrcWeb.ConnCase, async: false

  defp create_team_with_members(token, members) do
    {:ok, team_data} =
      Teamrc.Teams.put_team(token, %{
        "name" => "task-api-team-#{:erlang.unique_integer([:positive])}",
        "members" => members
      })

    team_data
  end

  describe "POST /api/teams/tasks" do
    test "creates a task (201)", %{conn: conn} do
      token = "trc_ak_task_api_#{:erlang.unique_integer([:positive])}"
      team = create_team_with_members(token, [%{"name" => "agent1", "role" => "dev"}])

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/teams/tasks", %{
          "token" => token,
          "team_id" => team["id"],
          "description" => "Build the login page",
          "assignee" => "agent1"
        })

      resp = json_response(conn, 201)
      assert resp["task"]["number"] == 1
      assert resp["task"]["description"] == "Build the login page"
      assert resp["task"]["assignee"] == "agent1"
      assert resp["task"]["status"] == "todo"
      assert resp["task"]["created_by"] == token
      assert is_binary(resp["task"]["inserted_at"])
      assert is_binary(resp["task"]["updated_at"])
    end

    test "with empty description returns 400", %{conn: conn} do
      token = "trc_ak_task_api_empty_#{:erlang.unique_integer([:positive])}"
      team = create_team_with_members(token, [%{"name" => "agent1", "role" => "dev"}])

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/teams/tasks", %{
          "token" => token,
          "team_id" => team["id"],
          "description" => "",
          "assignee" => "agent1"
        })

      resp = json_response(conn, 400)
      assert resp["error"] =~ "description"
    end

    test "with invalid assignee returns 400", %{conn: conn} do
      token = "trc_ak_task_api_bad_assignee_#{:erlang.unique_integer([:positive])}"
      team = create_team_with_members(token, [%{"name" => "agent1", "role" => "dev"}])

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/teams/tasks", %{
          "token" => token,
          "team_id" => team["id"],
          "description" => "Some task",
          "assignee" => "nonexistent"
        })

      resp = json_response(conn, 400)
      assert resp["error"] =~ "assignee"
    end

    test "with oversized description returns 400", %{conn: conn} do
      token = "trc_ak_task_api_big_#{:erlang.unique_integer([:positive])}"
      team = create_team_with_members(token, [%{"name" => "agent1", "role" => "dev"}])

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/teams/tasks", %{
          "token" => token,
          "team_id" => team["id"],
          "description" => String.duplicate("x", 2001),
          "assignee" => "agent1"
        })

      resp = json_response(conn, 400)
      assert resp["error"] =~ "description"
    end
  end

  describe "GET /api/teams/tasks/:token" do
    test "returns task list", %{conn: conn} do
      token = "trc_ak_task_api_list_#{:erlang.unique_integer([:positive])}"

      team =
        create_team_with_members(token, [
          %{"name" => "agent1", "role" => "dev"},
          %{"name" => "agent2", "role" => "qa"}
        ])

      Teamrc.Tasks.create_task(token, team["id"], %{
        description: "Task 1",
        assignee: "agent1"
      })

      Teamrc.Tasks.create_task(token, team["id"], %{
        description: "Task 2",
        assignee: "agent2"
      })

      conn = get(conn, "/api/teams/tasks/#{token}?team_id=#{team["id"]}")
      resp = json_response(conn, 200)

      assert length(resp["tasks"]) == 2
      assert Enum.map(resp["tasks"], & &1["number"]) == [1, 2]
    end

    test "with status filter", %{conn: conn} do
      token = "trc_ak_task_api_filter_#{:erlang.unique_integer([:positive])}"
      team = create_team_with_members(token, [%{"name" => "agent1", "role" => "dev"}])

      Teamrc.Tasks.create_task(token, team["id"], %{
        description: "Task 1",
        assignee: "agent1"
      })

      Teamrc.Tasks.create_task(token, team["id"], %{
        description: "Task 2",
        assignee: "agent1"
      })

      Teamrc.Tasks.update_task_status(token, team["id"], 1, "in_progress")

      conn =
        get(conn, "/api/teams/tasks/#{token}?team_id=#{team["id"]}&status=in_progress")

      resp = json_response(conn, 200)
      assert length(resp["tasks"]) == 1
      assert hd(resp["tasks"])["number"] == 1
      assert hd(resp["tasks"])["status"] == "in_progress"
    end

    test "with assignee filter", %{conn: conn} do
      token = "trc_ak_task_api_af_#{:erlang.unique_integer([:positive])}"

      team =
        create_team_with_members(token, [
          %{"name" => "agent1", "role" => "dev"},
          %{"name" => "agent2", "role" => "qa"}
        ])

      Teamrc.Tasks.create_task(token, team["id"], %{
        description: "Task 1",
        assignee: "agent1"
      })

      Teamrc.Tasks.create_task(token, team["id"], %{
        description: "Task 2",
        assignee: "agent2"
      })

      conn =
        get(conn, "/api/teams/tasks/#{token}?team_id=#{team["id"]}&assignee=agent2")

      resp = json_response(conn, 200)
      assert length(resp["tasks"]) == 1
      assert hd(resp["tasks"])["assignee"] == "agent2"
    end

    test "returns 404 for unknown token", %{conn: conn} do
      conn = get(conn, "/api/teams/tasks/trc_ak_unknown_#{:erlang.unique_integer([:positive])}")
      resp = json_response(conn, 404)
      assert resp["error"] == "not_found"
    end
  end

  describe "PATCH /api/teams/tasks/:number" do
    test "updates status", %{conn: conn} do
      token = "trc_ak_task_api_patch_#{:erlang.unique_integer([:positive])}"
      team = create_team_with_members(token, [%{"name" => "agent1", "role" => "dev"}])

      Teamrc.Tasks.create_task(token, team["id"], %{
        description: "Patchable task",
        assignee: "agent1"
      })

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> patch("/api/teams/tasks/1", %{
          "token" => token,
          "team_id" => team["id"],
          "status" => "in_progress"
        })

      resp = json_response(conn, 200)
      assert resp["task"]["status"] == "in_progress"
      assert resp["task"]["claimed_by"] == token
      assert is_binary(resp["task"]["claimed_at"])
    end

    test "with invalid transition returns 409", %{conn: conn} do
      token = "trc_ak_task_api_conflict_#{:erlang.unique_integer([:positive])}"
      team = create_team_with_members(token, [%{"name" => "agent1", "role" => "dev"}])

      Teamrc.Tasks.create_task(token, team["id"], %{
        description: "Invalid transition",
        assignee: "agent1"
      })

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> patch("/api/teams/tasks/1", %{
          "token" => token,
          "team_id" => team["id"],
          "status" => "done"
        })

      resp = json_response(conn, 409)
      assert resp["error"] =~ "invalid status transition"
    end

    test "for non-existent task returns 404", %{conn: conn} do
      token = "trc_ak_task_api_notfound_#{:erlang.unique_integer([:positive])}"
      team = create_team_with_members(token, [%{"name" => "agent1", "role" => "dev"}])

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> patch("/api/teams/tasks/999", %{
          "token" => token,
          "team_id" => team["id"],
          "status" => "in_progress"
        })

      resp = json_response(conn, 404)
      assert resp["error"] =~ "not found"
    end

    test "with invalid status value returns 400", %{conn: conn} do
      token = "trc_ak_task_api_badstatus_#{:erlang.unique_integer([:positive])}"
      team = create_team_with_members(token, [%{"name" => "agent1", "role" => "dev"}])

      Teamrc.Tasks.create_task(token, team["id"], %{
        description: "Bad status",
        assignee: "agent1"
      })

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> patch("/api/teams/tasks/1", %{
          "token" => token,
          "team_id" => team["id"],
          "status" => "bogus"
        })

      resp = json_response(conn, 400)
      assert resp["error"] =~ "status must be one of"
    end

    test "with invalid task number returns 400", %{conn: conn} do
      token = "trc_ak_task_api_badnum_#{:erlang.unique_integer([:positive])}"
      team = create_team_with_members(token, [%{"name" => "agent1", "role" => "dev"}])

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> patch("/api/teams/tasks/notanumber", %{
          "token" => token,
          "team_id" => team["id"],
          "status" => "in_progress"
        })

      resp = json_response(conn, 400)
      assert resp["error"] =~ "invalid task number"
    end
  end
end
