defmodule Teamrc.Repo.Migrations.CreateAccounts do
  use Ecto.Migration

  def change do
    create table(:accounts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :clerk_user_id, :string, null: false, size: 255
      add :email, :string, size: 255

      timestamps(type: :utc_datetime)
    end

    create unique_index(:accounts, [:clerk_user_id])

    create table(:account_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :account_id, references(:accounts, type: :binary_id, on_delete: :delete_all), null: false
      add :token, :string, null: false, size: 255
      add :machine_name, :string, size: 255
      add :last_seen_at, :utc_datetime
      add :revoked_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:account_tokens, [:account_id])
    create unique_index(:account_tokens, [:token])

    alter table(:teams) do
      add :owner_account_id, references(:accounts, type: :binary_id), null: true
    end
  end
end
