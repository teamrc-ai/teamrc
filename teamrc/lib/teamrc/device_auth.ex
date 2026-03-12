defmodule Teamrc.DeviceAuth do
  @moduledoc """
  Postgres-backed device authorization requests.

  Implements a device authorization flow similar to OAuth 2.0 Device Authorization Grant.
  CLI creates a request, user confirms via browser, CLI polls for confirmation.

  Previously a GenServer with in-memory state; now backed by Postgres for
  crash resilience and multi-node support.
  """

  import Ecto.Query
  alias Teamrc.Repo
  alias Teamrc.Schema.DeviceAuthRequest

  @request_ttl_seconds 900
  @max_requests_per_token 3
  @max_global_requests 10_000
  @max_failed_attempts 5
  @user_code_alphabet ~c"ABCDEFGHJKLMNPQRSTUVWXYZ23456789"

  # --- Public API ---

  @doc "Create a new device authorization request for the given machine token."
  def create_request(token) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.transaction(fn ->
      # Check global cap
      global_count =
        Repo.one(
          from r in DeviceAuthRequest,
            where: r.expires_at > ^now,
            select: count(r.id)
        )

      if global_count >= @max_global_requests do
        Repo.rollback(:global_limit_reached)
      end

      # Check per-token rate limit
      token_count =
        Repo.one(
          from r in DeviceAuthRequest,
            where: r.token == ^token and r.expires_at > ^now,
            select: count(r.id)
        )

      if token_count >= @max_requests_per_token do
        Repo.rollback(:rate_limited)
      end

      device_code = generate_device_code()
      user_code = generate_user_code()
      expires_at = DateTime.add(now, @request_ttl_seconds, :second)

      attrs = %{
        device_code: device_code,
        user_code: user_code,
        token: token,
        status: "pending",
        expires_at: expires_at,
        failed_attempts: 0
      }

      case Repo.insert(DeviceAuthRequest.changeset(%DeviceAuthRequest{}, attrs)) do
        {:ok, _request} ->
          %{
            device_code: device_code,
            user_code: user_code,
            verification_url: verification_url(),
            expires_in: @request_ttl_seconds,
            interval: 5
          }

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  @doc "Poll a device authorization request by device_code. Token must match the originator."
  def poll_request(device_code, token) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case Repo.one(from r in DeviceAuthRequest, where: r.device_code == ^device_code) do
      nil ->
        {:error, :not_found}

      %DeviceAuthRequest{} = req ->
        cond do
          DateTime.compare(req.expires_at, now) != :gt ->
            # Expired. Clean it up and return not_found
            Repo.delete(req)
            {:error, :not_found}

          req.token != token ->
            # Return :not_found to avoid leaking whether a device code exists
            {:error, :not_found}

          req.status == "pending" ->
            {:ok, %{status: :pending}}

          req.status == "confirmed" ->
            Repo.delete(req)
            {:ok, %{status: :confirmed, user_id: req.account_id, email: req.email}}
        end
    end
  end

  @doc "Confirm a device authorization request by user_code (called from the web UI)."
  def confirm_request(user_code, user_id, email) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case find_active_by_user_code(user_code, now) do
      nil ->
        {:error, :not_found}

      %DeviceAuthRequest{status: "confirmed"} ->
        {:error, :already_confirmed}

      %DeviceAuthRequest{} = req ->
        case Repo.update(
               Ecto.Changeset.change(req, %{
                 status: "confirmed",
                 account_id: user_id,
                 email: email
               })
             ) do
          {:ok, confirmed_req} -> {:ok, confirmed_req}
          {:error, _} -> {:error, :update_failed}
        end
    end
  end

  @doc """
  Record a failed attempt for a user_code. Returns :ok or {:error, :code_invalidated}
  after #{@max_failed_attempts} failures. The increment is atomic (single UPDATE query)
  to prevent concurrent requests from bypassing the threshold.
  """
  def record_failed_attempt(user_code) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # Atomically increment failed_attempts
    query =
      from r in DeviceAuthRequest,
        where: r.user_code == ^user_code and r.expires_at > ^now

    case Repo.update_all(query, inc: [failed_attempts: 1]) do
      {0, _} ->
        {:error, :not_found}

      {1, _} ->
        # Check threshold after atomic increment
        attempts =
          Repo.one(from r in DeviceAuthRequest, where: r.user_code == ^user_code, select: r.failed_attempts)

        if attempts && attempts >= @max_failed_attempts do
          Repo.delete_all(query)
          {:error, :code_invalidated}
        else
          :ok
        end
    end
  end

  @doc "Get a request by user_code. Used to retrieve the machine token after confirmation."
  def get_request_by_user_code(user_code) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case find_active_by_user_code(user_code, now) do
      nil -> {:error, :not_found}
      %DeviceAuthRequest{} = req -> {:ok, req}
    end
  end

  @doc "Delete all expired device auth requests."
  def cleanup_expired do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    {count, _} =
      Repo.delete_all(
        from r in DeviceAuthRequest,
          where: r.expires_at < ^now
      )

    {:ok, count}
  end

  # --- Private Helpers ---

  defp find_active_by_user_code(user_code, now) do
    Repo.one(
      from r in DeviceAuthRequest,
        where: r.user_code == ^user_code and r.expires_at > ^now
    )
  end

  defp generate_device_code do
    :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)
  end

  defp generate_user_code do
    chars = @user_code_alphabet
    len = length(chars)
    limit = div(256, len) * len

    code =
      Stream.repeatedly(fn -> :crypto.strong_rand_bytes(1) |> :binary.first() end)
      |> Stream.filter(&(&1 < limit))
      |> Enum.take(8)
      |> Enum.map(&Enum.at(chars, rem(&1, len)))
      |> List.to_string()

    String.slice(code, 0, 4) <> "-" <> String.slice(code, 4, 4)
  end

  defp verification_url do
    base = TeamrcWeb.Endpoint.url()
    "#{base}/auth/verify"
  end
end
