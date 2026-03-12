defmodule Teamrc.Accounts.MachineToken do
  @moduledoc "Schema for machine tokens (ed25519 keypair-based CLI auth)."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "machine_tokens" do
    field :token, :string
    field :machine_name, :string
    field :last_seen_at, :utc_datetime
    field :revoked_at, :utc_datetime
    belongs_to :user, Teamrc.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(machine_token, attrs) do
    machine_token
    |> cast(attrs, [:user_id, :token, :machine_name, :last_seen_at, :revoked_at])
    |> validate_required([:token])
    |> validate_length(:machine_name, max: 255)
    |> unique_constraint(:token)
  end
end
