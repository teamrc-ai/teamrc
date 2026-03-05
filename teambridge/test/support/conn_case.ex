defmodule TeambridgeWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint TeambridgeWeb.Endpoint

      use TeambridgeWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import TeambridgeWeb.ConnCase
    end
  end

  setup _tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Teambridge.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Teambridge.Repo, {:shared, self()})

    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
