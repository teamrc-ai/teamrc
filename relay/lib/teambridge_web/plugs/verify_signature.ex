defmodule TeambridgeWeb.Plugs.VerifySignature do
  @moduledoc """
  Plug that verifies Ed25519 request signatures for API authentication.

  Clients sign requests with their Ed25519 private key and include the
  base64url-encoded signature in the `x-tb-signature` header.

  The token (`tb_ak_<base64url(public_key)>`) is extracted from:
  - `body_params["token"]` for POST requests
  - `path_params["token"]` for GET requests

  The signed message is:
  - For POST: the JSON-encoded body params (canonical form after parsing)
  - For GET: "GET /path" (method + space + request path)

  This prevents BOLA because the token embeds the public key, and only
  the holder of the corresponding private key can produce a valid signature.
  A client cannot forge signatures for another team's token.

  ## Configuration

  Set `config :relay, :skip_auth, true` to bypass signature verification
  (used in test environment).
  """

  import Plug.Conn
  alias Teambridge.Auth

  def init(opts), do: opts

  def call(conn, _opts) do
    if Application.get_env(:relay, :skip_auth, false) do
      conn
    else
      with {:ok, token} <- extract_token(conn),
           {:ok, signature} <- extract_signature(conn),
           {:ok, public_key} <- Auth.from_token(token),
           {:ok, message} <- get_sign_message(conn),
           true <- Auth.verify(public_key, message, signature) do
        conn
      else
        _ ->
          conn
          |> put_status(401)
          |> Phoenix.Controller.json(%{error: "unauthorized"})
          |> halt()
      end
    end
  end

  defp extract_token(conn) do
    cond do
      token = conn.body_params["token"] -> {:ok, token}
      token = conn.path_params["token"] -> {:ok, token}
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

  # For POST: sign the JSON-encoded body params.
  # Note: The client must sign the same JSON string that Jason.encode! produces
  # from the parsed body params. This works because Phoenix parses the JSON body
  # into body_params, and we re-encode it deterministically. The client should
  # sign the JSON payload it sends (which must match the re-encoded form).
  #
  # For GET: sign "METHOD /path" (e.g., "GET /api/teams/tb_ak_...")
  defp get_sign_message(conn) do
    case conn.method do
      "GET" -> {:ok, "GET #{conn.request_path}"}
      _ -> {:ok, Jason.encode!(conn.body_params)}
    end
  end
end
