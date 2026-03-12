defmodule TeambridgeWeb.Plugs.VerifySignature do
  @moduledoc """
  Plug that verifies Ed25519 request signatures for API authentication.

  Clients sign requests with their Ed25519 private key and include the
  base64url-encoded signature in the `x-tb-signature` header.

  The token (`tb_ak_<base64url(public_key)>`) is extracted from:
  - `body_params["token"]` for POST requests
  - `path_params["token"]` for GET requests

  The signed message is:
  - For POST: the raw request body (exact bytes sent by the client)
  - For GET: "GET /path" (method + space + request path)

  The `x-tb-timestamp` header is required and must be within 5 minutes
  of server time to prevent replay attacks.

  This prevents BOLA because the token embeds the public key, and only
  the holder of the corresponding private key can produce a valid signature.

  ## Configuration

  Set `config :teambridge, :skip_auth, true` to bypass signature verification
  (used in test environment).
  """

  import Plug.Conn
  alias Teambridge.Auth
  alias TeambridgeWeb.Plugs.CacheBodyReader

  # Compile-time check: skip_auth must never be configured in prod
  @skip_auth_allowed Mix.env() == :test

  def init(opts), do: opts

  @max_timestamp_drift_seconds 300

  def call(conn, _opts) do
    if @skip_auth_allowed and Application.get_env(:teambridge, :skip_auth, false) do
      # Still extract token for downstream use, just skip verification
      case extract_token(conn) do
        {:ok, token} -> assign(conn, :verified_token, token)
        _ -> conn
      end
    else
      with {:ok, token} <- extract_token(conn),
           {:ok, signature} <- extract_signature(conn),
           {:ok, timestamp} <- extract_timestamp(conn),
           :ok <- validate_timestamp(timestamp),
           {:ok, public_key} <- Auth.from_token(token),
           {:ok, raw_message} <- get_sign_message(conn),
           message = "#{timestamp}.#{raw_message}",
           true <- Auth.verify(public_key, message, signature),
           :ok <- verify_token_matches_key(token, public_key) do
        assign(conn, :verified_token, token)
      else
        _ ->
          conn
          |> put_status(401)
          |> Phoenix.Controller.json(%{error: "unauthorized"})
          |> halt()
      end
    end
  end

  defp extract_timestamp(conn) do
    case get_req_header(conn, "x-tb-timestamp") do
      [ts | _] -> {:ok, ts}
      _ -> :error
    end
  end

  defp validate_timestamp(timestamp_str) do
    case Integer.parse(timestamp_str) do
      {ts, ""} ->
        now = System.system_time(:second)

        if abs(now - ts) <= @max_timestamp_drift_seconds do
          :ok
        else
          :error
        end

      _ ->
        :error
    end
  end

  defp verify_token_matches_key(token, public_key) do
    if Auth.to_token(public_key) == token do
      :ok
    else
      :error
    end
  end

  defp extract_token(conn) do
    cond do
      token = conn.body_params["token"] -> {:ok, token}
      token = conn.path_params["token"] -> {:ok, token}
      token = conn.query_params["token"] -> {:ok, token}
      true -> :error
    end
  end

  defp extract_signature(conn) do
    case get_req_header(conn, "x-tb-signature") do
      [sig | _] ->
        case Base.url_decode64(sig, padding: false) do
          {:ok, decoded} -> {:ok, decoded}
          _ -> :error
        end

      _ ->
        :error
    end
  end

  # For POST: sign the raw request body (exact bytes the client sent).
  # Falls back to re-encoding body_params for test compatibility.
  # For GET: sign "METHOD /path" (e.g., "GET /api/teams/tb_ak_...")
  defp get_sign_message(conn) do
    case conn.method do
      "GET" ->
        full_path =
          if conn.query_string != "" do
            "#{conn.request_path}?#{conn.query_string}"
          else
            conn.request_path
          end

        {:ok, "GET #{full_path}"}

      _ ->
        raw = CacheBodyReader.get_raw_body(conn)

        if raw != "" do
          {:ok, raw}
        else
          # Fallback for test environment where raw body may not be cached
          {:ok, Jason.encode!(conn.body_params)}
        end
    end
  end
end
