defmodule Teambridge.Repo.Migrations.CreateTokenTeams do
  use Ecto.Migration

  def change do
    create table(:token_teams, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :token, :string, null: false
      add :team_id, references(:teams, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:token_teams, [:token])
    create index(:token_teams, [:team_id])
  end
end
