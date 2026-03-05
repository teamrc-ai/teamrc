defmodule TeambridgeWeb.Plugs.RateLimiter do
  @moduledoc """
  In-memory token bucket rate limiter per token.

  Maintains an ETS table of {token, count, window_start} entries.
  Each token gets a fixed number of requests per window (60 seconds).

  Configure limits per action by passing opts:
    plug RateLimiter, limit: 60, window_ms: 60_000
  """

  import Plug.Conn

  @default_limit 60
  @default_window_ms 60_000
  @table :tb_rate_limiter

  def init(opts) do
    ensure_table()
    %{
      limit: Keyword.get(opts, :limit, @default_limit),
      window_ms: Keyword.get(opts, :window_ms, @default_window_ms)
    }
  end

  def call(conn, opts) do
    token = extract_token(conn)

    if token do
      check_rate(conn, token, opts)
    else
      # No token means auth plug will reject anyway
      conn
    end
  end

  defp check_rate(conn, token, %{limit: limit, window_ms: window_ms}) do
    now = System.system_time(:millisecond)

    case :ets.lookup(@table, token) do
      [{^token, count, window_start}] when now - window_start < window_ms ->
        if count >= limit do
          conn
          |> put_status(429)
          |> Phoenix.Controller.json(%{error: "rate limit exceeded"})
          |> halt()
        else
          :ets.update_counter(@table, token, {2, 1})
          conn
        end

      _ ->
        :ets.insert(@table, {token, 1, now})
        conn
    end
  end

  defp extract_token(conn) do
    cond do
      token = conn.body_params["token"] -> token
      token = conn.path_params["token"] -> token
      token = conn.query_params["token"] -> token
      true -> nil
    end
  end

  defp ensure_table do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    end
  end
end
