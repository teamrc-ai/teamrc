defmodule TeamrcWeb.Plugs.RateLimiter do
  @moduledoc """
  In-memory rate limiter keyed by client IP (and optionally token).

  Applies two layers of rate limiting:
  1. **Per-IP** — limits total requests from a single IP address.
     Catches abuse from unauthenticated sources and distributed token use.
  2. **Per-token** — limits requests from a single authenticated token.
     Prevents a compromised token from exhausting resources.

  Unauthenticated requests (no token) get a stricter per-IP limit.

  Configure limits per pipeline:
    plug RateLimiter, limit: 60, window_ms: 60_000, ip_limit: 120
  """

  import Plug.Conn

  @default_limit 60
  @default_ip_limit 120
  @default_unauth_ip_limit 30
  @default_window_ms 60_000
  @table :trc_rate_limiter
  @cleanup_interval_ms 300_000

  def init(opts) do
    ensure_table()
    %{
      limit: Keyword.get(opts, :limit, @default_limit),
      ip_limit: Keyword.get(opts, :ip_limit, @default_ip_limit),
      unauth_ip_limit: Keyword.get(opts, :unauth_ip_limit, @default_unauth_ip_limit),
      window_ms: Keyword.get(opts, :window_ms, @default_window_ms)
    }
  end

  def call(conn, opts) do
    ip_key = {:ip, client_ip(conn)}
    token = extract_token(conn)

    # Per-IP check (always applied)
    ip_limit = if token, do: opts.ip_limit, else: opts.unauth_ip_limit

    case check_rate(ip_key, ip_limit, opts.window_ms) do
      :ok ->
        # Per-token check (only if authenticated)
        if token do
          case check_rate({:token, token}, opts.limit, opts.window_ms) do
            :ok -> conn
            :rate_limited -> reject(conn)
          end
        else
          conn
        end

      :rate_limited ->
        reject(conn)
    end
  end

  defp check_rate(key, limit, window_ms) do
    now = System.system_time(:millisecond)

    count = :ets.update_counter(@table, key, {2, 1}, {key, 0, now})

    case :ets.lookup(@table, key) do
      [{^key, _count, window_start}] when now - window_start >= window_ms ->
        :ets.insert(@table, {key, 1, now})
        :ok

      _ ->
        if count > limit, do: :rate_limited, else: :ok
    end
  end

  defp client_ip(conn) do
    # Always use conn.remote_ip — X-Forwarded-For is attacker-controlled
    # and can be spoofed to bypass rate limits. If deploying behind a proxy,
    # configure Plug.RemoteIp or Bandit/Cowboy to set conn.remote_ip correctly.
    conn.remote_ip |> :inet.ntoa() |> to_string()
  end

  defp extract_token(conn) do
    cond do
      token = conn.body_params["token"] -> token
      token = conn.path_params["token"] -> token
      token = conn.query_params["token"] -> token
      true -> nil
    end
  end

  defp reject(conn) do
    conn
    |> put_resp_header("retry-after", "60")
    |> put_status(429)
    |> Phoenix.Controller.json(%{error: "rate limit exceeded"})
    |> halt()
  end

  defp ensure_table do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
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
