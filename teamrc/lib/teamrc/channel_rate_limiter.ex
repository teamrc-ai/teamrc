defmodule Teamrc.ChannelRateLimiter do
  @moduledoc """
  Token-based rate limiting for Phoenix channel pushes via ETS.

  Unlike per-socket rate limiting (which resets on reconnect and can be
  bypassed by opening multiple sockets), this module tracks the last push
  timestamp per token globally. A single token cannot exceed the rate limit
  regardless of how many sockets it opens.
  """

  use GenServer

  @table :teamrc_channel_rate_limits
  @default_interval_ms 1_000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    {:ok, %{}}
  end

  @doc """
  Check if a push is allowed for the given key.

  Returns `:ok` if the push is allowed (and records the current timestamp),
  or `:rate_limited` if the key has pushed too recently.
  """
  @spec check_rate(term(), non_neg_integer()) :: :ok | :rate_limited
  def check_rate(key, interval_ms \\ @default_interval_ms) do
    now = System.monotonic_time(:millisecond)

    case :ets.lookup(@table, key) do
      [{^key, last_at}] when now - last_at < interval_ms ->
        :rate_limited

      _ ->
        :ets.insert(@table, {key, now})
        :ok
    end
  end
end
