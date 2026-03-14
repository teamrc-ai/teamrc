defmodule TeamrcWeb.KnowledgeChannelTest do
  use TeamrcWeb.ChannelCase, async: false

  alias TeamrcWeb.{UserSocket, KnowledgeChannel}

  setup do
    keypair = Teamrc.TestSigning.generate_keypair()
    ticket = generate_ticket(keypair)
    {:ok, socket} = connect(UserSocket, %{"ticket" => ticket})

    team_id = create_team_for_token(keypair.token, knowledge: "initial knowledge")

    %{socket: socket, keypair: keypair, team_id: team_id}
  end

  describe "join/3" do
    test "join with valid token and team_id succeeds", %{socket: socket, team_id: team_id} do
      assert {:ok, reply, _socket} = subscribe_and_join(socket, KnowledgeChannel, "knowledge:#{team_id}")

      assert is_binary(reply.knowledge_hash)
      assert is_integer(reply.knowledge_size)
      assert reply.knowledge_cap == 100_000
    end

    test "join with token that has no access to team is rejected", %{team_id: _team_id} do
      # Create a different keypair with no team access
      other_keypair = Teamrc.TestSigning.generate_keypair()
      other_ticket = generate_ticket(other_keypair)
      {:ok, other_socket} = connect(UserSocket, %{"ticket" => other_ticket})

      assert {:error, %{reason: "not_found"}} =
               subscribe_and_join(other_socket, KnowledgeChannel, "knowledge:#{Ecto.UUID.generate()}")
    end

    test "join with non-existent team_id is rejected", %{socket: socket} do
      assert {:error, %{reason: "not_found"}} =
               subscribe_and_join(socket, KnowledgeChannel, "knowledge:#{Ecto.UUID.generate()}")
    end
  end

  describe "handle_in knowledge:push" do
    test "push with content merges, broadcasts, and returns hash/size", %{
      socket: socket,
      team_id: team_id
    } do
      {:ok, _reply, socket} = subscribe_and_join(socket, KnowledgeChannel, "knowledge:#{team_id}")

      ref = push(socket, "knowledge:push", %{"content" => "new finding"})
      assert_reply ref, :ok, reply

      assert is_binary(reply.knowledge_hash)
      assert is_integer(reply.knowledge_size)
      assert reply.knowledge_size > 0

      # Verify the broadcast was sent to other clients
      assert_broadcast "knowledge:updated", %{
        content: content,
        knowledge_hash: _hash,
        knowledge_size: _size
      }

      assert content =~ "initial knowledge"
      assert content =~ "new finding"
    end

    test "push with oversized content triggers prune and still succeeds", %{
      keypair: keypair
    } do
      # Create a team with existing knowledge that's already near the cap (~60KB)
      existing_sections =
        for i <- 1..100 do
          "## Existing #{i}\n#{String.duplicate("a", 550)}\n"
        end

      existing_knowledge = "# Preamble\n\n" <> Enum.join(existing_sections, "\n")
      assert byte_size(existing_knowledge) > 50_000
      assert byte_size(existing_knowledge) < 100_000

      team_id = create_team_for_token(keypair.token, knowledge: existing_knowledge)

      ticket = generate_ticket(keypair)
      {:ok, socket} = connect(UserSocket, %{"ticket" => ticket})
      {:ok, _reply, socket} = subscribe_and_join(socket, KnowledgeChannel, "knowledge:#{team_id}")

      # Push new content that's under 100KB individually, but merged total exceeds 100KB
      new_sections =
        for i <- 1..100 do
          "## New #{i}\n#{String.duplicate("b", 550)}\n"
        end

      new_content = Enum.join(new_sections, "\n")
      assert byte_size(new_content) < 100_000

      ref = push(socket, "knowledge:push", %{"content" => new_content})
      assert_reply ref, :ok, reply

      # After pruning, size should be within the cap
      assert reply.knowledge_size <= 100_000
      assert reply.knowledge_size > 0
    end

    test "push rate limiting rejects second push within 1 second", %{
      socket: socket,
      team_id: team_id
    } do
      {:ok, _reply, socket} = subscribe_and_join(socket, KnowledgeChannel, "knowledge:#{team_id}")

      ref1 = push(socket, "knowledge:push", %{"content" => "first push"})
      assert_reply ref1, :ok, _reply1

      # Immediately push again (within 1 second)
      ref2 = push(socket, "knowledge:push", %{"content" => "second push"})
      assert_reply ref2, :error, %{reason: "rate_limited"}
    end

    test "push with missing content returns error", %{socket: socket, team_id: team_id} do
      {:ok, _reply, socket} = subscribe_and_join(socket, KnowledgeChannel, "knowledge:#{team_id}")

      ref = push(socket, "knowledge:push", %{"other" => "data"})
      assert_reply ref, :error, %{reason: "missing content"}
    end

    test "push with non-binary content (number) returns error", %{socket: socket, team_id: team_id} do
      {:ok, _reply, socket} = subscribe_and_join(socket, KnowledgeChannel, "knowledge:#{team_id}")

      ref = push(socket, "knowledge:push", %{"content" => 42})
      assert_reply ref, :error, %{reason: "missing content"}
    end

    test "push with non-binary content (map) returns error", %{socket: socket, team_id: team_id} do
      {:ok, _reply, socket} = subscribe_and_join(socket, KnowledgeChannel, "knowledge:#{team_id}")

      ref = push(socket, "knowledge:push", %{"content" => %{"nested" => "data"}})
      assert_reply ref, :error, %{reason: "missing content"}
    end

    test "push with non-binary content (list) returns error", %{socket: socket, team_id: team_id} do
      {:ok, _reply, socket} = subscribe_and_join(socket, KnowledgeChannel, "knowledge:#{team_id}")

      ref = push(socket, "knowledge:push", %{"content" => ["a", "b"]})
      assert_reply ref, :error, %{reason: "missing content"}
    end
  end

  describe "PubSub from REST" do
    test "REST-initiated knowledge update is forwarded to connected client", %{
      socket: socket,
      team_id: team_id
    } do
      {:ok, _reply, _socket} =
        subscribe_and_join(socket, KnowledgeChannel, "knowledge:#{team_id}")

      # Simulate a REST-initiated knowledge update from a different token
      Phoenix.PubSub.broadcast(
        Teamrc.PubSub,
        "team_knowledge:#{team_id}",
        {:knowledge_updated,
         %{
           content: "rest-updated knowledge",
           knowledge_hash: "abc123",
           knowledge_size: 22,
           source_token: "trc_ak_different_token"
         }}
      )

      # The client should receive the update since source_token differs
      assert_push "knowledge:updated", %{
        content: "rest-updated knowledge",
        knowledge_hash: "abc123",
        knowledge_size: 22
      }
    end

    test "PubSub message from same token is not echoed back", %{
      socket: socket,
      team_id: team_id,
      keypair: keypair
    } do
      {:ok, _reply, _socket} =
        subscribe_and_join(socket, KnowledgeChannel, "knowledge:#{team_id}")

      # Simulate a PubSub message with the same source token
      Phoenix.PubSub.broadcast(
        Teamrc.PubSub,
        "team_knowledge:#{team_id}",
        {:knowledge_updated,
         %{
           content: "my own update",
           knowledge_hash: "abc123",
           knowledge_size: 14,
           source_token: keypair.token
         }}
      )

      # Should NOT receive the push since source_token matches
      refute_push "knowledge:updated", _
    end
  end
end
