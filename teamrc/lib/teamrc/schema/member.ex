defmodule Teamrc.Schema.Member do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "members" do
    field :name, :string
    field :role, :string
    field :soul, :string
    field :rules, {:array, :string}, default: []
    field :skills, {:array, :string}, default: []
    belongs_to :team, Teamrc.Schema.Team, type: :binary_id

    timestamps(type: :utc_datetime)
  end

  def changeset(member, attrs) do
    member
    |> cast(attrs, [:name, :role, :soul, :rules, :skills])
    |> validate_required([:name])
    |> validate_length(:name, max: 64)
  end
end
