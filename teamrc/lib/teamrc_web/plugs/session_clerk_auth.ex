defmodule TeamrcWeb.Plugs.SessionClerkAuth do
  @moduledoc """
  Browser pipeline plug that reads Clerk's `__session` cookie,
  verifies the JWT server-side, and stores the verified identity
  in the Phoenix session for use by LiveView.

  This plug is non-blocking: if no Clerk cookie is present or the
  JWT is invalid, the request continues without session values.
  LiveView pages can check for nil to show "please sign in" prompts.

  Sessions are re-verified against Clerk every 15 minutes to ensure
  deactivated accounts lose access promptly.
  """

  import Plug.Conn

  @skip_auth_allowed Mix.env() == :test
  @reverify_interval_seconds 900

  def init(opts), do: opts

  def call(conn, _opts) do
    if @skip_auth_allowed and Application.get_env(:teamrc, :skip_clerk_auth, false) do
      conn
    else
      case get_session(conn, "clerk_user_id") do
        nil -> try_verify_clerk(conn)
        _existing -> maybe_reverify(conn)
      end
    end
  end

  defp maybe_reverify(conn) do
    verified_at = get_session(conn, "clerk_verified_at") || 0
    now = System.system_time(:second)

    if now - verified_at > @reverify_interval_seconds do
      reverify_clerk(conn)
    else
      conn
    end
  end

  defp reverify_clerk(conn) do
    conn = fetch_cookies(conn)
    token = conn.cookies["__session"] || conn.cookies["__clerk_db_jwt"]

    if is_nil(token) or token == "" do
      clear_session_auth(conn)
    else
      case TeamrcWeb.Plugs.VerifyClerkJWT.verify_token(token) do
        {:ok, claims} ->
          conn
          |> put_session("clerk_user_id", claims["sub"])
          |> put_session("clerk_email", TeamrcWeb.Plugs.VerifyClerkJWT.get_email(claims))
          |> put_session("clerk_verified_at", System.system_time(:second))

        {:error, _} ->
          clear_session_auth(conn)
      end
    end
  end

  defp try_verify_clerk(conn) do
    conn = fetch_cookies(conn)
    token = conn.cookies["__session"] || conn.cookies["__clerk_db_jwt"]

    if is_nil(token) or token == "" do
      conn
    else
      case TeamrcWeb.Plugs.VerifyClerkJWT.verify_token(token) do
        {:ok, claims} ->
          conn
          |> configure_session(renew: true)
          |> put_session("clerk_user_id", claims["sub"])
          |> put_session("clerk_email", TeamrcWeb.Plugs.VerifyClerkJWT.get_email(claims))
          |> put_session("clerk_verified_at", System.system_time(:second))

        {:error, _} ->
          conn
      end
    end
  end

  defp clear_session_auth(conn) do
    conn
    |> delete_session("clerk_user_id")
    |> delete_session("clerk_email")
    |> delete_session("clerk_verified_at")
  end
end
