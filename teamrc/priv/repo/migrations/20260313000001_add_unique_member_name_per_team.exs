defmodule Teamrc.Repo.Migrations.AddUniqueMemberNamePerTeam do
  use Ecto.Migration

  def change do
    create unique_index(:members, [:team_id, :name])
  end
end
