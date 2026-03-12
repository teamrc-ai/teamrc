defmodule Teamrc.DataCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require database access.

  Provides `errors_on/1` helper for changeset validation tests.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      alias Teamrc.Repo

      import Ecto
      import Ecto.Changeset
      import Ecto.Query
      import Teamrc.DataCase
    end
  end

  setup tags do
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Teamrc.Repo)

    unless tags[:async] do
      Ecto.Adapters.SQL.Sandbox.mode(Teamrc.Repo, {:shared, self()})
    end

    :ok
  end

  @doc """
  A helper that transforms changeset errors into a map of messages.

      assert {:error, changeset} = Accounts.create_user(%{password: "short"})
      assert "should be at least 12 character(s)" in errors_on(changeset).password
      assert %{password: ["should be at least 12 character(s)"]} = errors_on(changeset)

  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
