defmodule Teamrc.Schema.Invite do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "invites" do
    field :code, :string
    field :expires_at, :utc_datetime
    belongs_to :team, Teamrc.Schema.Team, type: :binary_id

    timestamps(type: :utc_datetime)
  end

  def changeset(invite, attrs) do
    invite
    |> cast(attrs, [:code, :expires_at, :team_id])
    |> validate_required([:code, :expires_at, :team_id])
    |> unique_constraint(:code)
  end
end
