defmodule Teamrc.Repo.Migrations.AddCheckConstraintsAndIndexes do
  use Ecto.Migration

  def change do
    # Issue #5: Add CHECK constraints for domain fields

    # teams.visibility must be 'public' or 'private'
    create constraint(:teams, :visibility_check,
      check: "visibility IN ('public', 'private')"
    )

    # token_teams.scope must be 'project' or 'global'
    create constraint(:token_teams, :scope_check,
      check: "scope IN ('project', 'global')"
    )

    # device_auth_requests.status must be 'pending' or 'confirmed'
    create constraint(:device_auth_requests, :status_check,
      check: "status IN ('pending', 'confirmed')"
    )

    # device_auth_requests.failed_attempts must be non-negative
    create constraint(:device_auth_requests, :failed_attempts_non_negative,
      check: "failed_attempts >= 0"
    )

    # Issue #6: Add index on device_auth_requests.account_id for lookup performance
    create index(:device_auth_requests, [:account_id])

    # Add index on device_auth_requests.token for rate limit queries
    create_if_not_exists index(:device_auth_requests, [:token])
  end
end
