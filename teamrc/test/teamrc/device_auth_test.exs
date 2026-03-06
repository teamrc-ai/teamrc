defmodule Teamrc.DeviceAuthTest do
  use ExUnit.Case, async: true

  alias Teamrc.DeviceAuth

  setup do
    {:ok, pid} = DeviceAuth.start_link(name: :"device_auth_#{:erlang.unique_integer([:positive])}")
    {:ok, pid: pid}
  end

  describe "create_request/2" do
    test "returns valid device_code and user_code", %{pid: pid} do
      token = "trc_ak_test_#{:erlang.unique_integer([:positive])}"
      assert {:ok, result} = DeviceAuth.create_request(pid, token)

      assert is_binary(result.device_code)
      assert byte_size(result.device_code) == 64  # 32 bytes hex = 64 chars
      assert is_binary(result.user_code)
      assert Regex.match?(~r/^[A-Z2-9]{4}-[A-Z2-9]{4}$/, result.user_code)
      assert result.expires_in == 900
      assert result.interval == 5
      assert is_binary(result.verification_url)
    end
  end

  describe "poll_request/3" do
    test "pending request returns pending status", %{pid: pid} do
      token = "trc_ak_test_#{:erlang.unique_integer([:positive])}"
      {:ok, result} = DeviceAuth.create_request(pid, token)

      assert {:ok, %{status: :pending}} = DeviceAuth.poll_request(pid, result.device_code, token)
    end

    test "token mismatch returns error", %{pid: pid} do
      token = "trc_ak_test_#{:erlang.unique_integer([:positive])}"
      {:ok, result} = DeviceAuth.create_request(pid, token)

      assert {:error, :token_mismatch} =
               DeviceAuth.poll_request(pid, result.device_code, "trc_ak_other_token")
    end

    test "not found returns error", %{pid: pid} do
      assert {:error, :not_found} =
               DeviceAuth.poll_request(pid, "nonexistent_code", "trc_ak_whatever")
    end
  end

  describe "confirm_request/4" do
    test "confirming updates status", %{pid: pid} do
      token = "trc_ak_test_#{:erlang.unique_integer([:positive])}"
      {:ok, result} = DeviceAuth.create_request(pid, token)

      assert :ok =
               DeviceAuth.confirm_request(pid, result.user_code, "clerk_123", "user@example.com")
    end

    test "polling confirmed request returns confirmed status", %{pid: pid} do
      token = "trc_ak_test_#{:erlang.unique_integer([:positive])}"
      {:ok, result} = DeviceAuth.create_request(pid, token)

      DeviceAuth.confirm_request(pid, result.user_code, "clerk_123", "user@example.com")

      assert {:ok, %{status: :confirmed, clerk_user_id: "clerk_123", email: "user@example.com"}} =
               DeviceAuth.poll_request(pid, result.device_code, token)
    end

    test "confirming nonexistent user_code returns error", %{pid: pid} do
      assert {:error, :not_found} =
               DeviceAuth.confirm_request(pid, "ZZZZ-ZZZZ", "clerk_123", "user@example.com")
    end
  end

  describe "expired requests" do
    test "expired requests are cleaned up by sweep", %{pid: pid} do
      token = "trc_ak_test_#{:erlang.unique_integer([:positive])}"
      {:ok, result} = DeviceAuth.create_request(pid, token)

      # Manually expire the request by manipulating state
      :sys.replace_state(pid, fn state ->
        update_in(state, [:requests, result.device_code], fn req ->
          %{req | expires_at: DateTime.add(DateTime.utc_now(), -1, :second)}
        end)
      end)

      # Trigger sweep
      send(pid, :sweep)
      # Give the GenServer a moment to process
      :sys.get_state(pid)

      assert {:error, :not_found} =
               DeviceAuth.poll_request(pid, result.device_code, token)
    end
  end

  describe "rate limiting" do
    test "4th request for same token is rejected", %{pid: pid} do
      token = "trc_ak_test_#{:erlang.unique_integer([:positive])}"

      assert {:ok, _} = DeviceAuth.create_request(pid, token)
      assert {:ok, _} = DeviceAuth.create_request(pid, token)
      assert {:ok, _} = DeviceAuth.create_request(pid, token)
      assert {:error, :rate_limited} = DeviceAuth.create_request(pid, token)
    end

    test "different tokens can each have 3 requests", %{pid: pid} do
      token1 = "trc_ak_test_#{:erlang.unique_integer([:positive])}"
      token2 = "trc_ak_test_#{:erlang.unique_integer([:positive])}"

      assert {:ok, _} = DeviceAuth.create_request(pid, token1)
      assert {:ok, _} = DeviceAuth.create_request(pid, token1)
      assert {:ok, _} = DeviceAuth.create_request(pid, token1)
      assert {:ok, _} = DeviceAuth.create_request(pid, token2)
    end
  end

  describe "failed attempts" do
    test "5 failures invalidate the code", %{pid: pid} do
      token = "trc_ak_test_#{:erlang.unique_integer([:positive])}"
      {:ok, result} = DeviceAuth.create_request(pid, token)

      assert :ok = DeviceAuth.record_failed_attempt(pid, result.user_code)
      assert :ok = DeviceAuth.record_failed_attempt(pid, result.user_code)
      assert :ok = DeviceAuth.record_failed_attempt(pid, result.user_code)
      assert :ok = DeviceAuth.record_failed_attempt(pid, result.user_code)
      assert {:error, :code_invalidated} = DeviceAuth.record_failed_attempt(pid, result.user_code)

      # Request should now be gone
      assert {:error, :not_found} =
               DeviceAuth.poll_request(pid, result.device_code, token)
    end
  end
end
