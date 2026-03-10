defmodule Teamrc.Accounts do
  @moduledoc "Context module for account and machine token operations."

  alias Teamrc.Repo
  alias Teamrc.Schema.{Account, AccountToken, TokenTeam}
  import Ecto.Query

  def find_or_create_account(clerk_user_id, email) do
    %Account{}
    |> Account.changeset(%{clerk_user_id: clerk_user_id, email: email})
    |> Repo.insert(
      on_conflict: {:replace, [:email, :updated_at]},
      conflict_target: :clerk_user_id,
      returning: true
    )
  end

  def link_token(account_id, token, machine_name) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case Repo.get_by(AccountToken, token: token) do
      nil ->
        %AccountToken{}
        |> AccountToken.changeset(%{
          account_id: account_id,
          token: token,
          machine_name: machine_name,
          last_seen_at: now
        })
        |> Repo.insert()

      existing ->
        existing
        |> AccountToken.changeset(%{
          machine_name: machine_name || existing.machine_name,
          last_seen_at: now
        })
        |> Repo.update()
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

  @doc "Get teams with machine details for the dashboard. Returns [{team, machines}]."
  def get_account_teams_with_machines(account_id) do
    # Get all active tokens for this account
    active_tokens =
      from(at in AccountToken,
        where: at.account_id == ^account_id and is_nil(at.revoked_at),
        select: at
      )
      |> Repo.all()

    token_strings = Enum.map(active_tokens, & &1.token)

    if token_strings == [] do
      []
    else
      # Get all token_team associations for these tokens
      token_teams =
        from(tt in TokenTeam,
          where: tt.token in ^token_strings,
          preload: [team: :members]
        )
        |> Repo.all()

      # Build a lookup from token -> machine info
      token_to_machine = Map.new(active_tokens, fn at ->
        {at.token, %{
          token: at.token,
          machine_name: at.machine_name,
          last_seen_at: at.last_seen_at
        }}
      end)

      # Group by team, collect machines for each team
      token_teams
      |> Enum.group_by(& &1.team_id)
      |> Enum.map(fn {_team_id, tts} ->
        team = hd(tts).team
        machines = Enum.map(tts, fn tt ->
          machine = Map.get(token_to_machine, tt.token, %{token: tt.token, machine_name: nil, last_seen_at: nil})
          Map.merge(machine, %{
            scope: tt.scope || "project",
            project_name: tt.project_name,
            tt_last_seen_at: tt.last_seen_at
          })
        end)
        |> Enum.uniq_by(& &1.token)
        {team, machines}
      end)
    end
  end

  @doc "Check if a Clerk user has a machine token associated with a team."
  def is_team_participant?(nil, _team_id), do: false

  def is_team_participant?(clerk_user_id, team_id) do
    account = get_account_with_tokens(clerk_user_id)

    if account do
      tokens =
        account.account_tokens
        |> Enum.reject(& &1.revoked_at)
        |> Enum.map(& &1.token)

      if tokens == [] do
        false
      else
        from(tt in TokenTeam,
          where: tt.team_id == ^team_id and tt.token in ^tokens,
          select: tt.token,
          limit: 1
        )
        |> Repo.one()
        |> is_binary()
      end
    else
      false
    end
  end

  @doc "Resolve participants for a single team."
  def resolve_participants(team_id) do
    Map.get(resolve_participants_batch([team_id]), team_id, [])
  end

  @doc "Resolve participants for multiple teams in a single query. Returns %{team_id => [emails]}."
  def resolve_participants_batch(team_ids) when is_list(team_ids) do
    if team_ids == [] do
      %{}
    else
      from(tt in TokenTeam,
        left_join: at in AccountToken,
        on: at.token == tt.token and is_nil(at.revoked_at),
        left_join: a in Account,
        on: a.id == at.account_id,
        where: tt.team_id in ^team_ids,
        select: {tt.team_id, a.email}
      )
      |> Repo.all()
      |> Enum.group_by(fn {team_id, _} -> team_id end, fn {_, email} -> email || "anonymous" end)
      |> Map.new(fn {team_id, emails} -> {team_id, Enum.uniq(emails)} end)
    end
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

        :ok
    end
  end

  @doc "Delete an account and all associated data (tokens, token_teams). Teams themselves are preserved."
  def delete_account(clerk_user_id) do
    case get_account_with_tokens(clerk_user_id) do
      nil ->
        {:error, :not_found}

      account ->
        all_tokens = Enum.map(account.account_tokens, & &1.token)

        Repo.transaction(fn ->
          # Delete token_team associations for all tokens (including revoked)
          if all_tokens != [] do
            from(tt in TokenTeam, where: tt.token in ^all_tokens)
            |> Repo.delete_all()
          end

          # Delete the account (cascades to account_tokens via FK)
          Repo.delete!(account)
        end)
        |> case do
          {:ok, _} ->
            :ok

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc "Export all data associated with a Clerk account as a map."
  def export_account_data(clerk_user_id) do
    case get_account_with_tokens(clerk_user_id) do
      nil ->
        {:error, :not_found}

      account ->
        teams_with_machines = get_account_teams_with_machines(account.id)
        team_ids = Enum.map(teams_with_machines, fn {team, _} -> team.id end)
        participants = resolve_participants_batch(team_ids)

        {:ok, %{
          account: %{
            id: account.id,
            email: account.email,
            created_at: account.inserted_at,
            updated_at: account.updated_at
          },
          machines: Enum.map(account.account_tokens, fn at ->
            %{
              token: at.token,
              machine_name: at.machine_name,
              last_seen_at: at.last_seen_at,
              revoked_at: at.revoked_at,
              created_at: at.inserted_at
            }
          end),
          teams: Enum.map(teams_with_machines, fn {team, machines} ->
            %{
              id: team.id,
              name: team.name,
              members: Enum.map(team.members, fn m ->
                %{name: m.name, role: m.role, soul: m.soul, skills: m.skills}
              end),
              skills: team.skills || [],
              platforms: team.platforms || [],
              knowledge: team.knowledge,
              visibility: team.visibility,
              participants: Map.get(participants, team.id, []),
              your_machines: Enum.map(machines, fn m ->
                %{token: m.token, machine_name: m.machine_name, scope: m.scope, project_name: m.project_name}
              end)
            }
          end)
        }}
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
