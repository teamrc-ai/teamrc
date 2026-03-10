defmodule TeamrcWeb.Plugs.SessionClerkAuthTest do
  use TeamrcWeb.ConnCase, async: false

  alias TeamrcWeb.Plugs.SessionClerkAuth

  @rsa_key JOSE.JWK.generate_key({:rsa, 2048})
  @jwk_public JOSE.JWK.to_public(@rsa_key)

  @issuer "https://test.clerk.accounts.dev"
  @audience "test-audience"

  setup do
    original_skip = Application.get_env(:teamrc, :skip_clerk_auth, false)
    Application.put_env(:teamrc, :skip_clerk_auth, false)

    original_config = Application.get_env(:teamrc, Teamrc.ClerkJWT, [])

    Application.put_env(:teamrc, Teamrc.ClerkJWT,
      jwks_url: "https://test.clerk.accounts.dev/.well-known/jwks.json",
      issuer: @issuer,
      audience: @audience
    )

    seed_jwks_cache()

    on_exit(fn ->
      Application.put_env(:teamrc, :skip_clerk_auth, original_skip)
      Application.put_env(:teamrc, Teamrc.ClerkJWT, original_config)
      clean_jwks_cache()
    end)

    :ok
  end

  test "keeps authenticated session when verification is still fresh", %{conn: conn} do
    now = System.system_time(:second)

    conn =
      conn
      |> init_test_session(%{
        "clerk_user_id" => "user_existing",
        "clerk_email" => "existing@example.com",
        "clerk_verified_at" => now
      })
      |> SessionClerkAuth.call(SessionClerkAuth.init([]))

    assert get_session(conn, "clerk_user_id") == "user_existing"
    assert get_session(conn, "clerk_email") == "existing@example.com"
    assert get_session(conn, "clerk_verified_at") == now
  end

  test "clears stale authenticated session when Clerk cookie is missing", %{conn: conn} do
    stale = System.system_time(:second) - 901

    conn =
      conn
      |> init_test_session(%{
        "clerk_user_id" => "user_stale",
        "clerk_email" => "stale@example.com",
        "clerk_verified_at" => stale
      })
      |> SessionClerkAuth.call(SessionClerkAuth.init([]))

    assert is_nil(get_session(conn, "clerk_user_id"))
    assert is_nil(get_session(conn, "clerk_email"))
    assert is_nil(get_session(conn, "clerk_verified_at"))
  end

  test "re-verifies stale session when Clerk cookie is present and valid", %{conn: conn} do
    now = System.system_time(:second)

    token =
      build_jwt(%{
        "sub" => "user_refreshed",
        "email" => "refreshed@example.com",
        "iss" => @issuer,
        "aud" => @audience,
        "exp" => now + 3600
      })

    conn =
      conn
      |> init_test_session(%{
        "clerk_user_id" => "user_old",
        "clerk_email" => "old@example.com",
        "clerk_verified_at" => now - 901
      })
      |> Plug.Test.put_req_cookie("__session", token)
      |> SessionClerkAuth.call(SessionClerkAuth.init([]))

    assert get_session(conn, "clerk_user_id") == "user_refreshed"
    assert get_session(conn, "clerk_email") == "refreshed@example.com"
    assert get_session(conn, "clerk_verified_at") >= now
  end

  test "session is renewed on reverification (session ID rotation)", %{conn: conn} do
    now = System.system_time(:second)

    token =
      build_jwt(%{
        "sub" => "user_rotated",
        "email" => "rotated@example.com",
        "iss" => @issuer,
        "aud" => @audience,
        "exp" => now + 3600
      })

    conn =
      conn
      |> init_test_session(%{
        "clerk_user_id" => "user_old",
        "clerk_email" => "old@example.com",
        "clerk_verified_at" => now - 901
      })
      |> Plug.Test.put_req_cookie("__session", token)
      |> SessionClerkAuth.call(SessionClerkAuth.init([]))

    # The session should be configured for renewal
    assert conn.private[:plug_session_info] == :renew
  end

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
