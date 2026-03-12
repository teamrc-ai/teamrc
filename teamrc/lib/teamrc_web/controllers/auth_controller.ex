defmodule TeamrcWeb.AuthController do
  use TeamrcWeb, :controller
  use TeamrcWeb.Plugs.ApiErrorHandler

  import Ecto.Query
  alias Teamrc.{DeviceAuth, Repo}
  alias Teamrc.Schema.TokenTeam
  alias Teamrc.Accounts

  @doc "POST /api/auth/device. Initiates device authorization flow."
  def create_device(conn, _params) do
    token = conn.assigns[:verified_token]

    case DeviceAuth.create_request(token) do
      {:ok, result} ->
        conn
        |> put_status(:ok)
        |> json(%{
          device_code: result.device_code,
          user_code: result.user_code,
          verification_url: result.verification_url,
          expires_in: result.expires_in,
          interval: result.interval
        })

      {:error, :rate_limited} ->
        conn
        |> put_status(429)
        |> json(%{error: "too many pending requests for this token"})

      {:error, :global_limit_reached} ->
        conn
        |> put_status(503)
        |> json(%{error: "service temporarily at capacity"})
    end
  end

  @doc "GET /api/auth/device/:device_code. Polls for device authorization status."
  def poll_device(conn, %{"device_code" => device_code}) do
    token = conn.assigns[:verified_token]

    case DeviceAuth.poll_request(device_code, token) do
      {:ok, %{status: :pending}} ->
        json(conn, %{status: "pending"})

      {:ok, %{status: :confirmed, user_id: user_id, email: email}} ->
        {machine_count, team_count} = get_user_stats(user_id)

        json(conn, %{
          status: "confirmed",
          email: email,
          machine_count: machine_count,
          team_count: team_count
        })

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "not_found"})
    end
  end

  # --- Private ---

  defp get_user_stats(user_id) do
    case Accounts.get_user_with_machine_tokens(user_id) do
      nil ->
        {0, 0}

      user ->
        active_tokens =
          user.machine_tokens
          |> Enum.filter(&is_nil(&1.revoked_at))

        machine_count = length(active_tokens)
        token_strings = Enum.map(active_tokens, & &1.token)

        team_count =
          if token_strings == [] do
            0
          else
            Repo.one(
              from tt in TokenTeam,
                where: tt.token in ^token_strings,
                select: count(tt.team_id, :distinct)
            )
          end

        {machine_count, team_count}
    end
  end
end
