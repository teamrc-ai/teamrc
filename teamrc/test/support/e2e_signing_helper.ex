defmodule Teamrc.TestSigning do
  @moduledoc """
  Reusable Ed25519 signing helper for Elixir-side tests.

  Generates keypairs, tokens, and signed requests using the same
  algorithm as the CLI (for cross-verification in tests).
  """

  @doc "Generate a fresh Ed25519 keypair and derive the trc_ak_ token."
  def generate_keypair do
    {public_key, private_key} = :crypto.generate_key(:eddsa, :ed25519)

    token =
      "trc_ak_" <>
        Base.url_encode64(public_key, padding: false)

    %{public_key: public_key, private_key: private_key, token: token}
  end

  @doc "Sign a POST body with the given private key. Returns {signature_b64, timestamp}."
  def sign_post(body, private_key) when is_binary(body) do
    timestamp = System.system_time(:second) |> Integer.to_string()
    message = "#{timestamp}.#{body}"
    signature = :crypto.sign(:eddsa, :none, message, [private_key, :ed25519])
    signature_b64 = Base.url_encode64(signature, padding: false)
    {signature_b64, timestamp}
  end

  @doc "Sign a GET/DELETE request path. Returns {signature_b64, timestamp}."
  def sign_request(method, path, private_key) when method in ["GET", "DELETE"] do
    timestamp = System.system_time(:second) |> Integer.to_string()
    message = "#{timestamp}.#{method} #{path}"
    signature = :crypto.sign(:eddsa, :none, message, [private_key, :ed25519])
    signature_b64 = Base.url_encode64(signature, padding: false)
    {signature_b64, timestamp}
  end
end
