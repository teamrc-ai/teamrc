defmodule Teamrc.Repo.Migrations.AddCreatedByToken do
  use Ecto.Migration

  def change do
    alter table(:teams) do
      add :owner_claim_secret, :string
    end
  end
end
