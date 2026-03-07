defmodule Teamrc.Repo.Migrations.FixTokenTeamsAndMembers do
  use Ecto.Migration

  def change do
    # Q9: Allow a token to belong to multiple teams
    # Drop old single-column unique index and replace with composite
    drop_if_exists unique_index(:token_teams, [:token])
    create unique_index(:token_teams, [:token, :team_id])

    # Q13: Ensure role is always present on members
    alter table(:members) do
      modify :role, :string, null: false, default: ""
    end
  end
end
