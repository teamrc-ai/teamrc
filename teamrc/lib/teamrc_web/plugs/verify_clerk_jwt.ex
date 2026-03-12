defmodule TeamrcWeb.Plugs.VerifyClerkJWT do
  @moduledoc """
  Plug that verifies Clerk-issued JWTs from the Authorization header.

  Extracts Bearer token, verifies the RS256 signature against Clerk's JWKS
  endpoint, validates standard claims (iss, exp, aud), and assigns
  `:clerk_user_id` and `:clerk_email` to the conn.

  ## Configuration

      config :teamrc, Teamrc.ClerkJWT,
        jwks_url: System.get_env("CLERK_JWKS_URL"),
        issuer: System.get_env("CLERK_ISSUER"),
        audience: System.get_env("CLERK_AUDIENCE")

  The `audience` is optional — if not configured, the `aud` claim is not checked.
  The `issuer` is REQUIRED in production — the app will fail to start without it.
  """

  import Plug.Conn

  @max_clock_skew_seconds 30

  # Only allow skipping auth in test environment
  @skip_auth_allowed Mix.env() == :test

  @doc "Verify a Clerk JWT token string. Returns {:ok, claims} or {:error, reason}."
  def verify_token(token) do
    with {:ok, jwks} <- fetch_jwks(),
         {:ok, claims} <- verify_and_decode(token, jwks),
         :ok <- validate_claims(claims) do
      {:ok, claims}
    end
  end

  def init(opts), do: opts

  def call(conn, _opts) do
    if @skip_auth_allowed and Application.get_env(:teamrc, :skip_clerk_auth, false) do
      conn
    else
      with {:ok, token} <- extract_bearer_token(conn),
           {:ok, jwks} <- fetch_jwks(),
           {:ok, claims} <- verify_and_decode(token, jwks),
           :ok <- validate_claims(claims) do
        conn
        |> assign(:clerk_user_id, claims["sub"])
        |> assign(:clerk_email, get_email(claims))
      else
        {:error, reason} ->
          conn
          |> put_status(401)
          |> Phoenix.Controller.json(%{error: reason})
          |> halt()
      end
    end
  end

  defp extract_bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token | _] -> {:ok, String.trim(token)}
      _ -> {:error, "missing or invalid authorization header"}
    end
  end

  defp verify_and_decode(token, jwks) do
    try do
      case JOSE.JWT.verify_strict(jwks, ["RS256"], token) do
        {true, %JOSE.JWT{fields: claims}, _jws} -> {:ok, claims}
        {false, _, _} -> {:error, "invalid token signature"}
      end
    rescue
      _ -> {:error, "invalid token"}
    end
  end

  defp validate_claims(claims) do
    config = Application.get_env(:teamrc, Teamrc.ClerkJWT, [])
    expected_issuer = Keyword.get(config, :issuer)
    expected_audience = Keyword.get(config, :audience)

    with :ok <- validate_issuer(claims, expected_issuer),
         :ok <- validate_expiration(claims),
         :ok <- validate_audience(claims, expected_audience) do
      :ok
    end
  end

  defp validate_issuer(claims, expected_issuer) when is_binary(expected_issuer) and expected_issuer != "" do
    if claims["iss"] == expected_issuer do
      :ok
    else
      {:error, "invalid issuer"}
    end
  end

  # Fail closed: if issuer is not configured, reject all tokens
  defp validate_issuer(_claims, _), do: {:error, "issuer not configured"}

  defp validate_expiration(claims) do
    case claims["exp"] do
      exp when is_number(exp) ->
        now = System.system_time(:second)

        if now <= exp + @max_clock_skew_seconds do
          :ok
        else
          {:error, "token expired"}
        end

      _ ->
        {:error, "missing expiration"}
    end
  end

  defp validate_audience(_claims, nil), do: :ok
  defp validate_audience(_claims, ""), do: :ok

  defp validate_audience(claims, expected_audience) do
    aud = claims["aud"]

    cond do
      aud == expected_audience -> :ok
      is_list(aud) and expected_audience in aud -> :ok
      true -> {:error, "invalid audience"}
    end
  end

  @doc "Extract email from verified Clerk JWT claims."
  def get_email(claims) do
    claims["email"] || claims["primary_email_address"]
  end

  # --- JWKS Caching via ETS ---

  @jwks_table :clerk_jwks_cache
  @jwks_ttl_seconds 300

  defp fetch_jwks do
    case :ets.lookup(@jwks_table, :jwks) do
      [{:jwks, jwks, fetched_at}] ->
        if System.system_time(:second) - fetched_at < @jwks_ttl_seconds do
          {:ok, jwks}
        else
          fetch_and_cache_jwks()
        end

      [] ->
        fetch_and_cache_jwks()
    end
  end

  defp fetch_and_cache_jwks do
    config = Application.get_env(:teamrc, Teamrc.ClerkJWT, [])
    jwks_url = Keyword.get(config, :jwks_url)

    if is_nil(jwks_url) or jwks_url == "" do
      {:error, "JWKS URL not configured"}
    else
      case fetch_jwks_from_url(jwks_url) do
        {:ok, jwks} ->
          :ets.insert(@jwks_table, {:jwks, jwks, System.system_time(:second)})
          {:ok, jwks}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp fetch_jwks_from_url(url) do
    url_charlist = String.to_charlist(url)

    ssl_opts = [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      depth: 3
    ]

    case :httpc.request(:get, {url_charlist, []}, [ssl: ssl_opts], []) do
      {:ok, {{_, 200, _}, _headers, body}} ->
        jwks = JOSE.JWK.from_map(Jason.decode!(List.to_string(body)))
        {:ok, jwks}

      {:ok, {{_, status, _}, _, _}} ->
        {:error, "JWKS fetch failed with status #{status}"}

      {:error, _reason} ->
        {:error, "authentication service unavailable"}
    end
  end
end
