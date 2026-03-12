defmodule TeamrcWeb.AccountController do
  use TeamrcWeb, :controller
  use TeamrcWeb.Plugs.ApiErrorHandler

  alias Teamrc.Accounts

  @doc "GET /api/account. Returns account info and machines."
  def show(conn, _params) do
    user = conn.assigns.current_scope.user

    case Accounts.get_user_with_machine_tokens(user.id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "account_not_found"})

      user_with_tokens ->
        machines =
          Enum.map(user_with_tokens.machine_tokens, fn mt ->
            %{
              id: mt.id,
              machine_name: mt.machine_name,
              token: truncate_token(mt.token),
              last_seen_at: mt.last_seen_at,
              revoked_at: mt.revoked_at
            }
          end)

        json(conn, %{
          account: %{id: user_with_tokens.id, email: user_with_tokens.email},
          machines: machines
        })
    end
  end

  @doc "GET /api/account/teams. Returns teams accessible through account's tokens with machine details."
  def teams(conn, _params) do
    user = conn.assigns.current_scope.user

    case Accounts.get_user_with_machine_tokens(user.id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "account_not_found"})

      user_with_tokens ->
        teams_with_machines = Accounts.get_user_teams_with_machines(user_with_tokens.id)
        team_ids = Enum.map(teams_with_machines, fn {team, _} -> team.id end)
        participants_map = Accounts.resolve_participants_batch(team_ids)

        teams_data =
          Enum.map(teams_with_machines, fn {team, machines} ->
            hashed_participants =
              Map.get(participants_map, team.id, ["anonymous"])
              |> Enum.map(fn
                "anonymous" -> "anonymous"
                email -> Teamrc.PII.email_hash(email) || "anonymous"
              end)

            %{
              id: team.id,
              name: team.name,
              agent_count: length(team.members),
              skill_count: length(team.skills || []),
              platforms: team.platforms || [],
              participants: hashed_participants,
              machines:
                Enum.map(machines, fn m ->
                  %{
                    token: truncate_token(m.token),
                    name: m.machine_name,
                    scope: m.scope,
                    project_name: m.project_name,
                    last_seen_at: m.last_seen_at || m.tt_last_seen_at
                  }
                end)
            }
          end)

        json(conn, %{teams: teams_data})
    end
  end

  @doc "DELETE /api/account/machines/:token. Revokes a machine token."
  def revoke_machine(conn, %{"token" => token}) do
    user = conn.assigns.current_scope.user

    case Accounts.revoke_machine_token(user.id, token) do
      :ok ->
        json(conn, %{status: "revoked"})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "token_not_found"})
    end
  end

  @doc "POST /api/account/reassociate. Copies team associations to a new token."
  def reassociate(conn, %{"new_token" => new_token}) do
    user = conn.assigns.current_scope.user

    case Accounts.reassociate_teams(user.id, new_token) do
      {:ok, count} ->
        json(conn, %{reassociated: count})

      {:error, :token_not_found} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "new_token must be a non-revoked token linked to your account"})

      {:error, :token_revoked} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "new_token must be a non-revoked token linked to your account"})
    end
  end

  @doc "GET /api/account/export. Exports all account data as JSON."
  def export(conn, _params) do
    user = conn.assigns.current_scope.user

    case Accounts.export_user_data(user.id) do
      {:ok, data} ->
        conn
        |> put_resp_header("content-disposition", "attachment; filename=\"teamrc-export.json\"")
        |> json(data)

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "account_not_found"})
    end
  end

  @doc "DELETE /api/account. Permanently deletes account and all associated data."
  def delete(conn, _params) do
    user = conn.assigns.current_scope.user

    case Accounts.delete_user_and_data(user) do
      :ok ->
        conn
        |> put_status(:ok)
        |> json(%{status: "deleted"})

      {:error, _reason} ->
        conn
        |> put_status(:internal_server_error)
        |> json(%{error: "deletion_failed"})
    end
  end

  defp truncate_token(token) when is_binary(token) do
    String.slice(token, 0, 12) <> "..."
  end

  defp truncate_token(nil), do: nil
end
