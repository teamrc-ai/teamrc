defmodule TeamrcWeb.Plugs.ApiVersion do
  @moduledoc """
  Plug that validates the `X-Teamrc-Version` header on API requests.

  If the header is missing, the request is allowed through for backwards
  compatibility during rollout. If present but below the minimum supported
  version, the request is rejected with 426 Upgrade Required.
  """

  import Plug.Conn

  @minimum_version 1

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_req_header(conn, "x-teamrc-version") do
      [version_str | _] ->
        case Integer.parse(version_str) do
          {version, ""} when version >= @minimum_version ->
            conn

          {_, ""} ->
            conn
            |> put_status(426)
            |> Phoenix.Controller.json(%{
              error: "upgrade_required",
              message: "Your teamrc CLI is outdated. Please update: npm install -g teamrc",
              minimum_version: @minimum_version
            })
            |> halt()

          _ ->
            conn
            |> put_status(400)
            |> Phoenix.Controller.json(%{
              error: "bad_request",
              message: "Malformed version header. Expected an integer."
            })
            |> halt()
        end

      [] ->
        # No version header. Allow for backwards compatibility
        conn
    end
  end
end
