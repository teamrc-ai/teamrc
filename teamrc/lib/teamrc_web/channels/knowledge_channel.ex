defmodule TeamrcWeb.KnowledgeChannel do
  @moduledoc """
  Channel for real-time knowledge sync between CLI daemons.

  Topic: `knowledge:<team_id>`

  Handles:
  - `knowledge:push`  --  merge incoming knowledge, persist, broadcast to other clients
  - PubSub messages from REST-initiated knowledge changes

  Rate limited to 1 push per second per token (via ETS, not per-socket).
  """

  use Phoenix.Channel

  require Logger

  alias Teamrc.Teams

  @knowledge_cap 100_000
  @rate_limit_ms 1_000

  @impl true
  def join("knowledge:" <> team_id, _params, socket) do
    token = socket.assigns.token

    case Teams.get_team_hashes(token, team_id) do
      {:ok, hashes} ->
        # Subscribe to PubSub for REST-initiated knowledge changes
        Phoenix.PubSub.subscribe(Teamrc.PubSub, "team_knowledge:#{team_id}")

        socket = assign(socket, :team_id, team_id)

        {:ok,
         %{
           knowledge_hash: hashes["knowledge_hash"],
           knowledge_size: knowledge_size(token, team_id),
           knowledge_cap: @knowledge_cap
         }, socket}

      :error ->
        {:error, %{reason: "not_found"}}

      {:error, :team_id_required} ->
        {:error, %{reason: "team_id_required"}}
    end
  end

  @impl true
  def handle_in("knowledge:push", %{"content" => content}, socket) when is_binary(content) do
    token = socket.assigns.token

    case Teamrc.ChannelRateLimiter.check_rate(token, @rate_limit_ms) do
      :rate_limited ->
        {:reply, {:error, %{reason: "rate_limited"}}, socket}

      :ok ->
        team_id = socket.assigns.team_id

        case Teams.update_knowledge(team_id, token, content) do
          {:ok, merged, knowledge_hash, knowledge_size} ->
            # Broadcast to other clients on this channel (not the sender)
            broadcast_from!(socket, "knowledge:updated", %{
              content: merged,
              knowledge_hash: knowledge_hash,
              knowledge_size: knowledge_size
            })

            {:reply, {:ok, %{knowledge_hash: knowledge_hash, knowledge_size: knowledge_size}},
             socket}

          {:error, reason} ->
            {:reply, {:error, %{reason: to_string(reason)}}, socket}
        end
    end
  end

  def handle_in("knowledge:push", _payload, socket) do
    {:reply, {:error, %{reason: "missing content"}}, socket}
  end

  @impl true
  def handle_info(
        {:knowledge_updated,
         %{content: content, knowledge_hash: hash, knowledge_size: size, source_token: source_token}},
        socket
      ) do
    # Don't echo back to the source token that initiated the change
    if source_token != socket.assigns.token do
      push(socket, "knowledge:updated", %{
        content: content,
        knowledge_hash: hash,
        knowledge_size: size
      })
    end

    {:noreply, socket}
  end

  # Ignore unexpected PubSub messages
  def handle_info(_msg, socket), do: {:noreply, socket}

  # --- Private helpers ---

  defp knowledge_size(token, team_id) do
    case Teams.get_team(token, team_id) do
      {:ok, team} ->
        case team["knowledge"] do
          nil -> 0
          k when is_binary(k) -> byte_size(k)
        end

      _ ->
        0
    end
  end
end
