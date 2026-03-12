defmodule Teamrc.DeviceAuth.CleanupTask do
  @moduledoc """
  Periodic task to clean up expired device auth requests from the database.

  Runs every 60 seconds and deletes rows where expires_at < now.
  """

  use GenServer

  @sweep_interval_ms :timer.seconds(60)

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  @impl true
  def init(_opts) do
    schedule_sweep()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:sweep, state) do
    Teamrc.DeviceAuth.cleanup_expired()
    schedule_sweep()
    {:noreply, state}
  end

  defp schedule_sweep do
    Process.send_after(self(), :sweep, @sweep_interval_ms)
  end
end
