defmodule TeamrcWeb.Plugs.PIIHeader do
  @moduledoc """
  Plug that adds an `X-PII-Access: true` response header to endpoints
  whose responses may contain Personally Identifiable Information.

  This header serves as an audit signal for infrastructure (proxies,
  logging pipelines) to handle PII-bearing responses with extra care
  (e.g., redacting from access logs, applying shorter cache TTLs).

  ## Usage

      plug TeamrcWeb.Plugs.PIIHeader
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    register_before_send(conn, fn conn ->
      put_resp_header(conn, "x-pii-access", "true")
    end)
  end
end
