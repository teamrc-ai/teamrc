defmodule Teamrc.Repo.Migrations.AddTeamOwner do
  use Ecto.Migration

  def change do
    alter table(:teams) do
      add :owner_account_id, references(:accounts, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:teams, [:owner_account_id])
  end
end
