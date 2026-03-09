defmodule TeamrcWeb.AccountController do
  use TeamrcWeb, :controller
  use TeamrcWeb.Plugs.ApiErrorHandler

  alias Teamrc.Accounts

  @doc "GET /api/account — return account info and machines."
  def show(conn, _params) do
    clerk_user_id = conn.assigns[:clerk_user_id]

    case Accounts.get_account_with_tokens(clerk_user_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "account_not_found"})

      account ->
        machines =
          Enum.map(account.account_tokens, fn at ->
            %{
              id: at.id,
              machine_name: at.machine_name,
              token: truncate_token(at.token),
              last_seen_at: at.last_seen_at,
              revoked_at: at.revoked_at
            }
          end)

        json(conn, %{
          account: %{id: account.id, email: account.email},
          machines: machines
        })
    end
  end

  @doc "GET /api/account/teams — return teams accessible through account's tokens with machine details."
  def teams(conn, _params) do
    clerk_user_id = conn.assigns[:clerk_user_id]

    case Accounts.get_account_with_tokens(clerk_user_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "account_not_found"})

      account ->
        teams_with_machines = Accounts.get_account_teams_with_machines(account.id)
        team_ids = Enum.map(teams_with_machines, fn {team, _} -> team.id end)
        participants_map = Accounts.resolve_participants_batch(team_ids)

        teams_data =
          Enum.map(teams_with_machines, fn {team, machines} ->
            %{
              id: team.id,
              name: team.name,
              agent_count: length(team.members),
              skill_count: length(team.skills || []),
              platforms: team.platforms || [],
              participants: Map.get(participants_map, team.id, ["anonymous"]),
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

  @doc "DELETE /api/account/machines/:token — revoke a machine token."
  def revoke_machine(conn, %{"token" => token}) do
    clerk_user_id = conn.assigns[:clerk_user_id]

    case Accounts.get_account_with_tokens(clerk_user_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "account_not_found"})

      account ->
        case Accounts.revoke_token(account.id, token) do
          :ok ->
            json(conn, %{status: "revoked"})

          {:error, :not_found} ->
            conn
            |> put_status(:not_found)
            |> json(%{error: "token_not_found"})
        end
    end
  end

  @doc "POST /api/account/reassociate — copy team associations to a new token."
  def reassociate(conn, %{"new_token" => new_token}) do
    clerk_user_id = conn.assigns[:clerk_user_id]

    case Accounts.get_account_with_tokens(clerk_user_id) do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "account_not_found"})

      account ->
        case Accounts.reassociate_teams(account.id, new_token) do
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
  end

  defp truncate_token(token) when is_binary(token) do
    String.slice(token, 0, 12) <> "..."
  end

  defp truncate_token(nil), do: nil
end
