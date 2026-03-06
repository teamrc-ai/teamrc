defmodule Teamrc.Repo.Migrations.AddRulesAndSkills do
  use Ecto.Migration

  def change do
    alter table(:teams) do
      add :rules, :jsonb, default: "[]"
      add :skills, :jsonb, default: "[]"
    end

    alter table(:members) do
      add :rules, :jsonb, default: "[]"
      add :skills, :jsonb, default: "[]"
    end
  end
end
