defmodule Teamrc.Schema.Member do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "members" do
    field :name, :string
    field :role, :string
    field :soul, :string
    field :skills, {:array, :string}, default: []
    belongs_to :team, Teamrc.Schema.Team, type: :binary_id

    timestamps(type: :utc_datetime)
  end

  def changeset(member, attrs) do
    member
    |> cast(attrs, [:name, :role, :soul, :skills])
    |> validate_required([:name, :role])
    |> validate_length(:name, max: 64)
    |> validate_length(:role, min: 1, max: 256)
    |> validate_length(:soul, max: 10_000)
    |> unique_constraint(:name, name: "members_team_id_name_index")
  end
end
