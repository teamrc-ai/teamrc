defmodule Teamrc.Repo.Migrations.AddMemberDescription do
  use Ecto.Migration

  def change do
    alter table(:members) do
      add :description, :text
    end
  end
end
