defmodule TeambridgeWeb.Plugs.VerifySignatureTest do
  use TeambridgeWeb.ConnCase, async: false

  alias Teambridge.Auth

  # Enable auth for these security-specific tests
  setup do
    original = Application.get_env(:teambridge, :skip_auth, false)
    Application.put_env(:teambridge, :skip_auth, false)
    on_exit(fn -> Application.put_env(:teambridge, :skip_auth, original) end)

    {pub, priv} = :crypto.generate_key(:eddsa, :ed25519)
    token = Auth.to_token(pub)

    %{pub: pub, priv: priv, token: token}
  end

  describe "POST with valid signature" do
    test "passes through for /api/push", %{conn: conn, priv: priv, token: token} do
      body = %{"token" => token, "platform" => "test", "entry" => %{"type" => "msg", "content" => "hi"}}
      {signature, timestamp} = sign_body_with_timestamp(priv, body)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-tb-signature", Base.url_encode64(signature, padding: false))
        |> put_req_header("x-tb-timestamp", timestamp)
        |> post("/api/push", body)

      assert json_response(conn, 200) == %{"status" => "ok"}
    end

    test "passes through for /api/teams (create)", %{conn: conn, priv: priv, token: token} do
      body = %{"token" => token, "team" => %{"name" => "test-team"}}
      {signature, timestamp} = sign_body_with_timestamp(priv, body)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-tb-signature", Base.url_encode64(signature, padding: false))
        |> put_req_header("x-tb-timestamp", timestamp)
        |> post("/api/teams", body)

      resp = json_response(conn, 201)
      assert resp["team"]["name"] == "test-team"
      assert resp["team"]["id"]
    end
  end

  describe "GET with valid signature" do
    test "passes through for /api/teams/:token", %{conn: conn, priv: priv, token: token} do
      Teambridge.Teams.put_team(token, %{"name" => "test"})

      timestamp = Integer.to_string(System.system_time(:second))
      message = "#{timestamp}.GET /api/teams/#{token}"
      signature = :crypto.sign(:eddsa, :none, message, [priv, :ed25519])

      conn =
        conn
        |> put_req_header("x-tb-signature", Base.url_encode64(signature, padding: false))
        |> put_req_header("x-tb-timestamp", timestamp)
        |> get("/api/teams/#{token}")

      assert json_response(conn, 200)["team"]["name"] == "test"
    end
  end

  describe "missing signature" do
    test "returns 401 for POST without signature header", %{conn: conn, token: token} do
      body = %{"token" => token, "platform" => "test", "entry" => %{"type" => "msg"}}

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> post("/api/push", body)

      assert json_response(conn, 401) == %{"error" => "unauthorized"}
    end

    test "returns 401 for GET without signature header", %{conn: conn, token: token} do
      conn = get(conn, "/api/teams/#{token}")
      assert json_response(conn, 401) == %{"error" => "unauthorized"}
    end
  end

  describe "invalid signature" do
    test "returns 401 for POST with wrong signature", %{conn: conn, token: token} do
      body = %{"token" => token, "platform" => "test", "entry" => %{"type" => "msg"}}
      bad_sig = :crypto.strong_rand_bytes(64)
      timestamp = Integer.to_string(System.system_time(:second))

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-tb-signature", Base.url_encode64(bad_sig, padding: false))
        |> put_req_header("x-tb-timestamp", timestamp)
        |> post("/api/push", body)

      assert json_response(conn, 401) == %{"error" => "unauthorized"}
    end

    test "returns 401 for tampered body", %{conn: conn, priv: priv, token: token} do
      original_body = %{"token" => token, "platform" => "test", "entry" => %{"type" => "msg"}}
      {signature, timestamp} = sign_body_with_timestamp(priv, original_body)

      tampered_body = %{"token" => token, "platform" => "test", "entry" => %{"type" => "evil"}}

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-tb-signature", Base.url_encode64(signature, padding: false))
        |> put_req_header("x-tb-timestamp", timestamp)
        |> post("/api/push", tampered_body)

      assert json_response(conn, 401) == %{"error" => "unauthorized"}
    end
  end

  describe "replay attack prevention" do
    test "returns 401 for expired timestamp", %{conn: conn, priv: priv, token: token} do
      body = %{"token" => token, "platform" => "test", "entry" => %{"type" => "msg", "content" => "hi"}}
      # Timestamp 10 minutes ago
      timestamp = Integer.to_string(System.system_time(:second) - 600)
      message = "#{timestamp}.#{Jason.encode!(body)}"
      signature = :crypto.sign(:eddsa, :none, message, [priv, :ed25519])

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-tb-signature", Base.url_encode64(signature, padding: false))
        |> put_req_header("x-tb-timestamp", timestamp)
        |> post("/api/push", body)

      assert json_response(conn, 401) == %{"error" => "unauthorized"}
    end

    test "returns 401 for missing timestamp", %{conn: conn, priv: priv, token: token} do
      body = %{"token" => token, "platform" => "test", "entry" => %{"type" => "msg"}}
      message = Jason.encode!(body)
      signature = :crypto.sign(:eddsa, :none, message, [priv, :ed25519])

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-tb-signature", Base.url_encode64(signature, padding: false))
        |> post("/api/push", body)

      assert json_response(conn, 401) == %{"error" => "unauthorized"}
    end
  end

  describe "wrong key (BOLA prevention)" do
    test "returns 401 when signing with a different keypair", %{conn: conn, token: token} do
      {_attacker_pub, attacker_priv} = :crypto.generate_key(:eddsa, :ed25519)

      body = %{"token" => token, "platform" => "test", "entry" => %{"type" => "msg"}}
      {signature, timestamp} = sign_body_with_timestamp(attacker_priv, body)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-tb-signature", Base.url_encode64(signature, padding: false))
        |> put_req_header("x-tb-timestamp", timestamp)
        |> post("/api/push", body)

      assert json_response(conn, 401) == %{"error" => "unauthorized"}
    end
  end

  describe "malformed token" do
    test "returns 401 for non-tb_ak_ token", %{conn: conn} do
      body = %{"token" => "bad_token_123", "platform" => "test", "entry" => %{"type" => "msg"}}
      bad_sig = :crypto.strong_rand_bytes(64)
      timestamp = Integer.to_string(System.system_time(:second))

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-tb-signature", Base.url_encode64(bad_sig, padding: false))
        |> put_req_header("x-tb-timestamp", timestamp)
        |> post("/api/push", body)

      assert json_response(conn, 401) == %{"error" => "unauthorized"}
    end

    test "returns 401 for malformed base64 in token", %{conn: conn} do
      body = %{"token" => "tb_ak_!!!invalid!!!", "platform" => "test", "entry" => %{"type" => "msg"}}
      bad_sig = :crypto.strong_rand_bytes(64)
      timestamp = Integer.to_string(System.system_time(:second))

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-tb-signature", Base.url_encode64(bad_sig, padding: false))
        |> put_req_header("x-tb-timestamp", timestamp)
        |> post("/api/push", body)

      assert json_response(conn, 401) == %{"error" => "unauthorized"}
    end
  end

  describe "input validation" do
    test "rejects team name over 64 characters", %{conn: conn, priv: priv, token: token} do
      long_name = String.duplicate("a", 65)
      body = %{"token" => token, "team" => %{"name" => long_name}}
      {signature, timestamp} = sign_body_with_timestamp(priv, body)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-tb-signature", Base.url_encode64(signature, padding: false))
        |> put_req_header("x-tb-timestamp", timestamp)
        |> post("/api/teams", body)

      assert json_response(conn, 400)["error"] =~ "64 characters"
    end

    test "rejects team name with special characters", %{conn: conn, priv: priv, token: token} do
      body = %{"token" => token, "team" => %{"name" => "team<script>"}}
      {signature, timestamp} = sign_body_with_timestamp(priv, body)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-tb-signature", Base.url_encode64(signature, padding: false))
        |> put_req_header("x-tb-timestamp", timestamp)
        |> post("/api/teams", body)

      assert json_response(conn, 400)["error"] =~ "alphanumeric"
    end

    test "rejects team with more than 20 members", %{conn: conn, priv: priv, token: token} do
      members = for i <- 1..21, do: %{"name" => "agent#{i}", "role" => "worker"}
      body = %{"token" => token, "team" => %{"name" => "big-team", "members" => members}}
      {signature, timestamp} = sign_body_with_timestamp(priv, body)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-tb-signature", Base.url_encode64(signature, padding: false))
        |> put_req_header("x-tb-timestamp", timestamp)
        |> post("/api/teams", body)

      assert json_response(conn, 400)["error"] =~ "20 members"
    end
  end

  describe "sync input validation" do
    test "rejects path traversal in file paths", %{conn: conn, priv: priv, token: token} do
      body = %{
        "token" => token,
        "platform" => "test",
        "hashes" => %{"../../../etc/passwd" => "abc123"}
      }
      {signature, timestamp} = sign_body_with_timestamp(priv, body)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-tb-signature", Base.url_encode64(signature, padding: false))
        |> put_req_header("x-tb-timestamp", timestamp)
        |> post("/api/sync", body)

      assert json_response(conn, 400)["error"] =~ "invalid file path"
    end

    test "rejects absolute file paths", %{conn: conn, priv: priv, token: token} do
      body = %{
        "token" => token,
        "platform" => "test",
        "hashes" => %{"/etc/passwd" => "abc123"}
      }
      {signature, timestamp} = sign_body_with_timestamp(priv, body)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-tb-signature", Base.url_encode64(signature, padding: false))
        |> put_req_header("x-tb-timestamp", timestamp)
        |> post("/api/sync", body)

      assert json_response(conn, 400)["error"] =~ "invalid file path"
    end

    test "rejects invalid platform name", %{conn: conn, priv: priv, token: token} do
      body = %{
        "token" => token,
        "platform" => "bad platform!@#",
        "hashes" => %{}
      }
      {signature, timestamp} = sign_body_with_timestamp(priv, body)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-tb-signature", Base.url_encode64(signature, padding: false))
        |> put_req_header("x-tb-timestamp", timestamp)
        |> post("/api/sync", body)

      assert json_response(conn, 400)["error"] =~ "platform"
    end

    test "rejects missing platform", %{conn: conn, priv: priv, token: token} do
      body = %{
        "token" => token,
        "hashes" => %{"file.txt" => "abc"}
      }
      {signature, timestamp} = sign_body_with_timestamp(priv, body)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-tb-signature", Base.url_encode64(signature, padding: false))
        |> put_req_header("x-tb-timestamp", timestamp)
        |> post("/api/sync", body)

      assert json_response(conn, 400)["error"] =~ "platform"
    end

    test "accepts valid sync request", %{conn: conn, priv: priv, token: token} do
      body = %{
        "token" => token,
        "platform" => "claude-code",
        "hashes" => %{"agent-team.yaml" => "sha256abc"}
      }
      {signature, timestamp} = sign_body_with_timestamp(priv, body)

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("x-tb-signature", Base.url_encode64(signature, padding: false))
        |> put_req_header("x-tb-timestamp", timestamp)
        |> post("/api/sync", body)

      assert json_response(conn, 200)["changes"]
    end
  end

  describe "rate limiting" do
    test "returns 429 after exceeding rate limit", %{conn: _conn, priv: priv, token: token} do
      # Send 61 requests (limit is 60)
      results =
        for _i <- 1..61 do
          body = %{"token" => token, "platform" => "test", "entry" => %{"type" => "msg", "content" => "hi"}}
          {signature, timestamp} = sign_body_with_timestamp(priv, body)

          build_conn()
          |> put_req_header("content-type", "application/json")
          |> put_req_header("x-tb-signature", Base.url_encode64(signature, padding: false))
          |> put_req_header("x-tb-timestamp", timestamp)
          |> post("/api/push", body)
        end

      statuses = Enum.map(results, & &1.status)
      assert 429 in statuses
    end
  end

  # Helper: sign JSON-encoded body params with a private key and current timestamp
  defp sign_body_with_timestamp(priv, body) do
    timestamp = Integer.to_string(System.system_time(:second))
    message = "#{timestamp}.#{Jason.encode!(body)}"
    signature = :crypto.sign(:eddsa, :none, message, [priv, :ed25519])
    {signature, timestamp}
  end
end
