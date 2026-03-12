defmodule TeamrcWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Provides `register_and_log_in_user/1` and `log_in_user/2`
  helpers for testing authenticated routes.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint TeamrcWeb.Endpoint

      use TeamrcWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import TeamrcWeb.ConnCase
    end
  end

  setup _tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Teamrc.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Teamrc.Repo, {:shared, self()})

    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end

  @doc """
  Creates and logs in a user, returning the updated conn and user.

  Returns `%{conn: conn, user: user}`.
  """
  def register_and_log_in_user(%{conn: conn}) do
    user = Teamrc.AccountsFixtures.user_fixture()
    %{conn: log_in_user(conn, user), user: user}
  end

  @doc """
  Logs the given `user` into the `conn`.

  Returns the updated `conn`.
  """
  def log_in_user(conn, user) do
    token = Teamrc.Accounts.generate_user_session_token(user)

    conn
    |> Phoenix.ConnTest.init_test_session(%{})
    |> Plug.Conn.put_session(:user_token, token)
  end
end
