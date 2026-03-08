defmodule Teamrc.Repo.Migrations.AddScopeAndPlatforms do
  use Ecto.Migration

  def change do
    alter table(:token_teams) do
      add :scope, :string, default: "project"
      add :project_name, :string
      add :last_seen_at, :utc_datetime
    end

    alter table(:teams) do
      add :platforms, :jsonb, default: "[]"
    end
  end
end
