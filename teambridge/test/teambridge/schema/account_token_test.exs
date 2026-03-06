defmodule Teambridge.Schema.AccountTokenTest do
  use ExUnit.Case, async: true

  alias Teambridge.Schema.AccountToken

  describe "changeset/2" do
    test "valid with required fields" do
      changeset = AccountToken.changeset(%AccountToken{}, %{
        account_id: Ecto.UUID.generate(),
        token: "tb_ak_testtoken123"
      })
      assert changeset.valid?
    end

    test "valid with all fields" do
      changeset = AccountToken.changeset(%AccountToken{}, %{
        account_id: Ecto.UUID.generate(),
        token: "tb_ak_testtoken123",
        machine_name: "bens-macbook"
      })
      assert changeset.valid?
    end

    test "invalid without account_id" do
      changeset = AccountToken.changeset(%AccountToken{}, %{token: "tb_ak_testtoken123"})
      refute changeset.valid?
      assert %{account_id: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid without token" do
      changeset = AccountToken.changeset(%AccountToken{}, %{account_id: Ecto.UUID.generate()})
      refute changeset.valid?
      assert %{token: ["can't be blank"]} = errors_on(changeset)
    end

    test "invalid with machine_name too long" do
      changeset = AccountToken.changeset(%AccountToken{}, %{
        account_id: Ecto.UUID.generate(),
        token: "tb_ak_testtoken123",
        machine_name: String.duplicate("a", 256)
      })
      refute changeset.valid?
      assert %{machine_name: [_]} = errors_on(changeset)
    end
  end

  describe "revoked?/1" do
    test "returns false when revoked_at is nil" do
      refute AccountToken.revoked?(%AccountToken{revoked_at: nil})
    end

    test "returns true when revoked_at is set" do
      assert AccountToken.revoked?(%AccountToken{revoked_at: ~U[2026-03-07 00:00:00Z]})
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
