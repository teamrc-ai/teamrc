defmodule Teamrc.ChannelRateLimiter do
  @moduledoc """
  Token-based rate limiting for Phoenix channel pushes via ETS.

  Unlike per-socket rate limiting (which resets on reconnect and can be
  bypassed by opening multiple sockets), this module tracks the last push
  timestamp per token globally. A single token cannot exceed the rate limit
  regardless of how many sockets it opens.

  Uses `:ets.select_replace/2` + `:ets.insert_new/2` for atomic
  check-and-set, avoiding TOCTOU races between concurrent pushes.
  Stale entries are swept every 5 minutes.
  """

  use GenServer

  @table :teamrc_channel_rate_limits
  @default_interval_ms 1_000
  @sweep_interval_ms 300_000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    :ets.new(@table, [:set, :public, :named_table, read_concurrency: true, write_concurrency: true])
    schedule_sweep()
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
    cutoff = now - interval_ms

    # Atomically replace the entry only if it exists AND is old enough
    case :ets.select_replace(@table, [
           {{key, :"$1"}, [{:<, :"$1", cutoff}], [{{key, now}}]}
         ]) do
      1 ->
        # Entry existed and was old enough -- updated atomically
        :ok

      0 ->
        # Either the entry doesn't exist, or it's too recent
        case :ets.insert_new(@table, {key, now}) do
          true -> :ok
          false -> :rate_limited
        end
    end
  end

  @impl true
  def handle_info(:sweep, state) do
    sweep_stale_entries()
    schedule_sweep()
    {:noreply, state}
  end

  defp schedule_sweep do
    Process.send_after(self(), :sweep, @sweep_interval_ms)
  end

  defp sweep_stale_entries do
    cutoff = System.monotonic_time(:millisecond) - @sweep_interval_ms

    :ets.select_delete(@table, [
      {{:_, :"$1"}, [{:<, :"$1", cutoff}], [true]}
    ])
  end
end
