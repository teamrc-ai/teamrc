defmodule TeamrcWeb.UserSocketTest do
  use TeamrcWeb.ChannelCase, async: false

  alias TeamrcWeb.UserSocket

  setup do
    keypair = Teamrc.TestSigning.generate_keypair()
    %{keypair: keypair}
  end

  describe "connect/3" do
    test "valid ticket connects successfully", %{keypair: keypair} do
      ticket = generate_ticket(keypair)

      assert {:ok, socket} = connect(UserSocket, %{"ticket" => ticket})
      assert socket.assigns.token == keypair.token
    end

    test "expired ticket is rejected", %{keypair: keypair} do
      ticket = generate_expired_ticket(keypair)

      assert :error = connect(UserSocket, %{"ticket" => ticket})
    end

    test "wrong signature is rejected", %{keypair: keypair} do
      # Generate a ticket with a different key's signature
      other_keypair = Teamrc.TestSigning.generate_keypair()

      timestamp = System.system_time(:second) |> Integer.to_string()
      # Sign with the other key but use the original token
      message = "#{timestamp}.#{keypair.token}"
      signature = :crypto.sign(:eddsa, :none, message, [other_keypair.private_key, :ed25519])
      signature_b64 = Base.url_encode64(signature, padding: false)
      ticket = "#{timestamp}.#{keypair.token}.#{signature_b64}"

      assert :error = connect(UserSocket, %{"ticket" => ticket})
    end

    test "malformed ticket with missing parts is rejected" do
      assert :error = connect(UserSocket, %{"ticket" => "just-one-part"})
      assert :error = connect(UserSocket, %{"ticket" => "two.parts"})
    end

    test "missing ticket param is rejected" do
      assert :error = connect(UserSocket, %{})
      assert :error = connect(UserSocket, %{"other" => "param"})
    end

    test "ticket with invalid base64 signature is rejected", %{keypair: keypair} do
      timestamp = System.system_time(:second) |> Integer.to_string()
      ticket = "#{timestamp}.#{keypair.token}.!!!invalid-base64!!!"

      assert :error = connect(UserSocket, %{"ticket" => ticket})
    end

    test "ticket with invalid token format is rejected" do
      timestamp = System.system_time(:second) |> Integer.to_string()
      # Not a valid trc_ak_ token
      fake_sig = Base.url_encode64("fakesig", padding: false)
      ticket = "#{timestamp}.not_a_valid_token.#{fake_sig}"

      assert :error = connect(UserSocket, %{"ticket" => ticket})
    end

    test "socket id includes the token", %{keypair: keypair} do
      ticket = generate_ticket(keypair)

      {:ok, socket} = connect(UserSocket, %{"ticket" => ticket})
      assert UserSocket.id(socket) == "user_socket:#{keypair.token}"
    end
  end
end
