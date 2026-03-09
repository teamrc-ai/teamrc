defmodule Teamrc.Repo.Migrations.AddKnowledgeToTeams do
  use Ecto.Migration

  def change do
    alter table(:teams) do
      add :knowledge, :text
    end
  end
end
