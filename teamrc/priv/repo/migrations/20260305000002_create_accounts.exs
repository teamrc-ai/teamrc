defmodule Teamrc.Repo.Migrations.CreateAccounts do
  use Ecto.Migration

  def change do
    # Users table (phx.gen.auth + OAuth fields + ToS)
    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :string, null: false, size: 160
      add :hashed_password, :string
      add :confirmed_at, :utc_datetime

      # ToS acceptance
      add :accepted_terms_at, :utc_datetime
      add :terms_version_accepted, :string

      # OAuth provider info
      add :provider, :string
      add :provider_uid, :string, size: 255
      add :avatar_url, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:email])
    create unique_index(:users, [:provider, :provider_uid], where: "provider IS NOT NULL")

    # Session tokens (phx.gen.auth)
    create table(:users_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :token, :binary, null: false
      add :context, :string, null: false
      add :sent_to, :string
      add :authenticated_at, :utc_datetime

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:users_tokens, [:user_id])
    create unique_index(:users_tokens, [:context, :token])

    # Machine tokens (ed25519 CLI auth)
    create table(:machine_tokens, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all)
      add :token, :string, null: false, size: 255
      add :machine_name, :string, size: 255
      add :last_seen_at, :utc_datetime
      add :revoked_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:machine_tokens, [:token])
    create index(:machine_tokens, [:user_id])

    # User profiles (PII-separated)
    create table(:user_profiles, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false
      add :display_name, :string, size: 100
      add :bio, :string, size: 500

      timestamps(type: :utc_datetime)
    end

    create unique_index(:user_profiles, [:user_id])

    # Add owner_user_id to teams (replaces old owner_account_id)
    alter table(:teams) do
      add :owner_user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:teams, [:owner_user_id])
  end
end
