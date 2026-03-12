defmodule Teamrc.Repo.Migrations.CreateDeviceAuthRequests do
  use Ecto.Migration

  def change do
    create table(:device_auth_requests, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_code, :string, null: false
      add :device_code, :string, null: false
      add :token, :string, null: false
      add :status, :string, null: false, default: "pending"
      add :expires_at, :utc_datetime, null: false
      add :account_id, :binary_id
      add :email, :string
      add :failed_attempts, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:device_auth_requests, [:user_code])
    create unique_index(:device_auth_requests, [:device_code])
    create index(:device_auth_requests, [:token])
    create index(:device_auth_requests, [:expires_at])
  end
end
