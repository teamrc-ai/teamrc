defmodule Teamrc.Auth do
  @prefix "trc_ak_"

  @doc "Verify an Ed25519 signature."
  def verify(public_key, message, signature) do
    :crypto.verify(:eddsa, :none, message, signature, [public_key, :ed25519])
  rescue
    _ -> false
  end

  @doc "Convert a public key to a token string."
  def to_token(public_key) do
    @prefix <> Base.url_encode64(public_key, padding: false)
  end

  @doc "Convert a token string back to a public key."
  def from_token(@prefix <> encoded) do
    case Base.url_decode64(encoded, padding: false) do
      {:ok, key} -> {:ok, key}
      :error -> {:error, :invalid_token}
    end
  end

  def from_token(_), do: {:error, :invalid_token}
end
