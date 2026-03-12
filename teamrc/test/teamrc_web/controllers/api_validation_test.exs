defmodule TeamrcWeb.ApiValidationTest do
  @moduledoc "Tests for input validation fixes in the API controller."

  use TeamrcWeb.ConnCase, async: false

  # ---------------------------------------------------------------------------
  # Fix 3: validate_members off-by-one (exactly 20 should be allowed)
  # ---------------------------------------------------------------------------

  describe "validate_members boundary" do
    test "accepts exactly 20 members", %{conn: conn} do
      token = "tok_20mem_#{:erlang.unique_integer([:positive])}"

      members =
        for i <- 1..20 do
          %{"name" => "agent-#{i}", "role" => "worker"}
        end

      team = %{"name" => "big-team", "members" => members}

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/teams", %{"token" => token, "team" => team})

      resp = json_response(conn, 201)
      assert resp["team"]["name"] == "big-team"
      assert length(resp["team"]["members"]) == 20
    end

    test "rejects 21 members", %{conn: conn} do
      token = "tok_21mem_#{:erlang.unique_integer([:positive])}"

      members =
        for i <- 1..21 do
          %{"name" => "agent-#{i}", "role" => "worker"}
        end

      team = %{"name" => "too-big-team", "members" => members}

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/teams", %{"token" => token, "team" => team})

      resp = json_response(conn, 400)
      assert resp["error"] =~ "at most 20 members"
    end
  end

  # ---------------------------------------------------------------------------
  # Fix 13: validate_team_name trims trailing spaces
  # ---------------------------------------------------------------------------

  describe "team name trimming" do
    test "trailing spaces in team name are accepted after trimming", %{conn: conn} do
      token = "tok_trim_#{:erlang.unique_integer([:positive])}"
      team = %{"name" => "  my-team  ", "members" => []}

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/teams", %{"token" => token, "team" => team})

      resp = json_response(conn, 201)
      assert resp["team"]["name"] == "my-team"
    end

    test "purely whitespace name is rejected", %{conn: conn} do
      token = "tok_empty_#{:erlang.unique_integer([:positive])}"
      team = %{"name" => "   ", "members" => []}

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/teams", %{"token" => token, "team" => team})

      resp = json_response(conn, 400)
      assert resp["error"] =~ "must not be empty"
    end
  end
end
