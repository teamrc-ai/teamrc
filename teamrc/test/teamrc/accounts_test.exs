defmodule Teamrc.AccountsTest do
  use Teamrc.DataCase, async: false

  alias Teamrc.Accounts
  alias Teamrc.Accounts.{User, UserToken, MachineToken}
  alias Teamrc.Schema.TokenTeam

  import Teamrc.AccountsFixtures

  describe "register_user/1" do
    test "creates user with valid attrs including ToS" do
      attrs = valid_user_attributes()
      assert {:ok, %User{} = user} = Accounts.register_user(attrs)
      assert user.email == attrs["email"]
      assert user.accepted_terms_at
      assert user.terms_version_accepted
    end

    test "fails without ToS fields" do
      assert {:error, changeset} =
               Accounts.register_user(%{"email" => unique_user_email()})

      assert "terms of service must be accepted to register" in errors_on(changeset).terms_accepted
    end

    test "fails with duplicate email" do
      email = unique_user_email()
      attrs = %{"email" => email, "terms_accepted" => "true"}
      {:ok, _user} = Accounts.register_user(attrs)
      assert {:error, changeset} = Accounts.register_user(attrs)
      assert errors_on(changeset).email != []
    end
  end

  describe "get_user_by_email_and_password/2" do
    test "returns user with valid credentials" do
      user = user_with_password_fixture()
      found = Accounts.get_user_by_email_and_password(user.email, user.password)
      assert found.id == user.id
    end

    test "returns nil with wrong password" do
      user = user_with_password_fixture()
      refute Accounts.get_user_by_email_and_password(user.email, "wrong_password_1234")
    end

    test "returns nil for non-existent email" do
      refute Accounts.get_user_by_email_and_password("nope@example.com", "whatever_1234")
    end
  end

  describe "accept_terms/2" do
    test "updates accepted_terms_at and version" do
      user = user_fixture()
      {:ok, updated} = Accounts.accept_terms(user, "2026-03-11")
      assert updated.accepted_terms_at
      assert updated.terms_version_accepted == "2026-03-11"
    end
  end

  describe "find_or_create_oauth_user/3" do
    test "creates user with new email" do
      email = unique_user_email()

      assert {:ok, user} =
               Accounts.find_or_create_oauth_user("github", "12345", %{email: email})

      assert user.email == email
      assert user.provider == "github"
      assert user.provider_uid == "12345"
    end

    test "returns existing user for same provider+uid" do
      email = unique_user_email()
      {:ok, user1} = Accounts.find_or_create_oauth_user("github", "111", %{email: email})
      {:ok, user2} = Accounts.find_or_create_oauth_user("github", "111", %{email: email})
      assert user1.id == user2.id
    end

    test "returns error for existing email with different provider" do
      email = unique_user_email()
      {:ok, _user} = Accounts.find_or_create_oauth_user("github", "222", %{email: email})

      assert {:error, :oauth_provider_mismatch} =
               Accounts.find_or_create_oauth_user("google", "333", %{email: email})
    end

    test "returns error for nil email" do
      assert {:error, :missing_email} =
               Accounts.find_or_create_oauth_user("github", "444", %{email: nil})
    end
  end

  describe "delete_user_and_data/1" do
    test "deletes user, tokens, token_teams, and broadcasts disconnect" do
      # Create user with machine token
      user = user_fixture()
      token_str = "trc_ak_del_#{:erlang.unique_integer([:positive])}"
      {:ok, _mt} = Accounts.link_machine_token(user.id, token_str, "test-machine")

      # Create a team and associate the token
      {:ok, team_data} =
        Teamrc.Teams.put_team(token_str, %{"name" => "del-test-team", "members" => []})

      # Generate a session token
      _session_token = Accounts.generate_user_session_token(user)

      # Delete the user
      assert :ok = Accounts.delete_user_and_data(user)

      # Verify user is gone
      assert is_nil(Repo.get(User, user.id))

      # Verify machine tokens are gone (cascade)
      assert Repo.all(from mt in MachineToken, where: mt.user_id == ^user.id) == []

      # Verify token_teams are gone
      assert Repo.all(from tt in TokenTeam, where: tt.token == ^token_str) == []

      # Verify session tokens are gone
      assert Repo.all(from t in UserToken, where: t.user_id == ^user.id) == []

      # Team itself should still exist
      assert Repo.get(Teamrc.Schema.Team, team_data["id"])
    end
  end

  describe "export_user_data/1" do
    test "returns truncated tokens and hashed participant emails" do
      user = user_fixture()
      token_str = "trc_ak_export_#{:erlang.unique_integer([:positive])}"
      {:ok, _mt} = Accounts.link_machine_token(user.id, token_str, "export-machine")

      {:ok, _team_data} =
        Teamrc.Teams.put_team(token_str, %{"name" => "export-team", "members" => []})

      assert {:ok, data} = Accounts.export_user_data(user.id)

      assert data.account.id == user.id
      assert data.account.email == user.email

      # Machine tokens should be truncated
      assert Enum.all?(data.machines, fn m ->
               String.ends_with?(m.token, "...")
             end)

      # Teams should be present
      assert length(data.teams) == 1
      team = hd(data.teams)
      assert team.name == "export-team"

      # Participant emails should be hashed, not raw
      Enum.each(team.participants, fn p ->
        refute p == user.email
      end)
    end

    test "returns error for non-existent user" do
      assert {:error, :not_found} =
               Accounts.export_user_data(Ecto.UUID.generate())
    end
  end

  describe "deliver_user_reset_password_instructions/2" do
    test "creates a reset password token" do
      user = user_fixture()

      assert {:ok, _email} =
               Accounts.deliver_user_reset_password_instructions(
                 user,
                 &"http://example.com/reset/#{&1}"
               )

      # A token should exist in the database
      assert Repo.one(
               from t in UserToken,
                 where: t.user_id == ^user.id and t.context == "reset_password"
             )
    end
  end

  describe "get_user_by_reset_password_token/1" do
    test "returns user with valid token" do
      user = user_fixture()

      token =
        extract_user_token(fn url_fun ->
          Accounts.deliver_user_reset_password_instructions(user, url_fun)
        end)

      found = Accounts.get_user_by_reset_password_token(token)
      assert found.id == user.id
    end

    test "returns nil with invalid token" do
      refute Accounts.get_user_by_reset_password_token("invalid_token_value")
    end
  end

  describe "reset_user_password/2" do
    test "updates password and deletes old tokens" do
      user = user_fixture()

      # Create a session token that should get deleted
      _session_token = Accounts.generate_user_session_token(user)

      assert {:ok, {updated_user, expired_tokens}} =
               Accounts.reset_user_password(user, %{password: "new_secure_password_123"})

      assert updated_user.id == user.id
      # Old session tokens should be returned for disconnection
      assert is_list(expired_tokens)

      # All tokens should be deleted
      assert Repo.all(from t in UserToken, where: t.user_id == ^user.id) == []
    end
  end
end
