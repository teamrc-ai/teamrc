defmodule Teamrc.ViewToken do
  @moduledoc """
  Stateless HMAC-based view tokens for dashboard access.

  Encodes team_id + expiry into a signed token that grants viewer access
  to the team detail page without creating database records.
  """

  @separator "|"

  @doc """
  Creates a signed view token for the given team_id.

  Returns `{token, expires_at}` where token is a URL-safe base64 string.
  """
  def create(team_id, ttl_hours \\ 24) when is_binary(team_id) and is_integer(ttl_hours) do
    ttl_hours = ttl_hours |> max(1) |> min(168)
    expires_at = DateTime.utc_now() |> DateTime.add(ttl_hours * 3600)
    expires_unix = DateTime.to_unix(expires_at)

    payload = "#{team_id}#{@separator}#{expires_unix}"
    signature = :crypto.mac(:hmac, :sha256, secret(), payload)
    token = Base.url_encode64("#{payload}#{@separator}#{Base.url_encode64(signature, padding: false)}", padding: false)

    {token, expires_at}
  end

  @doc """
  Verifies a view token and returns the team_id if valid and not expired.

  Returns `{:ok, team_id}` or `:error`.
  """
  def verify(token) when is_binary(token) do
    with {:ok, decoded} <- Base.url_decode64(token, padding: false),
         [team_id, expires_str, sig_b64] <- split_payload(decoded),
         {expires_unix, ""} <- Integer.parse(expires_str),
         {:ok, expected_sig} <- Base.url_decode64(sig_b64, padding: false) do
      payload = "#{team_id}#{@separator}#{expires_unix}"
      actual_sig = :crypto.mac(:hmac, :sha256, secret(), payload)

      now = DateTime.utc_now() |> DateTime.to_unix()

      if secure_compare(actual_sig, expected_sig) and now < expires_unix do
        {:ok, team_id}
      else
        :error
      end
    else
      _ -> :error
    end
  end

  def verify(_), do: :error

  defp split_payload(decoded) do
    case String.split(decoded, @separator) do
      [team_id, expires_str, sig] -> [team_id, expires_str, sig]
      _ -> :error
    end
  end

  defp secret do
    TeamrcWeb.Endpoint.config(:secret_key_base)
    |> then(&:crypto.mac(:hmac, :sha256, &1, "view_token_v1"))
  end

  defp secure_compare(a, b) when byte_size(a) == byte_size(b) do
    :crypto.hash_equals(a, b)
  end

  defp secure_compare(_, _), do: false
end
