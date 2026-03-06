defmodule Teamrc.Schema.TokenTeam do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "token_teams" do
    field :token, :string
    belongs_to :team, Teamrc.Schema.Team, type: :binary_id

    timestamps(type: :utc_datetime)
  end

  def changeset(token_team, attrs) do
    token_team
    |> cast(attrs, [:token, :team_id])
    |> validate_required([:token, :team_id])
    |> unique_constraint(:token)
  end
end
