defmodule TeambridgeWeb.Plugs.VerifyClerkJWTTest do
  use TeambridgeWeb.ConnCase, async: false

  alias TeambridgeWeb.Plugs.VerifyClerkJWT

  # Generate a test RSA key pair at compile time
  @rsa_key JOSE.JWK.generate_key({:rsa, 2048})
  @jwk_public JOSE.JWK.to_public(@rsa_key)

  @test_issuer "https://test.clerk.accounts.dev"
  @test_audience "test-audience"
  @test_user_id "user_abc123"
  @test_email "dev@example.com"

  setup do
    # Disable skip_clerk_auth so we actually test the plug
    original = Application.get_env(:teambridge, :skip_clerk_auth, false)
    Application.put_env(:teambridge, :skip_clerk_auth, false)

    # Configure Clerk JWT settings for tests
    original_config = Application.get_env(:teambridge, Teambridge.ClerkJWT, [])

    Application.put_env(:teambridge, Teambridge.ClerkJWT,
      jwks_url: "https://test.clerk.accounts.dev/.well-known/jwks.json",
      issuer: @test_issuer,
      audience: @test_audience
    )

    # Seed the ETS cache with our test public key so we don't make HTTP calls
    seed_jwks_cache()

    on_exit(fn ->
      Application.put_env(:teambridge, :skip_clerk_auth, original)
      Application.put_env(:teambridge, Teambridge.ClerkJWT, original_config)
      clean_jwks_cache()
    end)

    :ok
  end

  describe "valid JWT" do
    test "assigns clerk_user_id and clerk_email", %{conn: conn} do
      token = build_jwt(%{
        "sub" => @test_user_id,
        "email" => @test_email,
        "iss" => @test_issuer,
        "aud" => @test_audience,
        "exp" => System.system_time(:second) + 3600
      })

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> VerifyClerkJWT.call(VerifyClerkJWT.init([]))

      refute conn.halted
      assert conn.assigns[:clerk_user_id] == @test_user_id
      assert conn.assigns[:clerk_email] == @test_email
    end
  end

  describe "missing authorization header" do
    test "returns 401", %{conn: conn} do
      conn =
        conn
        |> VerifyClerkJWT.call(VerifyClerkJWT.init([]))

      assert conn.halted
      assert conn.status == 401
      assert Jason.decode!(conn.resp_body)["error"] =~ "authorization"
    end
  end

  describe "expired JWT" do
    test "returns 401", %{conn: conn} do
      token = build_jwt(%{
        "sub" => @test_user_id,
        "email" => @test_email,
        "iss" => @test_issuer,
        "aud" => @test_audience,
        "exp" => System.system_time(:second) - 120
      })

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> VerifyClerkJWT.call(VerifyClerkJWT.init([]))

      assert conn.halted
      assert conn.status == 401
      assert Jason.decode!(conn.resp_body)["error"] =~ "expired"
    end
  end

  describe "wrong algorithm (HS256)" do
    test "returns 401", %{conn: conn} do
      # Create an HMAC-signed token (HS256) — should be rejected
      hmac_key = JOSE.JWK.generate_key({:oct, 32})
      jws = %{"alg" => "HS256"}
      claims = %{
        "sub" => @test_user_id,
        "email" => @test_email,
        "iss" => @test_issuer,
        "aud" => @test_audience,
        "exp" => System.system_time(:second) + 3600
      }

      {_, token} = JOSE.JWT.sign(hmac_key, jws, claims) |> JOSE.JWS.compact()

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> VerifyClerkJWT.call(VerifyClerkJWT.init([]))

      assert conn.halted
      assert conn.status == 401
    end
  end

  describe "wrong issuer" do
    test "returns 401", %{conn: conn} do
      token = build_jwt(%{
        "sub" => @test_user_id,
        "email" => @test_email,
        "iss" => "https://evil.example.com",
        "aud" => @test_audience,
        "exp" => System.system_time(:second) + 3600
      })

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token}")
        |> VerifyClerkJWT.call(VerifyClerkJWT.init([]))

      assert conn.halted
      assert conn.status == 401
      assert Jason.decode!(conn.resp_body)["error"] =~ "issuer"
    end
  end

  # --- Helpers ---

  defp build_jwt(claims) do
    jws = %{"alg" => "RS256"}
    {_, token} = JOSE.JWT.sign(@rsa_key, jws, claims) |> JOSE.JWS.compact()
    token
  end

  defp seed_jwks_cache do
    table =
      case :ets.whereis(:clerk_jwks_cache) do
        :undefined -> :ets.new(:clerk_jwks_cache, [:named_table, :set, :public])
        _ -> :clerk_jwks_cache
      end

    :ets.insert(table, {:jwks, @jwk_public, System.system_time(:second)})
  end

  defp clean_jwks_cache do
    case :ets.whereis(:clerk_jwks_cache) do
      :undefined -> :ok
      _ -> :ets.delete_all_objects(:clerk_jwks_cache)
    end
  end
end
