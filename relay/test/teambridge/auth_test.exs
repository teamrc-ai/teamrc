defmodule Teambridge.AuthTest do
  use ExUnit.Case, async: true

  alias Teambridge.Auth

  setup do
    {pub, priv} = :crypto.generate_key(:eddsa, :ed25519)
    %{pub: pub, priv: priv}
  end

  describe "verify/3" do
    test "returns true for valid signature", %{pub: pub, priv: priv} do
      message = "hello world"
      signature = :crypto.sign(:eddsa, :none, message, [priv, :ed25519])
      assert Auth.verify(pub, message, signature) == true
    end

    test "returns false for invalid signature", %{pub: pub} do
      message = "hello world"
      bad_signature = :crypto.strong_rand_bytes(64)
      assert Auth.verify(pub, message, bad_signature) == false
    end

    test "returns false for tampered message", %{pub: pub, priv: priv} do
      message = "hello world"
      signature = :crypto.sign(:eddsa, :none, message, [priv, :ed25519])
      assert Auth.verify(pub, "tampered", signature) == false
    end
  end

  describe "to_token/1" do
    test "creates a token with tb_ak_ prefix", %{pub: pub} do
      token = Auth.to_token(pub)
      assert String.starts_with?(token, "tb_ak_")
    end

    test "token is deterministic for same key", %{pub: pub} do
      assert Auth.to_token(pub) == Auth.to_token(pub)
    end
  end

  describe "from_token/1" do
    test "round-trips with to_token", %{pub: pub} do
      token = Auth.to_token(pub)
      assert {:ok, ^pub} = Auth.from_token(token)
    end

    test "returns error for invalid token" do
      assert {:error, :invalid_token} = Auth.from_token("bad_token")
    end

    test "returns error for wrong prefix" do
      assert {:error, :invalid_token} = Auth.from_token("wrong_" <> Base.url_encode64(<<1, 2, 3>>, padding: false))
    end

    test "returns error for invalid base64 in token" do
      assert {:error, :invalid_token} = Auth.from_token("tb_ak_!!!invalid!!!")
    end
  end

  describe "verify edge cases" do
    test "verify with wrong message returns false", %{pub: pub, priv: priv} do
      signature = :crypto.sign(:eddsa, :none, "correct message", [priv, :ed25519])
      assert Auth.verify(pub, "wrong message", signature) == false
    end

    test "verify with wrong key returns false", %{priv: priv} do
      {pub2, _priv2} = :crypto.generate_key(:eddsa, :ed25519)
      signature = :crypto.sign(:eddsa, :none, "test", [priv, :ed25519])
      assert Auth.verify(pub2, "test", signature) == false
    end
  end
end
