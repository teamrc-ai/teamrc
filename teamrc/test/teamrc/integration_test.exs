defmodule Teamrc.IntegrationTest do
  @moduledoc """
  Cross-boundary integration tests that verify data created via one path
  (e.g., web UI context functions) works correctly via another path
  (e.g., CLI API context functions).
  """
  use Teamrc.DataCase, async: false

  alias Teamrc.Teams
  alias Teamrc.Accounts
  alias Teamrc.DeviceAuth

  # Helper to generate unique tokens
  defp unique_token(prefix) do
    "#{prefix}_#{:erlang.unique_integer([:positive])}"
  end

  # Helper to generate unique email
  defp unique_email(prefix \\ "integration") do
    "#{prefix}_#{:erlang.unique_integer([:positive])}@test.com"
  end

  # Helper to create a user with a linked machine token
  defp create_user_with_token(token, opts \\ []) do
    email = Keyword.get(opts, :email, unique_email())

    {:ok, user} =
      Accounts.register_user(%{
        "email" => email,
        "terms_accepted" => "true"
      })

    {:ok, _mt} = Accounts.link_machine_token(user.id, token, "test-machine")
    {user, token}
  end

  describe "web-created invite works with CLI join" do
    test "invite created for a web-created team can be used by CLI token to join" do
      creator_token = unique_token("creator")
      joiner_token = unique_token("joiner")

      # Simulate web creation: create a team via put_team
      {:ok, team_data} =
        Teams.put_team(creator_token, %{
          "name" => "web-team",
          "members" => [
            %{"name" => "backend-agent", "role" => "backend", "soul" => "I handle APIs"},
            %{"name" => "frontend-agent", "role" => "frontend"}
          ],
          "skills" => [
            %{"id" => "testing", "title" => "Testing", "body" => "Write tests"}
          ],
          "knowledge" => "Team knowledge base"
        })

      team_id = team_data["id"]
      assert is_binary(team_id)

      # Create an invite (as if from web dashboard)
      {:ok, invite_code, expires_at} = Teams.create_invite(creator_token, 24, team_id)
      assert String.starts_with?(invite_code, "trc_inv_")
      assert DateTime.compare(expires_at, DateTime.utc_now()) == :gt

      # CLI join flow: join using the invite code
      {:ok, joined_team} = Teams.join_by_invite(invite_code, joiner_token)
      assert joined_team["name"] == "web-team"
      assert length(joined_team["members"]) == 2

      # Verify the joining token can get_team and sees correct data
      {:ok, fetched} = Teams.get_team(joiner_token)
      assert fetched["name"] == "web-team"
      assert fetched["knowledge"] == "Team knowledge base"
      assert length(fetched["members"]) == 2

      member_names = Enum.map(fetched["members"], & &1["name"]) |> Enum.sort()
      assert member_names == ["backend-agent", "frontend-agent"]

      # Joiner sees skills
      assert length(fetched["skills"]) == 1
      assert hd(fetched["skills"])["id"] == "testing"

      # Joiner sees souls (full access, not preview)
      backend = Enum.find(fetched["members"], &(&1["name"] == "backend-agent"))
      assert backend["soul"] == "I handle APIs"
    end
  end

  describe "CLI-created team visible in web dashboard flow" do
    test "get_teams returns all teams a token belongs to" do
      token = unique_token("dashboard")

      # Create Team A via CLI put_team
      {:ok, _team_a} =
        Teams.put_team(token, %{
          "name" => "cli-team-a",
          "members" => [%{"name" => "agent-a", "role" => "dev"}]
        })

      # Verify get_teams returns the team (web dashboard query)
      {:ok, teams} = Teams.get_teams(token)
      assert length(teams) == 1
      assert hd(teams)["name"] == "cli-team-a"

      # Create Team B via invite (simulating another user's team)
      {:ok, invite_code, _team_b_id, _} =
        Teams.create_team_with_invite(%{
          "name" => "invited-team-b",
          "members" => [%{"name" => "agent-b", "role" => "ops"}]
        })

      {:ok, _team_b} = Teams.join_by_invite(invite_code, token)

      # get_teams should return both teams
      {:ok, all_teams} = Teams.get_teams(token)
      assert length(all_teams) == 2

      team_names = Enum.map(all_teams, & &1["name"]) |> Enum.sort()
      assert team_names == ["cli-team-a", "invited-team-b"]

      # Each team should have the correct member count
      team_a_fetched = Enum.find(all_teams, &(&1["name"] == "cli-team-a"))
      team_b_fetched = Enum.find(all_teams, &(&1["name"] == "invited-team-b"))
      assert length(team_a_fetched["members"]) == 1
      assert length(team_b_fetched["members"]) == 1
    end
  end

  describe "clone token from set_visibility works with preview_by_clone_token" do
    test "public team clone token returns correct data with knowledge redacted" do
      token = unique_token("clone")

      {:ok, team_data} =
        Teams.put_team(token, %{
          "name" => "clonable-team",
          "members" => [
            %{"name" => "dev", "role" => "backend", "soul" => "Secret soul text"}
          ],
          "skills" => [
            %{"id" => "deploy", "title" => "Deploy", "body" => "Deploy instructions"}
          ],
          "knowledge" => "Private team knowledge that should be redacted"
        })

      claim_secret = team_data["owner_claim_secret"]
      team_id = team_data["id"]

      # Create user, link token, claim ownership
      {_user, ^token} = create_user_with_token(token)
      {:ok, :claimed} = Teams.claim_ownership(token, claim_secret)

      # Set visibility to public
      {:ok, updated_team} = Teams.set_visibility(token, team_id, "public")
      clone_token = updated_team.clone_token
      assert is_binary(clone_token)
      assert String.starts_with?(clone_token, "trc_cl_")

      # Use clone_token to preview
      {:ok, preview} = Teams.preview_by_clone_token(clone_token)
      assert preview["name"] == "clonable-team"
      assert length(preview["members"]) == 1
      assert hd(preview["members"])["name"] == "dev"

      # Knowledge should be redacted
      assert is_nil(preview["knowledge"])

      # Skills should still be present
      assert length(preview["skills"]) == 1
      assert hd(preview["skills"])["id"] == "deploy"
    end
  end

  describe "device auth flow end-to-end" do
    test "create request, confirm, and poll returns confirmed status with user info" do
      token = unique_token("device")

      # Step 1: CLI creates a device auth request
      {:ok, request} = DeviceAuth.create_request(token)
      assert is_binary(request.device_code)
      assert is_binary(request.user_code)
      assert request.expires_in > 0

      # Step 2: CLI polls - should be pending
      {:ok, poll_result} = DeviceAuth.poll_request(request.device_code, token)
      assert poll_result.status == :pending

      # Step 3: Create a user (simulating web login)
      {user, _user_token} = create_user_with_token(unique_token("device_user"))

      # Step 4: User confirms the request via web UI
      {:ok, _confirmed} = DeviceAuth.confirm_request(request.user_code, user.id, user.email)

      # Step 5: CLI polls again - should be confirmed with user info
      {:ok, confirmed_result} = DeviceAuth.poll_request(request.device_code, token)
      assert confirmed_result.status == :confirmed
      assert confirmed_result.user_id == user.id
      assert confirmed_result.email == user.email

      # Step 6: Link the machine token to the user (as CLI would after confirmation)
      {:ok, _mt} = Accounts.link_machine_token(user.id, token, "cli-machine")

      # Verify token is now linked to the user
      user_data = Accounts.get_user_with_machine_tokens(user.id)
      token_strings = Enum.map(user_data.machine_tokens, & &1.token)
      assert token in token_strings
    end
  end

  describe "invite expiry is enforced across boundaries" do
    test "expired invite fails for both join and preview" do
      creator_token = unique_token("expiry_creator")
      joiner_token = unique_token("expiry_joiner")

      # Create team and invite
      {:ok, _team} =
        Teams.put_team(creator_token, %{
          "name" => "expiry-team",
          "members" => [%{"name" => "bot", "role" => "helper"}]
        })

      {:ok, invite_code, _expires} = Teams.create_invite(creator_token, 24)

      # Verify invite works before expiry
      {:ok, preview_before} = Teams.preview_by_invite(invite_code)
      assert preview_before["name"] == "expiry-team"

      # Manually expire the invite
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      past = DateTime.add(now, -3600)

      Repo.update_all(
        from(i in Teamrc.Schema.Invite, where: i.code == ^invite_code),
        set: [expires_at: past]
      )

      # Join should fail
      assert :error = Teams.join_by_invite(invite_code, joiner_token)

      # Preview should also fail
      assert :error = Teams.preview_by_invite(invite_code)

      # Joiner should not have access
      assert :error = Teams.get_team(joiner_token)
    end
  end

  describe "scoped disconnect preserves other team access" do
    test "erase_token with team_id preserves access to other teams" do
      token = unique_token("scoped_dc")

      # Create Team A
      {:ok, team_a} =
        Teams.put_team(token, %{
          "name" => "keep-team",
          "members" => [%{"name" => "keeper", "role" => "dev"}],
          "knowledge" => "Team A knowledge"
        })

      team_a_id = team_a["id"]

      # Join Team B via invite
      {:ok, invite_code, _, _} =
        Teams.create_team_with_invite(%{
          "name" => "remove-team",
          "members" => [%{"name" => "remover", "role" => "ops"}]
        })

      {:ok, team_b} = Teams.join_by_invite(invite_code, token)
      team_b_id = team_b["id"]

      # Verify token can access both teams
      {:ok, teams_before} = Teams.get_teams(token)
      assert length(teams_before) == 2

      # Disconnect from Team B only
      {:ok, count} = Teams.erase_token(token, team_b_id)
      assert count == 1

      # Team A should still be accessible
      {:ok, got_a} = Teams.get_team(token, team_a_id)
      assert got_a["name"] == "keep-team"
      assert got_a["knowledge"] == "Team A knowledge"

      # Team B should not be accessible
      assert :error = Teams.get_team(token, team_b_id)

      # Push to Team A still works
      {:ok, updated_a} =
        Teams.put_team(
          token,
          %{
            "name" => "keep-team",
            "members" => [
              %{"name" => "keeper", "role" => "dev"},
              %{"name" => "new-member", "role" => "qa"}
            ],
            "knowledge" => "Team A knowledge\nNew line"
          },
          team_a_id
        )

      assert length(updated_a["members"]) == 2
      assert updated_a["knowledge"] =~ "New line"
    end
  end

  describe "ownership claim prevents double-claim" do
    test "second user cannot claim already-claimed team" do
      token_a = unique_token("claimer_a")
      token_b = unique_token("claimer_b")

      # Create team (returns claim secret)
      {:ok, team_data} =
        Teams.put_team(token_a, %{
          "name" => "claim-team",
          "members" => []
        })

      claim_secret = team_data["owner_claim_secret"]
      assert is_binary(claim_secret)
      assert String.starts_with?(claim_secret, "trc_ocs_")

      # Have token_b join the team so it's also a participant
      {:ok, invite_code, _} = Teams.create_invite(token_a, 24)
      {:ok, _} = Teams.join_by_invite(invite_code, token_b)

      # Create users and link tokens
      {_user_a, ^token_a} = create_user_with_token(token_a)
      {_user_b, ^token_b} = create_user_with_token(token_b)

      # User A claims ownership
      {:ok, :claimed} = Teams.claim_ownership(token_a, claim_secret)

      # User B attempts to claim with the same secret - should fail.
      # After claiming, owner_claim_secret is cleared and owner_user_id is set,
      # so the team is no longer in the candidate list. The function returns
      # :invalid_secret (no candidates found) rather than :already_claimed
      # (which only occurs in a race condition).
      result = Teams.claim_ownership(token_b, claim_secret)
      assert {:error, :invalid_secret} = result

      # Verify User A is still the owner (can set visibility)
      team_id = team_data["id"]
      {:ok, _} = Teams.set_visibility(token_a, team_id, "public")

      # Verify User B cannot set visibility (not owner)
      assert {:error, :not_owner} = Teams.set_visibility(token_b, team_id, "public")
    end
  end

  describe "visibility toggle round-trip" do
    test "public -> clone works, private -> clone fails" do
      token = unique_token("vis_toggle")

      {:ok, team_data} =
        Teams.put_team(token, %{
          "name" => "visibility-team",
          "members" => [%{"name" => "agent", "role" => "dev"}]
        })

      claim_secret = team_data["owner_claim_secret"]
      team_id = team_data["id"]

      # Create user, link, claim
      {_user, ^token} = create_user_with_token(token)
      {:ok, :claimed} = Teams.claim_ownership(token, claim_secret)

      # Set public - get clone_token
      {:ok, public_team} = Teams.set_visibility(token, team_id, "public")
      clone_token = public_team.clone_token
      assert is_binary(clone_token)

      # Verify clone works
      {:ok, preview} = Teams.preview_by_clone_token(clone_token)
      assert preview["name"] == "visibility-team"

      # Set private
      {:ok, _private_team} = Teams.set_visibility(token, team_id, "private")

      # Verify clone no longer works
      assert :error = Teams.preview_by_clone_token(clone_token)

      # Set public again - should reuse the same clone_token
      {:ok, public_again} = Teams.set_visibility(token, team_id, "public")
      assert public_again.clone_token == clone_token

      # Clone works again
      {:ok, preview_again} = Teams.preview_by_clone_token(clone_token)
      assert preview_again["name"] == "visibility-team"
    end
  end

  describe "knowledge merge across tokens" do
    test "multiple tokens pushing knowledge produces merged result" do
      token_a = unique_token("knowledge_a")
      token_b = unique_token("knowledge_b")

      # Token A creates team with initial knowledge
      {:ok, team_data} =
        Teams.put_team(token_a, %{
          "name" => "knowledge-team",
          "members" => [%{"name" => "researcher", "role" => "research"}],
          "knowledge" => "line1"
        })

      team_id = team_data["id"]

      # Token B joins the team
      {:ok, invite_code, _} = Teams.create_invite(token_a, 24, team_id)
      {:ok, _} = Teams.join_by_invite(invite_code, token_b)

      # Token A pushes updated knowledge
      {:ok, after_a_push} =
        Teams.put_team(
          token_a,
          %{
            "name" => "knowledge-team",
            "members" => [%{"name" => "researcher", "role" => "research"}],
            "knowledge" => "line1\nline2"
          },
          team_id
        )

      assert after_a_push["knowledge"] =~ "line1"
      assert after_a_push["knowledge"] =~ "line2"

      # Verify get_team returns merged knowledge
      {:ok, fetched} = Teams.get_team(token_b, team_id)
      assert fetched["knowledge"] =~ "line1"
      assert fetched["knowledge"] =~ "line2"

      # Token B pushes with a different knowledge addition
      {:ok, after_b_push} =
        Teams.put_team(
          token_b,
          %{
            "name" => "knowledge-team",
            "members" => [%{"name" => "researcher", "role" => "research"}],
            "knowledge" => "line1\nline3"
          },
          team_id
        )

      # Both additions should be present (merge is append-only with dedup)
      assert after_b_push["knowledge"] =~ "line1"
      assert after_b_push["knowledge"] =~ "line2"
      assert after_b_push["knowledge"] =~ "line3"

      # Final verification: both tokens see the same merged state
      {:ok, final_a} = Teams.get_team(token_a, team_id)
      {:ok, final_b} = Teams.get_team(token_b, team_id)
      assert final_a["knowledge"] == final_b["knowledge"]
      assert final_a["knowledge"] =~ "line1"
      assert final_a["knowledge"] =~ "line2"
      assert final_a["knowledge"] =~ "line3"

      # No duplicate lines
      line1_count =
        final_a["knowledge"]
        |> String.split("\n")
        |> Enum.count(&(&1 == "line1"))

      assert line1_count == 1
    end
  end

  describe "web-created team appears on owner's dashboard" do
    test "team created via create_team_with_invite (no token) is visible to owner" do
      # Simulate web wizard: user is logged in, creates a team with no machine token
      {:ok, user} =
        Accounts.register_user(%{
          "email" => unique_email("web_dash"),
          "terms_accepted" => "true"
        })

      {:ok, _invite_code, _team_id, _} =
        Teams.create_team_with_invite(
          %{
            "name" => "web-only-team",
            "members" => [%{"name" => "agent", "role" => "dev"}]
          },
          owner_user_id: user.id
        )

      # Dashboard query should find this team even with no machine tokens
      teams = Accounts.get_user_teams_with_machines(user.id)
      assert length(teams) == 1
      {team, machines} = hd(teams)
      assert team.name == "web-only-team"
      assert machines == []
    end

    test "web-created team and CLI-linked team both appear on dashboard" do
      {:ok, user} =
        Accounts.register_user(%{
          "email" => unique_email("web_cli_dash"),
          "terms_accepted" => "true"
        })

      # Web-created team (no token)
      {:ok, _invite_code, _team_id, _} =
        Teams.create_team_with_invite(
          %{"name" => "web-team", "members" => []},
          owner_user_id: user.id
        )

      # CLI-created team (with token linked to user)
      cli_token = unique_token("cli_dash")
      {:ok, _mt} = Accounts.link_machine_token(user.id, cli_token, "laptop")
      {:ok, _} = Teams.put_team(cli_token, %{"name" => "cli-team", "members" => []})

      teams = Accounts.get_user_teams_with_machines(user.id)
      assert length(teams) == 2
      names = Enum.map(teams, fn {t, _} -> t.name end) |> Enum.sort()
      assert names == ["cli-team", "web-team"]
    end

    test "is_team_participant? returns true for web-created team owner" do
      {:ok, user} =
        Accounts.register_user(%{
          "email" => unique_email("web_participant"),
          "terms_accepted" => "true"
        })

      {:ok, _invite_code, team_id, _} =
        Teams.create_team_with_invite(
          %{"name" => "owned-team", "members" => []},
          owner_user_id: user.id
        )

      assert Accounts.is_team_participant?(user.id, team_id)
    end
  end

  describe "multi-team token isolation" do
    test "push to one team does not affect another" do
      token = unique_token("isolation")

      # Create Team A
      {:ok, team_a} =
        Teams.put_team(token, %{
          "name" => "isolated-a",
          "members" => [%{"name" => "agent-a", "role" => "dev"}],
          "skills" => [%{"id" => "skill-a", "title" => "Skill A", "body" => "A body"}],
          "knowledge" => "Knowledge A"
        })

      team_a_id = team_a["id"]

      # Create Team B via invite
      {:ok, invite_code, _, _} =
        Teams.create_team_with_invite(%{
          "name" => "isolated-b",
          "members" => [%{"name" => "agent-b", "role" => "ops"}],
          "knowledge" => "Knowledge B"
        })

      {:ok, team_b} = Teams.join_by_invite(invite_code, token)
      team_b_id = team_b["id"]

      # Get initial hashes for both teams
      {:ok, hashes_a_before} = Teams.get_team_hashes(token, team_a_id)
      {:ok, hashes_b_before} = Teams.get_team_hashes(token, team_b_id)

      # Hashes should already differ (different teams)
      assert hashes_a_before["hash"] != hashes_b_before["hash"]

      # Push update to Team A only
      {:ok, updated_a} =
        Teams.put_team(
          token,
          %{
            "name" => "isolated-a",
            "members" => [
              %{"name" => "agent-a", "role" => "dev"},
              %{"name" => "agent-a2", "role" => "qa"}
            ],
            "skills" => [%{"id" => "skill-a", "title" => "Skill A", "body" => "A body"}],
            "knowledge" => "Knowledge A\nNew insight"
          },
          team_a_id
        )

      assert length(updated_a["members"]) == 2

      # Verify Team B is unchanged
      {:ok, team_b_after} = Teams.get_team(token, team_b_id)
      assert team_b_after["name"] == "isolated-b"
      assert length(team_b_after["members"]) == 1
      assert hd(team_b_after["members"])["name"] == "agent-b"
      assert team_b_after["knowledge"] == "Knowledge B"

      # Verify hashes: Team A should have changed, Team B should not
      {:ok, hashes_a_after} = Teams.get_team_hashes(token, team_a_id)
      {:ok, hashes_b_after} = Teams.get_team_hashes(token, team_b_id)

      assert hashes_a_after["hash"] != hashes_a_before["hash"]
      assert hashes_b_after["hash"] == hashes_b_before["hash"]

      # Component hashes should reflect what changed
      assert hashes_a_after["members_hash"] != hashes_a_before["members_hash"]
      assert hashes_a_after["knowledge_hash"] != hashes_a_before["knowledge_hash"]
      assert hashes_a_after["skills_hash"] == hashes_a_before["skills_hash"]
    end
  end
end
