defmodule Teambridge.Schema.AccountTest do
  use ExUnit.Case, async: true

  alias Teambridge.Schema.Account

  describe "changeset/2" do
    test "valid with required fields" do
      changeset = Account.changeset(%Account{}, %{clerk_user_id: "user_abc123"})
      assert changeset.valid?
    end

    test "valid with email" do
      changeset = Account.changeset(%Account{}, %{clerk_user_id: "user_abc123", email: "dev@example.com"})
      assert changeset.valid?
    end

    test "invalid without clerk_user_id" do
      changeset = Account.changeset(%Account{}, %{})
      refute changeset.valid?
      assert %{clerk_user_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid with bad email format" do
      changeset = Account.changeset(%Account{}, %{clerk_user_id: "user_abc123", email: "not-an-email"})
      refute changeset.valid?
      assert %{email: ["has invalid format"]} = errors_on(changeset)
    end

    test "valid with nil email" do
      changeset = Account.changeset(%Account{}, %{clerk_user_id: "user_abc123", email: nil})
      assert changeset.valid?
    end
  end

  defp errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
