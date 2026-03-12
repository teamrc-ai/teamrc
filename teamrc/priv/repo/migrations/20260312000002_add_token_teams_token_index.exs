defmodule Teamrc.Repo.Migrations.AddTokenTeamsTokenIndex do
  use Ecto.Migration

  def change do
    create index(:token_teams, [:token])
  end
end
