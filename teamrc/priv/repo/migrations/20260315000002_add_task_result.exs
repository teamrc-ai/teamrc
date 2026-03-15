defmodule Teamrc.Repo.Migrations.AddTaskResult do
  use Ecto.Migration

  def change do
    alter table(:tasks) do
      add :result, :text
    end

    create constraint(:tasks, :result_length,
      check: "result IS NULL OR length(result) <= 10000"
    )
  end
end
