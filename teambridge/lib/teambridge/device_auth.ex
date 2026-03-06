defmodule Teambridge.DeviceAuth.Request do
  @moduledoc "Ephemeral struct representing a device authorization request."

  defstruct [
    :device_code,
    :user_code,
    :token,
    :status,
    :clerk_user_id,
    :email,
    :expires_at,
    :inserted_at,
    failed_attempts: 0
  ]
end

defmodule Teambridge.DeviceAuth do
  @moduledoc """
  GenServer for ephemeral device authorization requests.

  Implements a device authorization flow similar to OAuth 2.0 Device Authorization Grant.
  CLI creates a request, user confirms via browser, CLI polls for confirmation.
  """

  use GenServer

  alias Teambridge.DeviceAuth.Request

  @sweep_interval_ms :timer.seconds(60)
  @request_ttl_seconds 900
  @max_requests_per_token 3
  @max_global_requests 10_000
  @max_failed_attempts 5
  @user_code_alphabet ~c"ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

  # --- Client API ---

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, %{}, name: name)
  end

  @doc "Create a new device authorization request for the given machine token."
  def create_request(pid \\ __MODULE__, token) do
    GenServer.call(pid, {:create_request, token})
  end

  @doc "Poll a device authorization request by device_code. Token must match the originator."
  def poll_request(pid \\ __MODULE__, device_code, token) do
    GenServer.call(pid, {:poll_request, device_code, token})
  end

  @doc "Confirm a device authorization request by user_code (called from the web UI)."
  def confirm_request(pid \\ __MODULE__, user_code, clerk_user_id, email) do
    GenServer.call(pid, {:confirm_request, user_code, clerk_user_id, email})
  end

  @doc "Record a failed attempt for a user_code. Returns :ok or {:error, :code_invalidated} after 5 failures."
  def record_failed_attempt(pid \\ __MODULE__, user_code) do
    GenServer.call(pid, {:record_failed_attempt, user_code})
  end

  @doc "Get a confirmed request by user_code. Used to retrieve the machine token after confirmation."
  def get_request_by_user_code(pid \\ __MODULE__, user_code) do
    GenServer.call(pid, {:get_request_by_user_code, user_code})
  end

  # --- GenServer Callbacks ---

  @impl true
  def init(_opts) do
    schedule_sweep()
    {:ok, %{requests: %{}}}
  end

  @impl true
  def handle_call({:create_request, token}, _from, state) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    requests = state.requests

    # Check global cap
    if map_size(requests) >= @max_global_requests do
      {:reply, {:error, :global_limit_reached}, state}
    else
      # Check per-token rate limit (active, non-expired requests)
      active_for_token =
        requests
        |> Map.values()
        |> Enum.count(fn r -> r.token == token and DateTime.compare(r.expires_at, now) == :gt end)

      if active_for_token >= @max_requests_per_token do
        {:reply, {:error, :rate_limited}, state}
      else
        device_code = generate_device_code()
        user_code = generate_user_code()
        expires_at = DateTime.add(now, @request_ttl_seconds, :second)

        request = %Request{
          device_code: device_code,
          user_code: user_code,
          token: token,
          status: :pending,
          expires_at: expires_at,
          inserted_at: now,
          failed_attempts: 0
        }

        state = put_in(state, [:requests, device_code], request)

        result = %{
          device_code: device_code,
          user_code: user_code,
          verification_url: verification_url(),
          expires_in: @request_ttl_seconds,
          interval: 5
        }

        {:reply, {:ok, result}, state}
      end
    end
  end

  def handle_call({:poll_request, device_code, token}, _from, state) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case Map.get(state.requests, device_code) do
      nil ->
        {:reply, {:error, :not_found}, state}

      %Request{} = req ->
        cond do
          DateTime.compare(req.expires_at, now) != :gt ->
            # Expired — clean it up and return not_found
            state = update_in(state.requests, &Map.delete(&1, device_code))
            {:reply, {:error, :not_found}, state}

          req.token != token ->
            {:reply, {:error, :token_mismatch}, state}

          req.status == :pending ->
            {:reply, {:ok, %{status: :pending}}, state}

          req.status == :confirmed ->
            {:reply, {:ok, %{status: :confirmed, clerk_user_id: req.clerk_user_id, email: req.email}}, state}
        end
    end
  end

  def handle_call({:confirm_request, user_code, clerk_user_id, email}, _from, state) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case find_by_user_code(state.requests, user_code, now) do
      nil ->
        {:reply, {:error, :not_found}, state}

      {device_code, _req} ->
        state =
          update_in(state, [:requests, device_code], fn req ->
            %{req | status: :confirmed, clerk_user_id: clerk_user_id, email: email}
          end)

        {:reply, :ok, state}
    end
  end

  def handle_call({:record_failed_attempt, user_code}, _from, state) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case find_by_user_code(state.requests, user_code, now) do
      nil ->
        {:reply, {:error, :not_found}, state}

      {device_code, req} ->
        new_attempts = req.failed_attempts + 1

        if new_attempts >= @max_failed_attempts do
          state = update_in(state.requests, &Map.delete(&1, device_code))
          {:reply, {:error, :code_invalidated}, state}
        else
          state =
            update_in(state, [:requests, device_code], fn r ->
              %{r | failed_attempts: new_attempts}
            end)

          {:reply, :ok, state}
        end
    end
  end

  def handle_call({:get_request_by_user_code, user_code}, _from, state) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case find_by_user_code(state.requests, user_code, now) do
      nil -> {:reply, {:error, :not_found}, state}
      {_device_code, req} -> {:reply, {:ok, req}, state}
    end
  end

  @impl true
  def handle_info(:sweep, state) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    cleaned =
      state.requests
      |> Enum.reject(fn {_code, req} -> DateTime.compare(req.expires_at, now) != :gt end)
      |> Map.new()

    schedule_sweep()
    {:noreply, %{state | requests: cleaned}}
  end

  # --- Private Helpers ---

  defp schedule_sweep do
    Process.send_after(self(), :sweep, @sweep_interval_ms)
  end

  defp generate_device_code do
    :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)
  end

  defp generate_user_code do
    chars = @user_code_alphabet
    len = length(chars)
    bytes = :crypto.strong_rand_bytes(8)

    code =
      for <<byte <- bytes>>, into: "" do
        <<Enum.at(chars, rem(byte, len))>>
      end

    String.slice(code, 0, 4) <> "-" <> String.slice(code, 4, 4)
  end

  defp verification_url do
    base = TeambridgeWeb.Endpoint.url()
    "#{base}/auth/verify"
  end

  defp find_by_user_code(requests, user_code, now) do
    Enum.find(requests, fn {_device_code, req} ->
      req.user_code == user_code and DateTime.compare(req.expires_at, now) == :gt
    end)
  end
end
