defmodule Teambridge.Schema.Team do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "teams" do
    field :name, :string
    has_many :members, Teambridge.Schema.Member
    has_many :invites, Teambridge.Schema.Invite

    timestamps(type: :utc_datetime)
  end

  def changeset(team, attrs) do
    team
    |> cast(attrs, [:name])
    |> validate_required([:name])
    |> validate_length(:name, max: 64)
    |> validate_format(:name, ~r/^[a-zA-Z0-9][a-zA-Z0-9 _-]*$/)
  end
end
