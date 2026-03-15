defmodule Teamrc.Repo.Migrations.CreateTasks do
  use Ecto.Migration

  def change do
    create table(:tasks, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :team_id, references(:teams, type: :binary_id, on_delete: :delete_all), null: false
      add :number, :integer, null: false
      add :description, :text, null: false
      add :assignee, :string, null: false
      add :status, :string, null: false, default: "todo"
      add :created_by, :string
      add :claimed_by, :string
      add :claimed_at, :utc_datetime
      add :completed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:tasks, [:team_id, :number])
    create index(:tasks, [:team_id, :status])
    create index(:tasks, [:team_id, :assignee])

    create constraint(:tasks, :valid_status,
      check: "status IN ('todo', 'in_progress', 'done', 'cancelled', 'failed')"
    )

    create constraint(:tasks, :description_length,
      check: "length(description) <= 2000"
    )

    create constraint(:tasks, :assignee_length,
      check: "length(assignee) <= 64"
    )
  end
end
