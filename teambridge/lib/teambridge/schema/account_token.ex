defmodule Teambridge.Schema.AccountToken do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "account_tokens" do
    field :token, :string
    field :machine_name, :string
    field :last_seen_at, :utc_datetime
    field :revoked_at, :utc_datetime
    belongs_to :account, Teambridge.Schema.Account, type: :binary_id

    timestamps(type: :utc_datetime)
  end

  def changeset(account_token, attrs) do
    account_token
    |> cast(attrs, [:account_id, :token, :machine_name, :last_seen_at, :revoked_at])
    |> validate_required([:account_id, :token])
    |> validate_length(:machine_name, max: 255)
    |> unique_constraint(:token)
  end

  @doc "Returns true if the token has been revoked."
  def revoked?(%__MODULE__{revoked_at: nil}), do: false
  def revoked?(%__MODULE__{revoked_at: _}), do: true
end
