defmodule TeamrcWeb.Plugs.SessionClerkAuth do
  @moduledoc """
  Browser pipeline plug that reads Clerk's `__session` cookie,
  verifies the JWT server-side, and stores the verified identity
  in the Phoenix session for use by LiveView.

  This plug is non-blocking: if no Clerk cookie is present or the
  JWT is invalid, the request continues without session values.
  LiveView pages can check for nil to show "please sign in" prompts.
  """

  import Plug.Conn

  @skip_auth_allowed Mix.env() == :test

  def init(opts), do: opts

  def call(conn, _opts) do
    if @skip_auth_allowed and Application.get_env(:teamrc, :skip_clerk_auth, false) do
      conn
    else
      case get_session(conn, "clerk_user_id") do
        nil -> try_verify_clerk(conn)
        _existing -> conn
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
          |> put_session("clerk_user_id", claims["sub"])
          |> put_session("clerk_email", TeamrcWeb.Plugs.VerifyClerkJWT.get_email(claims))

        {:error, _} ->
          conn
      end
    end
  end
end
