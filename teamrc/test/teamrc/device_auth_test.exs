defmodule Teamrc.DeviceAuthTest do
  use Teamrc.DataCase, async: true

  alias Teamrc.DeviceAuth
  alias Teamrc.Schema.DeviceAuthRequest
  alias Teamrc.Repo

  @test_user_id Ecto.UUID.generate()
  @test_user_id_2 Ecto.UUID.generate()

  describe "create_request/1" do
    test "returns valid device_code and user_code" do
      token = "trc_ak_test_#{:erlang.unique_integer([:positive])}"
      assert {:ok, result} = DeviceAuth.create_request(token)

      assert is_binary(result.device_code)
      assert byte_size(result.device_code) == 64
      assert is_binary(result.user_code)
      assert Regex.match?(~r/^[A-Z2-9]{4}-[A-Z2-9]{4}$/, result.user_code)
      assert result.expires_in == 900
      assert result.interval == 5
      assert is_binary(result.verification_url)
    end

    test "inserts a row in the database" do
      token = "trc_ak_test_#{:erlang.unique_integer([:positive])}"
      {:ok, result} = DeviceAuth.create_request(token)

      request = Repo.one!(from r in DeviceAuthRequest, where: r.device_code == ^result.device_code)
      assert request.token == token
      assert request.status == "pending"
      assert request.user_code == result.user_code
    end
  end

  describe "poll_request/2" do
    test "pending request returns pending status" do
      token = "trc_ak_test_#{:erlang.unique_integer([:positive])}"
      {:ok, result} = DeviceAuth.create_request(token)

      assert {:ok, %{status: :pending}} = DeviceAuth.poll_request(result.device_code, token)
    end

    test "token mismatch returns error" do
      token = "trc_ak_test_#{:erlang.unique_integer([:positive])}"
      {:ok, result} = DeviceAuth.create_request(token)

      assert {:error, :not_found} =
               DeviceAuth.poll_request(result.device_code, "trc_ak_other_token")
    end

    test "not found returns error" do
      assert {:error, :not_found} =
               DeviceAuth.poll_request("nonexistent_code", "trc_ak_whatever")
    end
  end

  describe "confirm_request/3" do
    test "confirming updates status" do
      token = "trc_ak_test_#{:erlang.unique_integer([:positive])}"
      {:ok, result} = DeviceAuth.create_request(token)

      assert {:ok, _confirmed_req} =
               DeviceAuth.confirm_request(result.user_code, @test_user_id, "user@example.com")
    end

    test "polling confirmed request returns confirmed status" do
      token = "trc_ak_test_#{:erlang.unique_integer([:positive])}"
      {:ok, result} = DeviceAuth.create_request(token)

      {:ok, _} = DeviceAuth.confirm_request(result.user_code, @test_user_id, "user@example.com")

      assert {:ok, %{status: :confirmed, user_id: @test_user_id, email: "user@example.com"}} =
               DeviceAuth.poll_request(result.device_code, token)
    end

    test "confirming nonexistent user_code returns error" do
      assert {:error, :not_found} =
               DeviceAuth.confirm_request("ZZZZ-ZZZZ", @test_user_id, "user@example.com")
    end

    test "double confirm returns already_confirmed" do
      token = "trc_ak_test_#{:erlang.unique_integer([:positive])}"
      {:ok, result} = DeviceAuth.create_request(token)

      assert {:ok, _} = DeviceAuth.confirm_request(result.user_code, @test_user_id, "user@example.com")

      assert {:error, :already_confirmed} =
               DeviceAuth.confirm_request(result.user_code, @test_user_id_2, "other@example.com")
    end
  end

  describe "expired requests" do
    test "expired requests are cleaned up" do
      token = "trc_ak_test_#{:erlang.unique_integer([:positive])}"
      {:ok, result} = DeviceAuth.create_request(token)

      # Manually expire the request by updating the DB row
      request = Repo.one!(from r in DeviceAuthRequest, where: r.device_code == ^result.device_code)

      Repo.update!(
        Ecto.Changeset.change(request, %{
          expires_at: DateTime.add(DateTime.utc_now(), -1, :second) |> DateTime.truncate(:second)
        })
      )

      # Run cleanup
      assert {:ok, 1} = DeviceAuth.cleanup_expired()

      # Request should now be gone
      assert {:error, :not_found} =
               DeviceAuth.poll_request(result.device_code, token)
    end

    test "polling an expired request returns not_found" do
      token = "trc_ak_test_#{:erlang.unique_integer([:positive])}"
      {:ok, result} = DeviceAuth.create_request(token)

      # Manually expire the request
      request = Repo.one!(from r in DeviceAuthRequest, where: r.device_code == ^result.device_code)

      Repo.update!(
        Ecto.Changeset.change(request, %{
          expires_at: DateTime.add(DateTime.utc_now(), -1, :second) |> DateTime.truncate(:second)
        })
      )

      assert {:error, :not_found} =
               DeviceAuth.poll_request(result.device_code, token)
    end
  end

  describe "rate limiting" do
    test "4th request for same token is rejected" do
      token = "trc_ak_test_#{:erlang.unique_integer([:positive])}"

      assert {:ok, _} = DeviceAuth.create_request(token)
      assert {:ok, _} = DeviceAuth.create_request(token)
      assert {:ok, _} = DeviceAuth.create_request(token)
      assert {:error, :rate_limited} = DeviceAuth.create_request(token)
    end

    test "different tokens can each have 3 requests" do
      token1 = "trc_ak_test_#{:erlang.unique_integer([:positive])}"
      token2 = "trc_ak_test_#{:erlang.unique_integer([:positive])}"

      assert {:ok, _} = DeviceAuth.create_request(token1)
      assert {:ok, _} = DeviceAuth.create_request(token1)
      assert {:ok, _} = DeviceAuth.create_request(token1)
      assert {:ok, _} = DeviceAuth.create_request(token2)
    end
  end

  describe "failed attempts" do
    test "5 failures invalidate the code" do
      token = "trc_ak_test_#{:erlang.unique_integer([:positive])}"
      {:ok, result} = DeviceAuth.create_request(token)

      assert :ok = DeviceAuth.record_failed_attempt(result.user_code)
      assert :ok = DeviceAuth.record_failed_attempt(result.user_code)
      assert :ok = DeviceAuth.record_failed_attempt(result.user_code)
      assert :ok = DeviceAuth.record_failed_attempt(result.user_code)
      assert {:error, :code_invalidated} = DeviceAuth.record_failed_attempt(result.user_code)

      # Request should now be gone
      assert {:error, :not_found} =
               DeviceAuth.poll_request(result.device_code, token)
    end
  end

  describe "get_request_by_user_code/1" do
    test "returns the request when active" do
      token = "trc_ak_test_#{:erlang.unique_integer([:positive])}"
      {:ok, result} = DeviceAuth.create_request(token)

      assert {:ok, req} = DeviceAuth.get_request_by_user_code(result.user_code)
      assert req.token == token
      assert req.user_code == result.user_code
    end

    test "returns error for nonexistent code" do
      assert {:error, :not_found} = DeviceAuth.get_request_by_user_code("ZZZZ-ZZZZ")
    end
  end
end
