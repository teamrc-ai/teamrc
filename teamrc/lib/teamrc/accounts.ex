defmodule Teamrc.Accounts do
  @moduledoc "Context module for account and machine token operations."

  alias Teamrc.Repo
  alias Teamrc.Schema.{Account, AccountToken, TokenTeam}
  import Ecto.Query

  def find_or_create_account(clerk_user_id, email) do
    case Repo.get_by(Account, clerk_user_id: clerk_user_id) do
      nil ->
        %Account{}
        |> Account.changeset(%{clerk_user_id: clerk_user_id, email: email})
        |> Repo.insert()

      account ->
        account
        |> Account.changeset(%{email: email})
        |> Repo.update()
    end
  end

  def link_token(account_id, token, machine_name) do
    case Repo.get_by(AccountToken, token: token) do
      nil ->
        %AccountToken{}
        |> AccountToken.changeset(%{
          account_id: account_id,
          token: token,
          machine_name: machine_name,
          last_seen_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.insert()

      existing ->
        {:ok, existing}
    end
  end

  def get_account_with_tokens(clerk_user_id) do
    Account
    |> where(clerk_user_id: ^clerk_user_id)
    |> preload(:account_tokens)
    |> Repo.one()
  end

  def get_account_teams(account_id) do
    from(t in Teamrc.Schema.Team,
      join: tt in TokenTeam,
      on: tt.team_id == t.id,
      join: at in AccountToken,
      on: at.token == tt.token,
      where: at.account_id == ^account_id and is_nil(at.revoked_at),
      distinct: true,
      preload: [:members]
    )
    |> Repo.all()
  end

  @doc "Resolve participants for a team. Returns unique list of emails or \"anonymous\"."
  def resolve_participants(team_id) do
    from(tt in TokenTeam,
      left_join: at in AccountToken,
      on: at.token == tt.token and is_nil(at.revoked_at),
      left_join: a in Account,
      on: a.id == at.account_id,
      where: tt.team_id == ^team_id,
      select: a.email
    )
    |> Repo.all()
    |> Enum.map(fn
      nil -> "anonymous"
      email -> email
    end)
    |> Enum.uniq()
  end

  def revoke_token(account_id, token) do
    case Repo.get_by(AccountToken, account_id: account_id, token: token) do
      nil ->
        {:error, :not_found}

      account_token ->
        Repo.transaction(fn ->
          account_token
          |> AccountToken.changeset(%{revoked_at: DateTime.utc_now() |> DateTime.truncate(:second)})
          |> Repo.update!()

          from(tt in TokenTeam, where: tt.token == ^token)
          |> Repo.delete_all()
        end)

        # Notify GenServer to remove token from in-memory state
        GenServer.cast(Teamrc.Teams, {:token_revoked, token})

        :ok
    end
  end

  def reassociate_teams(account_id, new_token) do
    case Repo.get_by(AccountToken, account_id: account_id, token: new_token) do
      nil ->
        {:error, :token_not_found}

      %{revoked_at: revoked} when not is_nil(revoked) ->
        {:error, :token_revoked}

      _token ->
        existing_team_ids =
          from(tt in TokenTeam,
            join: at in AccountToken,
            on: at.token == tt.token,
            where:
              at.account_id == ^account_id and at.token != ^new_token and is_nil(at.revoked_at),
            select: tt.team_id,
            distinct: true
          )
          |> Repo.all()

        current_team_ids =
          from(tt in TokenTeam,
            where: tt.token == ^new_token,
            select: tt.team_id
          )
          |> Repo.all()

        new_team_ids = existing_team_ids -- current_team_ids

        if new_team_ids != [] do
          now = DateTime.utc_now() |> DateTime.truncate(:second)

          entries =
            Enum.map(new_team_ids, fn team_id ->
              %{
                id: Ecto.UUID.generate(),
                token: new_token,
                team_id: team_id,
                inserted_at: now,
                updated_at: now
              }
            end)

          Repo.insert_all(TokenTeam, entries, on_conflict: :nothing)
        end

        {:ok, length(new_team_ids)}
    end
  end
end
