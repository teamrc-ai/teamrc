if Mix.env() == :test do
  defmodule TeamrcWeb.TestSetupController do
    @moduledoc """
    Test-only endpoint for E2E server-side setup operations.

    Provides actions that can't be performed through the public API:
    creating users, linking tokens, confirming device auth, and
    simulating web-created teams.

    Guarded by `Mix.env() == :test` at compile time — this module
    does not exist in :dev or :prod builds.
    """

    use TeamrcWeb, :controller

    alias Teamrc.{Accounts, Teams, DeviceAuth}

    def setup(conn, %{"action" => "create_user"} = params) do
      email = params["email"] || "e2e-#{System.unique_integer([:positive])}@test.local"

      case Accounts.register_user(%{
             "email" => email,
             "terms_accepted" => "true"
           }) do
        {:ok, user} ->
          json(conn, %{user_id: user.id, email: user.email})

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "create_user failed", details: inspect(changeset.errors)})
      end
    end

    def setup(conn, %{"action" => "link_token", "user_id" => user_id, "token" => token}) do
      machine_name = "e2e-machine"

      case Accounts.link_machine_token(user_id, token, machine_name) do
        {:ok, _mt} ->
          json(conn, %{status: "linked"})

        {:error, reason} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "link_token failed", reason: inspect(reason)})
      end
    end

    def setup(conn, %{"action" => "create_team_web", "team" => team} = params) do
      owner_user_id = params["owner_user_id"]
      opts = if owner_user_id, do: [owner_user_id: owner_user_id], else: []

      case Teams.create_team_with_invite(team, opts) do
        {:ok, invite_code, team_id, claim_secret} ->
          json(conn, %{
            invite_code: invite_code,
            team_id: team_id,
            claim_secret: claim_secret
          })

        {:error, reason} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "create_team_web failed", reason: inspect(reason)})
      end
    end

    def setup(conn, %{
          "action" => "confirm_device_auth",
          "user_code" => user_code,
          "user_id" => user_id,
          "email" => email
        }) do
      case DeviceAuth.confirm_request(user_code, user_id, email) do
        {:ok, _req} ->
          json(conn, %{status: "confirmed"})

        {:error, reason} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "confirm_device_auth failed", reason: inspect(reason)})
      end
    end

    def setup(conn, %{"action" => "update_team", "team_id" => team_id, "team" => team_attrs} = params) do
      # Simulate a web-side update by directly calling put_team with a known token
      token = params["token"]

      case Teams.put_team(token, team_attrs, team_id) do
        {:ok, team_data} ->
          json(conn, %{team: team_data})

        {:error, reason} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "update_team failed", reason: inspect(reason)})
      end
    end

    def setup(conn, %{"action" => "get_team", "token" => token} = params) do
      team_id = params["team_id"]

      case Teams.get_team(token, team_id) do
        {:ok, team} ->
          json(conn, %{team: team})

        :error ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "not_found"})
      end
    end

    def setup(conn, %{"action" => "revoke_token", "user_id" => user_id, "token" => token}) do
      case Accounts.revoke_machine_token(user_id, token) do
        :ok ->
          json(conn, %{status: "revoked"})

        {:error, :not_found} ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "token_not_found"})
      end
    end

    def setup(conn, %{"action" => "reassociate", "user_id" => user_id, "new_token" => new_token}) do
      case Accounts.reassociate_teams(user_id, new_token) do
        {:ok, count} ->
          json(conn, %{reassociated: count})

        {:error, reason} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "reassociate failed", reason: inspect(reason)})
      end
    end

    def setup(conn, %{"action" => "export_user", "user_id" => user_id}) do
      case Accounts.export_user_data(user_id) do
        {:ok, data} ->
          json(conn, %{export: data})

        {:error, :not_found} ->
          conn
          |> put_status(:not_found)
          |> json(%{error: "account_not_found"})
      end
    end

    def setup(conn, %{"action" => "delete_user", "user_id" => user_id}) do
      case Accounts.get_user(user_id) do
        nil ->
          conn |> put_status(:not_found) |> json(%{error: "user_not_found"})

        user ->
          case Accounts.delete_user_and_data(user) do
            :ok -> json(conn, %{status: "deleted"})
            {:error, reason} ->
              conn |> put_status(:unprocessable_entity) |> json(%{error: inspect(reason)})
          end
      end
    end

    def setup(conn, %{"action" => "get_user_machines", "user_id" => user_id}) do
      teams_with_machines = Accounts.get_user_teams_with_machines(user_id)
      participants = Accounts.resolve_participants_batch(
        Enum.map(teams_with_machines, fn {team, _} -> team.id end)
      )

      data = Enum.map(teams_with_machines, fn {team, machines} ->
        %{
          team_id: team.id,
          team_name: team.name,
          machines: Enum.map(machines, fn m ->
            %{
              token: m.token,
              machine_name: m.machine_name,
              scope: m[:scope],
              project_name: m[:project_name]
            }
          end),
          participants: Map.get(participants, team.id, [])
        }
      end)

      json(conn, %{teams: data})
    end

    def setup(conn, %{"action" => "erase_token", "token" => token} = params) do
      team_id = params["team_id"]
      {:ok, count} = Teams.erase_token(token, team_id)
      json(conn, %{status: "erased", teams_removed: count})
    end

    def setup(conn, %{"action" => "clear_rate_limits"}) do
      try do
        :ets.delete_all_objects(:trc_rate_limiter)
        json(conn, %{status: "cleared"})
      rescue
        ArgumentError ->
          json(conn, %{status: "no_table"})
      end
    end

    def setup(conn, _params) do
      conn
      |> put_status(:bad_request)
      |> json(%{error: "unknown or invalid action"})
    end
  end
end
