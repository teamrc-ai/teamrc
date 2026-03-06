defmodule TeamrcWeb.AuthControllerTest do
  use TeamrcWeb.ConnCase, async: false

  describe "POST /api/auth/device" do
    test "creates a device authorization request", %{conn: conn} do
      token = "trc_ak_test_#{:erlang.unique_integer([:positive])}"

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/auth/device", %{"token" => token})

      resp = json_response(conn, 200)
      assert is_binary(resp["device_code"])
      assert is_binary(resp["user_code"])
      assert is_binary(resp["verification_url"])
      assert resp["expires_in"] == 900
      assert resp["interval"] == 5
    end
  end

  describe "GET /api/auth/device/:device_code" do
    test "returns pending status for new request", %{conn: conn} do
      token = "trc_ak_test_#{:erlang.unique_integer([:positive])}"

      # Create the request
      create_conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post("/api/auth/device", %{"token" => token})

      %{"device_code" => device_code} = json_response(create_conn, 200)

      # Poll it
      conn = get(conn, "/api/auth/device/#{device_code}", %{"token" => token})
      assert json_response(conn, 200) == %{"status" => "pending"}
    end

    test "returns confirmed status after confirmation", %{conn: conn} do
      token = "trc_ak_test_#{:erlang.unique_integer([:positive])}"

      # Create the request
      create_conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post("/api/auth/device", %{"token" => token})

      resp = json_response(create_conn, 200)
      device_code = resp["device_code"]
      user_code = resp["user_code"]

      # Confirm via GenServer directly (simulating web UI confirmation)
      Teamrc.DeviceAuth.confirm_request(user_code, "clerk_test_123", "test@example.com")

      # Poll — should be confirmed
      conn = get(conn, "/api/auth/device/#{device_code}", %{"token" => token})
      resp = json_response(conn, 200)

      assert resp["status"] == "confirmed"
      assert resp["email"] == "test@example.com"
      assert is_integer(resp["machine_count"])
      assert is_integer(resp["team_count"])
    end

    test "returns 404 for nonexistent device_code", %{conn: conn} do
      token = "trc_ak_test_#{:erlang.unique_integer([:positive])}"
      conn = get(conn, "/api/auth/device/nonexistent", %{"token" => token})
      assert json_response(conn, 404) == %{"error" => "not_found"}
    end

    test "returns 403 for token mismatch", %{conn: conn} do
      token = "trc_ak_test_#{:erlang.unique_integer([:positive])}"

      create_conn =
        build_conn()
        |> put_req_header("content-type", "application/json")
        |> post("/api/auth/device", %{"token" => token})

      %{"device_code" => device_code} = json_response(create_conn, 200)

      # Poll with wrong token
      conn = get(conn, "/api/auth/device/#{device_code}", %{"token" => "trc_ak_wrong_token"})
      assert json_response(conn, 403) == %{"error" => "token_mismatch"}
    end
  end
end
