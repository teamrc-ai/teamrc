defmodule TeamrcWeb.Plugs.RateLimiter.Server do
  @moduledoc "Owns the rate limiter ETS table and schedules periodic cleanup."
  use GenServer

  @table :trc_rate_limiter
  @cleanup_interval_ms 300_000

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    table =
      case :ets.whereis(@table) do
        :undefined ->
          :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])

        ref ->
          ref
      end

    schedule_cleanup()
    {:ok, %{table: table}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    TeamrcWeb.Plugs.RateLimiter.purge_expired()
    schedule_cleanup()
    {:noreply, state}
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval_ms)
  end
end
