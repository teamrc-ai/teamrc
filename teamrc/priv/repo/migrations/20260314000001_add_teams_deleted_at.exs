defmodule Teamrc.Repo.Migrations.AddTeamsDeletedAt do
  use Ecto.Migration

  def change do
    alter table(:teams) do
      add :deleted_at, :utc_datetime
    end

    create index(:teams, [:deleted_at], where: "deleted_at IS NOT NULL")
  end
end
