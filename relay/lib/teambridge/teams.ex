defmodule Teambridge.Teams do
  use GenServer

  @buffer_ttl_ms :timer.hours(1)
  @cleanup_interval_ms :timer.minutes(5)

  # --- Client API ---

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  def put_team(pid \\ __MODULE__, token, team) do
    GenServer.call(pid, {:put_team, token, team})
  end

  def get_team(pid \\ __MODULE__, token) do
    GenServer.call(pid, {:get_team, token})
  end

  def push_buffer(pid \\ __MODULE__, token, entry) do
    GenServer.call(pid, {:push_buffer, token, entry})
  end

  def pull_buffer(pid \\ __MODULE__, token, platform) do
    GenServer.call(pid, {:pull_buffer, token, platform})
  end

  def put_hashes(pid \\ __MODULE__, token, platform, hashes) do
    GenServer.call(pid, {:put_hashes, token, platform, hashes})
  end

  def get_changes(pid \\ __MODULE__, token, requesting_platform) do
    GenServer.call(pid, {:get_changes, token, requesting_platform})
  end

  # --- Server Callbacks ---

  @impl true
  def init(_opts) do
    schedule_cleanup()

    state = %{
      teams: %{},
      hashes: %{},
      buffer: %{}
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:put_team, token, team}, _from, state) do
    state = put_in(state, [:teams, token], team)
    {:reply, :ok, state}
  end

  def handle_call({:get_team, token}, _from, state) do
    case Map.get(state.teams, token) do
      nil -> {:reply, :error, state}
      team -> {:reply, {:ok, team}, state}
    end
  end

  def handle_call({:push_buffer, token, entry}, _from, state) do
    wrapped = Map.put(entry, :delivered_to, MapSet.new())
    # Add timestamp if not present
    wrapped =
      if Map.has_key?(wrapped, "timestamp") or Map.has_key?(wrapped, :timestamp) do
        wrapped
      else
        Map.put(wrapped, "timestamp", DateTime.to_iso8601(DateTime.utc_now()))
      end

    buffer = Map.get(state.buffer, token, [])
    state = put_in(state, [:buffer, token], buffer ++ [wrapped])
    {:reply, :ok, state}
  end

  def handle_call({:pull_buffer, token, platform}, _from, state) do
    buffer = Map.get(state.buffer, token, [])

    {entries, updated_buffer} =
      Enum.reduce(buffer, {[], []}, fn entry, {acc_entries, acc_buffer} ->
        source = Map.get(entry, "source_platform") || Map.get(entry, :source_platform)
        already_delivered = MapSet.member?(entry.delivered_to, platform)

        if source == platform or already_delivered do
          {acc_entries, acc_buffer ++ [entry]}
        else
          updated_entry = Map.put(entry, :delivered_to, MapSet.put(entry.delivered_to, platform))
          # Return entry without the delivered_to metadata
          clean_entry = Map.delete(entry, :delivered_to)
          {acc_entries ++ [clean_entry], acc_buffer ++ [updated_entry]}
        end
      end)

    state = put_in(state, [:buffer, token], updated_buffer)
    {:reply, {:ok, entries}, state}
  end

  def handle_call({:put_hashes, token, platform, hashes}, _from, state) do
    token_hashes = Map.get(state.hashes, token, %{})
    token_hashes = Map.put(token_hashes, platform, hashes)
    state = put_in(state, [:hashes, token], token_hashes)
    {:reply, :ok, state}
  end

  def handle_call({:get_changes, token, requesting_platform}, _from, state) do
    token_hashes = Map.get(state.hashes, token, %{})

    changes =
      token_hashes
      |> Map.drop([requesting_platform])

    {:reply, {:ok, changes}, state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    now = DateTime.utc_now()

    cleaned_buffer =
      Map.new(state.buffer, fn {token, entries} ->
        filtered =
          Enum.filter(entries, fn entry ->
            timestamp_str = Map.get(entry, "timestamp") || Map.get(entry, :timestamp)

            case timestamp_str && DateTime.from_iso8601(timestamp_str) do
              {:ok, ts, _offset} ->
                DateTime.diff(now, ts, :millisecond) < @buffer_ttl_ms

              _ ->
                # Keep entries without valid timestamps
                true
            end
          end)

        {token, filtered}
      end)

    schedule_cleanup()
    {:noreply, %{state | buffer: cleaned_buffer}}
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval_ms)
  end
end
