defmodule Teamrc.Schema.TokenTeam do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "token_teams" do
    field :token, :string
    field :scope, :string, default: "project"
    field :project_name, :string
    field :last_seen_at, :utc_datetime
    belongs_to :team, Teamrc.Schema.Team, type: :binary_id

    timestamps(type: :utc_datetime)
  end

  def changeset(token_team, attrs) do
    token_team
    |> cast(attrs, [:token, :team_id, :scope, :project_name, :last_seen_at])
    |> validate_required([:token, :team_id])
    |> validate_inclusion(:scope, ["project", "global"])
    |> check_constraint(:scope, name: :scope_check, message: "must be 'project' or 'global'")
    |> unique_constraint([:token, :team_id])
  end
end
