defmodule TeamrcWeb.Plugs.VerifyOrigin do
  @moduledoc """
  Plug that verifies the Origin header on session-authenticated JSON API
  endpoints to prevent cross-site request forgery.

  For JSON APIs that rely on session cookies for authentication, CSRF
  protection via the Origin header is simpler and more appropriate than
  form-based CSRF tokens. Requests without an Origin header or with a
  mismatched Origin are rejected with 403 Forbidden.

  Safe methods (GET, HEAD, OPTIONS) are allowed through without checks
  since they should not cause side effects.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(%{method: method} = conn, _opts) when method in ["GET", "HEAD", "OPTIONS"] do
    conn
  end

  def call(conn, _opts) do
    origin = get_req_header(conn, "origin") |> List.first()
    app_host = TeamrcWeb.Endpoint.url()

    cond do
      is_nil(origin) ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(403, Jason.encode!(%{error: "missing_origin"}))
        |> halt()

      origin == app_host or String.starts_with?(origin, app_host <> "/") ->
        conn

      true ->
        conn
        |> put_resp_content_type("application/json")
        |> send_resp(403, Jason.encode!(%{error: "origin_mismatch"}))
        |> halt()
    end
  end
end
