defmodule TeamrcWeb.ChannelCase do
  @moduledoc """
  This module defines the test case to be used by channel tests.

  Provides helpers for connecting sockets and joining channels
  with Ed25519 ticket authentication.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import Phoenix.ChannelTest
      import TeamrcWeb.ChannelCase

      @endpoint TeamrcWeb.Endpoint
    end
  end

  setup _tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Teamrc.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Teamrc.Repo, {:shared, self()})

    # Clear channel rate limiter state between tests
    if :ets.whereis(:teamrc_channel_rate_limits) != :undefined do
      :ets.delete_all_objects(:teamrc_channel_rate_limits)
    end

    :ok
  end

  @doc """
  Generate a valid ticket for socket connection using a keypair.

  Returns the ticket string in the format `<timestamp>.<token>.<signature>`.
  """
  def generate_ticket(%{token: token, private_key: private_key}) do
    timestamp = System.system_time(:second) |> Integer.to_string()
    message = "#{timestamp}.#{token}"
    signature = :crypto.sign(:eddsa, :none, message, [private_key, :ed25519])
    signature_b64 = Base.url_encode64(signature, padding: false)
    "#{timestamp}.#{token}.#{signature_b64}"
  end

  @doc """
  Generate an expired ticket (timestamp 120 seconds in the past).
  """
  def generate_expired_ticket(%{token: token, private_key: private_key}) do
    timestamp = (System.system_time(:second) - 120) |> Integer.to_string()
    message = "#{timestamp}.#{token}"
    signature = :crypto.sign(:eddsa, :none, message, [private_key, :ed25519])
    signature_b64 = Base.url_encode64(signature, padding: false)
    "#{timestamp}.#{token}.#{signature_b64}"
  end

  @doc """
  Create a team and associate it with a token. Returns the team_id.
  """
  def create_team_for_token(token, opts \\ []) do
    name = Keyword.get(opts, :name, "test-team-#{:erlang.unique_integer([:positive])}")
    knowledge = Keyword.get(opts, :knowledge, nil)

    team_attrs = %{
      "name" => name,
      "members" => [],
      "knowledge" => knowledge
    }

    {:ok, team_data} = Teamrc.Teams.put_team(token, team_attrs)
    team_data["id"]
  end
end
