defmodule TeamrcWeb.UserSocket do
  @moduledoc """
  Socket for CLI daemon connections authenticated via Ed25519 signed tickets.

  Ticket format: `<timestamp>.<token>.<signature>`
  - `timestamp`: Unix epoch seconds (must be within 30s of server time)
  - `token`: `trc_ak_<base64url(pubkey)>` machine token
  - `signature`: Ed25519 signature of `<timestamp>.<token>`, base64url-encoded

  Reuses the same Ed25519 auth infrastructure as the REST API's VerifySignature plug.
  """

  use Phoenix.Socket

  channel "knowledge:*", TeamrcWeb.KnowledgeChannel
  channel "tasks:*", TeamrcWeb.TasksChannel

  @max_ticket_age_seconds 30

  @impl true
  def connect(%{"ticket" => ticket}, socket, _connect_info) do
    with {:ok, timestamp, token, signature} <- parse_ticket(ticket),
         :ok <- validate_timestamp(timestamp),
         {:ok, public_key} <- Teamrc.Auth.from_token(token),
         message = "#{timestamp}.#{token}",
         true <- Teamrc.Auth.verify(public_key, message, signature),
         :ok <- verify_token_matches_key(token, public_key) do
      {:ok, assign(socket, :token, token)}
    else
      _ -> :error
    end
  end

  def connect(_params, _socket, _connect_info), do: :error

  @impl true
  def id(socket), do: "user_socket:#{socket.assigns.token}"

  # --- Private helpers ---

  defp parse_ticket(ticket) when is_binary(ticket) do
    case String.split(ticket, ".", parts: 3) do
      [timestamp, token, signature_b64] ->
        case Base.url_decode64(signature_b64, padding: false) do
          {:ok, signature} -> {:ok, timestamp, token, signature}
          :error -> :error
        end

      _ ->
        :error
    end
  end

  defp parse_ticket(_), do: :error

  defp validate_timestamp(timestamp_str) do
    case Integer.parse(timestamp_str) do
      {ts, ""} ->
        now = System.system_time(:second)

        if abs(now - ts) <= @max_ticket_age_seconds do
          :ok
        else
          :error
        end

      _ ->
        :error
    end
  end

  defp verify_token_matches_key(token, public_key) do
    if Teamrc.Auth.to_token(public_key) == token do
      :ok
    else
      :error
    end
  end
end
