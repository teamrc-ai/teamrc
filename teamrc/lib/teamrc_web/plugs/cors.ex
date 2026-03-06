defmodule TeamrcWeb.Plugs.CORS do
  @moduledoc """
  Minimal CORS plug for the API.

  Since the API is consumed by CLI tools (not browsers), CORS is restrictive
  by default. Only allows requests from explicitly configured origins.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    allowed_origins = Application.get_env(:teamrc, :cors_origins, [])
    origin = get_req_header(conn, "origin") |> List.first()

    if origin && origin in allowed_origins do
      conn
      |> put_resp_header("access-control-allow-origin", origin)
      |> put_resp_header("access-control-allow-methods", "GET, POST, OPTIONS")
      |> put_resp_header("access-control-allow-headers", "content-type, x-tb-signature, x-tb-timestamp")
      |> put_resp_header("access-control-max-age", "86400")
      |> handle_preflight()
    else
      handle_preflight(conn)
    end
  end

  defp handle_preflight(%{method: "OPTIONS"} = conn) do
    conn
    |> send_resp(204, "")
    |> halt()
  end

  defp handle_preflight(conn), do: conn
end
