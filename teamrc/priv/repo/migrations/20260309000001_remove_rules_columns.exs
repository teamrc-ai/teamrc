defmodule Teamrc.Repo.Migrations.RemoveRulesColumns do
  use Ecto.Migration

  def change do
    alter table(:teams) do
      remove :rules, :jsonb, default: "[]"
    end

    alter table(:members) do
      remove :rules, :jsonb, default: "[]"
    end
  end
end
