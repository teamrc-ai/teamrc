defmodule Teamrc.Repo.Migrations.CreateTeams do
  use Ecto.Migration

  def change do
    create table(:teams, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :skills, :jsonb, default: "[]"
      add :platforms, :jsonb, default: "[]"
      add :knowledge, :text
      add :visibility, :string, null: false, default: "private"
      add :clone_token, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:teams, [:clone_token], where: "clone_token IS NOT NULL")

    create table(:members, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :role, :string, null: false, default: ""
      add :soul, :text
      add :skills, :jsonb, default: "[]"
      add :team_id, references(:teams, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create index(:members, [:team_id])

    create table(:invites, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :code, :string, null: false
      add :expires_at, :utc_datetime, null: false
      add :team_id, references(:teams, type: :binary_id, on_delete: :delete_all), null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:invites, [:code])
    create index(:invites, [:team_id])

    create table(:token_teams, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :token, :string, null: false
      add :team_id, references(:teams, type: :binary_id, on_delete: :delete_all), null: false
      add :scope, :string, default: "project"
      add :project_name, :string
      add :last_seen_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:token_teams, [:token, :team_id])
    create index(:token_teams, [:team_id])
  end
end
