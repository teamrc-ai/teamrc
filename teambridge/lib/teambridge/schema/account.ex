defmodule Teambridge.Schema.Account do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "accounts" do
    field :clerk_user_id, :string
    field :email, :string
    has_many :account_tokens, Teambridge.Schema.AccountToken

    timestamps(type: :utc_datetime)
  end

  def changeset(account, attrs) do
    account
    |> cast(attrs, [:clerk_user_id, :email])
    |> validate_required([:clerk_user_id])
    |> validate_length(:clerk_user_id, max: 255)
    |> validate_email()
    |> unique_constraint(:clerk_user_id)
  end

  defp validate_email(changeset) do
    case get_change(changeset, :email) do
      nil -> changeset
      _ -> validate_format(changeset, :email, ~r/^[^\s]+@[^\s]+\.[^\s]+$/)
    end
  end
end
