defmodule TeamrcWeb.Plugs.RateLimiter do
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
  @table :trc_rate_limiter
  @cleanup_interval_ms 300_000

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

    # Atomically increment counter, inserting a default entry if key doesn't exist
    count = :ets.update_counter(@table, token, {2, 1}, {token, 0, now})

    case :ets.lookup(@table, token) do
      [{^token, _count, window_start}] when now - window_start >= window_ms ->
        # Window expired — reset atomically
        :ets.insert(@table, {token, 1, now})
        conn

      _ ->
        if count > limit do
          conn
          |> put_status(429)
          |> Phoenix.Controller.json(%{error: "rate limit exceeded"})
          |> halt()
        else
          conn
        end
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
      # Periodically purge expired entries to prevent unbounded growth
      :timer.apply_interval(@cleanup_interval_ms, __MODULE__, :purge_expired, [])
    end
  end

  @doc false
  def purge_expired do
    cutoff = System.system_time(:millisecond) - @cleanup_interval_ms
    :ets.select_delete(@table, [{{:_, :_, :"$1"}, [{:<, :"$1", cutoff}], [true]}])
    :ok
  end
end
