defmodule TeamrcWeb.Plugs.CacheBodyReader do
  @moduledoc "Caches the raw request body for signature verification."

  def read_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} ->
        conn = update_in(conn.assigns[:raw_body], &[body | &1 || []])
        {:ok, body, conn}

      {:more, body, conn} ->
        conn = update_in(conn.assigns[:raw_body], &[body | &1 || []])
        {:more, body, conn}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_raw_body(conn) do
    (conn.assigns[:raw_body] || [])
    |> Enum.reverse()
    |> Enum.join()
  end
end
