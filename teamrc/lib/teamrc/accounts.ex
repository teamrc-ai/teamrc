defmodule Teamrc.Accounts do
  @moduledoc """
  The Accounts context.

  Combines phx.gen.auth user management (registration, session tokens, email change,
  password change) with machine token operations (CLI ed25519 keypair linking) and
  team association queries.
  """

  alias Teamrc.Repo
  alias Teamrc.Accounts.{User, UserToken, UserNotifier, UserProfile, MachineToken}
  alias Teamrc.Schema.{Team, TokenTeam}
  import Ecto.Query

  @terms_version "2026-03-11"

  @doc "Returns the current terms of service version string."
  def current_terms_version, do: @terms_version

  ## ──────────────────────────────────────────────────────────
  ## Database getters (phx.gen.auth)
  ## ──────────────────────────────────────────────────────────

  @doc """
  Gets a user by email.
  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by email and password.
  """
  def get_user_by_email_and_password(email, password)
      when is_binary(email) and is_binary(password) do
    user = Repo.get_by(User, email: email)
    if User.valid_password?(user, password), do: user
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.
  """
  def get_user!(id), do: Repo.get!(User, id)

  @doc """
  Gets a single user. Returns nil if not found.
  """
  def get_user(id), do: Repo.get(User, id)

  ## ──────────────────────────────────────────────────────────
  ## User registration (phx.gen.auth)
  ## ──────────────────────────────────────────────────────────

  @doc """
  Registers a user with email (no password required for magic link flow).
  Requires terms of service acceptance (`accepted_terms_at` and `terms_version_accepted`).
  """
  def register_user(attrs) do
    %User{}
    |> User.email_changeset(attrs)
    |> User.registration_terms_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Registers a user with email and password.
  Requires terms of service acceptance.
  """
  def register_user_with_password(attrs) do
    %User{}
    |> User.email_changeset(attrs)
    |> User.password_changeset(attrs)
    |> User.registration_terms_changeset(attrs)
    |> Repo.insert()
  end

  ## ──────────────────────────────────────────────────────────
  ## OAuth user management
  ## ──────────────────────────────────────────────────────────

  @doc """
  Finds or creates a user from OAuth callback data.

  If a user with the email already exists (whether via email/password
  or a different OAuth provider), the login is rejected to prevent
  account takeover via email squatting.
  """
  def find_or_create_oauth_user(provider, uid, info) when is_binary(provider) and is_binary(uid) do
    email = info[:email] || info["email"]

    if is_nil(email) do
      {:error, :missing_email}
    else
      find_or_create_oauth_user_impl(provider, uid, email, info)
    end
  end

  defp find_or_create_oauth_user_impl(provider, uid, email, info) do
    avatar_url = info[:avatar_url] || info["avatar_url"]

    # Wrap in transaction to prevent TOCTOU race on concurrent OAuth logins
    Repo.transaction(fn ->
      case Repo.get_by(User, email: email) do
        nil ->
          attrs = %{
            email: email,
            provider: provider,
            provider_uid: uid,
            avatar_url: avatar_url,
            confirmed_at: DateTime.utc_now(:second)
          }

          case %User{}
               |> User.oauth_changeset(attrs)
               |> Repo.insert(on_conflict: :nothing, conflict_target: :email, returning: true) do
            {:ok, user} ->
              if is_nil(user.id) do
                # on_conflict: :nothing returned no row; another transaction won
                case Repo.get_by(User, email: email) do
                  nil -> Repo.rollback(:race_condition)
                  user -> user
                end
              else
                user
              end

            {:error, changeset} ->
              Repo.rollback(changeset)
          end

        %User{provider: nil} ->
          Repo.rollback(:email_already_exists)

        %User{provider: ^provider, provider_uid: ^uid} = user ->
          user

        %User{provider: _other_provider} ->
          Repo.rollback(:oauth_provider_mismatch)
      end
    end)
  end

  ## ──────────────────────────────────────────────────────────
  ## Terms of Service
  ## ──────────────────────────────────────────────────────────

  @doc """
  Records the user's acceptance of terms of service.
  Requires a User struct (not raw user_id) to prevent type confusion.
  """
  def accept_terms(%User{} = user, version \\ @terms_version) when is_binary(version) do
    user
    |> User.terms_changeset(%{
      accepted_terms_at: DateTime.utc_now(:second),
      terms_version_accepted: version
    })
    |> Repo.update()
  end

  ## ──────────────────────────────────────────────────────────
  ## Settings (phx.gen.auth)
  ## ──────────────────────────────────────────────────────────

  @doc """
  Checks whether the user is in sudo mode.
  """
  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.
  """
  def change_user_email(user, attrs \\ %{}, opts \\ []) do
    User.email_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user email using the given token.
  """
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    Repo.transaction(fn ->
      with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
           %UserToken{sent_to: email} <- Repo.one(query),
           {:ok, user} <- Repo.update(User.email_changeset(user, %{email: email})),
           {_count, _result} <-
             Repo.delete_all(from(UserToken, where: [user_id: ^user.id, context: ^context])) do
        user
      else
        _ -> Repo.rollback(:transaction_aborted)
      end
    end)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user password.
  """
  def change_user_password(user, attrs \\ %{}, opts \\ []) do
    User.password_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user password.
  """
  def update_user_password(user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> update_user_and_delete_all_tokens()
  end

  @doc """
  Updates the user's display name in their profile.
  Creates the profile if it doesn't exist.
  """
  def update_display_name(%User{} = user, name) when is_binary(name) do
    case Repo.get_by(UserProfile, user_id: user.id) do
      nil ->
        %UserProfile{}
        |> UserProfile.changeset(%{user_id: user.id, display_name: name})
        |> Repo.insert()

      profile ->
        profile
        |> UserProfile.changeset(%{display_name: name})
        |> Repo.update()
    end
  end

  @doc """
  Initiates an email change by validating the new email.
  Returns {:ok, user} on success or {:error, changeset} on validation failure.
  """
  def apply_user_email(%User{} = user, attrs) do
    user
    |> User.email_changeset(attrs, validate_unique: true)
    |> Ecto.Changeset.apply_action(:update)
  end

  ## ──────────────────────────────────────────────────────────
  ## Session (phx.gen.auth)
  ## ──────────────────────────────────────────────────────────

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Gets the user with the given magic link token.
  """
  def get_user_by_magic_link_token(token) do
    with {:ok, query} <- UserToken.verify_magic_link_token_query(token),
         {user, _token} <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Logs the user in by magic link.
  """
  def login_user_by_magic_link(token) do
    {:ok, query} = UserToken.verify_magic_link_token_query(token)

    case Repo.one(query) do
      {%User{confirmed_at: nil, hashed_password: hash}, _token} when not is_nil(hash) ->
        raise """
        magic link log in is not allowed for unconfirmed users with a password set!

        This cannot happen with the default implementation, which indicates that you
        might have adapted the code to a different use case. Please make sure to read the
        "Mixing magic link and password registration" section of `mix help phx.gen.auth`.
        """

      {%User{confirmed_at: nil} = user, _token} ->
        user
        |> User.confirm_changeset()
        |> update_user_and_delete_all_tokens()

      {user, token} ->
        Repo.delete!(token)
        {:ok, {user, []}}

      nil ->
        {:error, :not_found}
    end
  end

  @doc ~S"""
  Delivers the update email instructions to the given user.
  """
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc """
  Delivers the magic link login instructions to the given user.
  """
  def deliver_login_instructions(%User{} = user, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "login")
    Repo.insert!(user_token)
    UserNotifier.deliver_login_instructions(user, magic_link_url_fun.(encoded_token))
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  ## ──────────────────────────────────────────────────────────
  ## Machine token operations (migrated from old Accounts context)
  ## ──────────────────────────────────────────────────────────

  @doc "Link a machine token to a user. Creates or updates the machine token record."
  def link_machine_token(user_id, token, machine_name) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case Repo.get_by(MachineToken, token: token) do
      nil ->
        %MachineToken{}
        |> MachineToken.changeset(%{
          user_id: user_id,
          token: token,
          machine_name: machine_name,
          last_seen_at: now
        })
        |> Repo.insert()

      %{user_id: ^user_id} = existing ->
        existing
        |> MachineToken.changeset(%{
          machine_name: machine_name || existing.machine_name,
          last_seen_at: now,
          revoked_at: nil
        })
        |> Repo.update()

      _existing ->
        {:error, :token_belongs_to_another_user}
    end
  end

  @doc "Get a user with all their machine tokens preloaded."
  def get_user_with_machine_tokens(user_id) do
    User
    |> where(id: ^user_id)
    |> preload(:machine_tokens)
    |> Repo.one()
  end

  @doc "Get teams with machine details for the dashboard. Returns [{team, machines}]."
  def get_user_teams_with_machines(user_id) do
    active_tokens =
      from(mt in MachineToken,
        where: mt.user_id == ^user_id and is_nil(mt.revoked_at),
        select: mt
      )
      |> Repo.all()

    token_strings = Enum.map(active_tokens, & &1.token)

    # Teams linked via machine tokens
    token_teams =
      if token_strings == [] do
        []
      else
        from(tt in TokenTeam,
          where: tt.token in ^token_strings,
          preload: [team: :members]
        )
        |> Repo.all()
      end

    # Teams owned by this user (e.g. created via web UI with no machine token).
    # Exclude teams already found via active machine tokens to avoid duplicates.
    token_team_ids = MapSet.new(token_teams, & &1.team_id)

    owned_teams =
      from(t in Team,
        where: t.owner_user_id == ^user_id and is_nil(t.deleted_at),
        preload: [:members]
      )
      |> Repo.all()
      |> Enum.reject(fn t -> MapSet.member?(token_team_ids, t.id) end)

    token_to_machine =
      Map.new(active_tokens, fn mt ->
        {mt.token,
         %{
           token: mt.token,
           machine_name: mt.machine_name,
           last_seen_at: mt.last_seen_at
         }}
      end)

    machine_linked =
      token_teams
      |> Enum.group_by(& &1.team_id)
      |> Enum.map(fn {_team_id, tts} ->
        team = hd(tts).team

        machines =
          Enum.map(tts, fn tt ->
            machine =
              Map.get(token_to_machine, tt.token, %{
                token: tt.token,
                machine_name: nil,
                last_seen_at: nil
              })

            Map.merge(machine, %{
              scope: tt.scope || "project",
              project_name: tt.project_name,
              tt_last_seen_at: tt.last_seen_at
            })
          end)
          |> Enum.uniq_by(& &1.token)

        {team, machines}
      end)

    # Owned teams with no machine tokens show with empty machines list
    owned_only = Enum.map(owned_teams, fn team -> {team, []} end)

    machine_linked ++ owned_only
  end

  @doc "Check if a user has a machine token associated with a team."
  def is_team_participant?(nil, _team_id), do: false

  def is_team_participant?(user_id, team_id) do
    # Check active machine token link
    via_token =
      from(tt in TokenTeam,
        join: mt in MachineToken, on: mt.token == tt.token,
        where: mt.user_id == ^user_id and tt.team_id == ^team_id and is_nil(mt.revoked_at),
        select: true,
        limit: 1
      )
      |> Repo.one()
      |> is_not_nil()

    # Also check direct ownership (owner always has access)
    via_token or
      (from(t in Team, where: t.id == ^team_id and t.owner_user_id == ^user_id, select: true, limit: 1)
       |> Repo.one()
       |> is_not_nil())
  end

  defp is_not_nil(nil), do: false
  defp is_not_nil(_), do: true

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
        left_join: mt in MachineToken,
        on: mt.token == tt.token and is_nil(mt.revoked_at),
        left_join: u in User,
        on: u.id == mt.user_id,
        where: tt.team_id in ^team_ids,
        select: {tt.team_id, u.email}
      )
      |> Repo.all()
      |> Enum.group_by(fn {team_id, _} -> team_id end, fn {_, email} -> email || "anonymous" end)
      |> Map.new(fn {team_id, emails} -> {team_id, Enum.uniq(emails)} end)
    end
  end

  @doc "Revoke a machine token owned by a user."
  def revoke_machine_token(user_id, token) do
    case Repo.get_by(MachineToken, user_id: user_id, token: token) do
      nil ->
        {:error, :not_found}

      machine_token ->
        case Repo.transaction(fn ->
               machine_token
               |> MachineToken.changeset(%{
                 revoked_at: DateTime.utc_now() |> DateTime.truncate(:second)
               })
               |> Repo.update!()

               from(tt in TokenTeam, where: tt.token == ^token)
               |> Repo.delete_all()
             end) do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

  @doc "Check if a machine token belongs to the team's owner."
  def is_team_owner?(token, team_id) do
    case Repo.get_by(MachineToken, token: token) do
      nil -> false
      %{revoked_at: revoked} when not is_nil(revoked) -> false

      %{user_id: user_id} when not is_nil(user_id) ->
        from(t in Team,
          where: t.id == ^team_id and t.owner_user_id == ^user_id,
          select: t.id,
          limit: 1
        )
        |> Repo.one()
        |> is_binary()

      _ ->
        false
    end
  end

  @doc "Copy team associations from other tokens of the same user to a new token."
  def reassociate_teams(user_id, new_token) do
    case Repo.get_by(MachineToken, user_id: user_id, token: new_token) do
      nil ->
        {:error, :token_not_found}

      %{revoked_at: revoked} when not is_nil(revoked) ->
        {:error, :token_revoked}

      _token ->
        existing_team_ids =
          from(tt in TokenTeam,
            join: mt in MachineToken,
            on: mt.token == tt.token,
            where:
              mt.user_id == ^user_id and mt.token != ^new_token and is_nil(mt.revoked_at),
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
                scope: "project",
                inserted_at: now,
                updated_at: now
              }
            end)

          Repo.insert_all(TokenTeam, entries, on_conflict: :nothing)
        end

        {:ok, length(new_team_ids)}
    end
  end

  @doc "Delete a user and all associated data (machine tokens, token_teams, sessions). Teams themselves are preserved."
  def delete_user_and_data(%User{} = user) do
    user = Repo.preload(user, :machine_tokens)
    all_tokens = Enum.map(user.machine_tokens, & &1.token)

    # Collect session tokens before deletion so we can broadcast disconnects
    session_tokens =
      Repo.all(from t in UserToken, where: t.user_id == ^user.id)

    Repo.transaction(fn ->
      if all_tokens != [] do
        from(tt in TokenTeam, where: tt.token in ^all_tokens)
        |> Repo.delete_all()
      end

      # Clear owner_user_id on owned teams to prevent dangling references
      from(t in Team, where: t.owner_user_id == ^user.id)
      |> Repo.update_all(set: [owner_user_id: nil])

      # Explicitly delete session tokens (belt-and-suspenders with FK cascade)
      from(t in UserToken, where: t.user_id == ^user.id)
      |> Repo.delete_all()

      Repo.delete!(user)
    end)
    |> case do
      {:ok, _} ->
        # Disconnect all open LiveView sessions
        Enum.each(session_tokens, fn t ->
          topic = "users_sessions:#{Base.url_encode64(t.token)}"
          TeamrcWeb.Endpoint.broadcast(topic, "disconnect", %{})
        end)

        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Export all data associated with a user as a map."
  def export_user_data(user_id) do
    case get_user_with_machine_tokens(user_id) do
      nil ->
        {:error, :not_found}

      user ->
        teams_with_machines = get_user_teams_with_machines(user.id)
        team_ids = Enum.map(teams_with_machines, fn {team, _} -> team.id end)
        participants = resolve_participants_batch(team_ids)

        {:ok,
         %{
           account: %{
             id: user.id,
             email: user.email,
             created_at: user.inserted_at,
             updated_at: user.updated_at
           },
           machines:
             Enum.map(user.machine_tokens, fn mt ->
               %{
                 token: String.slice(mt.token, 0, 12) <> "...",
                 machine_name: mt.machine_name,
                 last_seen_at: mt.last_seen_at,
                 revoked_at: mt.revoked_at,
                 created_at: mt.inserted_at
               }
             end),
           teams:
             Enum.map(teams_with_machines, fn {team, machines} ->
               hashed_participants =
                 Map.get(participants, team.id, [])
                 |> Enum.map(fn
                   "anonymous" -> "anonymous"
                   email -> Teamrc.PII.email_hash(email) || "anonymous"
                 end)

               %{
                 id: team.id,
                 name: team.name,
                 members:
                   Enum.map(team.members, fn m ->
                     %{name: m.name, role: m.role, soul: m.soul, skills: m.skills}
                   end),
                 skills: team.skills || [],
                 platforms: team.platforms || [],
                 knowledge: team.knowledge,
                 visibility: team.visibility,
                 participants: hashed_participants,
                 your_machines:
                   Enum.map(machines, fn m ->
                     %{
                       token: String.slice(m.token, 0, 12) <> "...",
                       machine_name: m.machine_name,
                       scope: m.scope,
                       project_name: m.project_name
                     }
                   end)
               }
             end)
         }}
    end
  end

  ## ──────────────────────────────────────────────────────────
  ## Password reset (phx.gen.auth)
  ## ──────────────────────────────────────────────────────────

  @doc """
  Delivers the reset password instructions to the given user.
  """
  def deliver_user_reset_password_instructions(%User{} = user, reset_password_url_fun)
      when is_function(reset_password_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "reset_password")
    Repo.insert!(user_token)
    UserNotifier.deliver_reset_password_instructions(user, reset_password_url_fun.(encoded_token))
  end

  @doc """
  Gets the user by reset password token.
  """
  def get_user_by_reset_password_token(token) do
    with {:ok, query} <- UserToken.verify_reset_password_token_query(token),
         %User{} = user <- Repo.one(query) do
      user
    else
      _ -> nil
    end
  end

  @doc """
  Resets the user password.
  """
  def reset_user_password(user, attrs) do
    user
    |> User.password_changeset(attrs)
    |> update_user_and_delete_all_tokens()
  end

  ## ──────────────────────────────────────────────────────────
  ## Token helpers (phx.gen.auth private)
  ## ──────────────────────────────────────────────────────────

  defp update_user_and_delete_all_tokens(changeset) do
    Repo.transaction(fn ->
      with {:ok, user} <- Repo.update(changeset) do
        tokens_to_expire = Repo.all(from t in UserToken, where: t.user_id == ^user.id)

        Repo.delete_all(from(t in UserToken, where: t.id in ^Enum.map(tokens_to_expire, & &1.id)))

        {user, tokens_to_expire}
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end
end
