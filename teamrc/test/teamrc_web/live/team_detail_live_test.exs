defmodule TeamrcWeb.TeamDetailLiveTest do
  use TeamrcWeb.ConnCase
  import Phoenix.LiveViewTest

  alias Teamrc.{Accounts, Repo, Teams}
  alias Teamrc.Schema.Team

  # --- Helpers ---

  defp create_team_with_invite(opts \\ []) do
    team = %{
      name: opts[:name] || "test-team",
      members: opts[:members] || [%{name: "dev", role: "development"}],
      skills: opts[:skills] || [],
      platforms: opts[:platforms] || []
    }

    {:ok, invite_code, team_id, _} = Teams.create_team_with_invite(team, opts)
    {invite_code, team_id}
  end

  defp make_team_public(team_id) do
    team = Repo.get!(Team, team_id)
    team |> Ecto.Changeset.change(%{visibility: "public"}) |> Repo.update!()
  end

  defp create_owner_with_team(opts \\ []) do
    user = Teamrc.AccountsFixtures.user_fixture()
    {invite_code, team_id} = create_team_with_invite([owner_user_id: user.id] ++ opts)

    # Link a machine token so the user is a "participant"
    token = "trc_ak_test_#{System.unique_integer([:positive])}"
    {:ok, _mt} = Accounts.link_machine_token(user.id, token, "test-machine")
    Teams.join_by_invite(invite_code, token)

    %{user: user, team_id: team_id, invite_code: invite_code, token: token}
  end

  # --- Tests: page rendering ---

  describe "private team without access" do
    test "shows private gate for unauthenticated user", %{conn: conn} do
      {_code, team_id} = create_team_with_invite()

      {:ok, _view, html} = live(conn, "/teams/#{team_id}")

      assert html =~ "This team is private"
      assert html =~ "You need an invite code to view this team."
    end

    test "non-existent team redirects to /new", %{conn: conn} do
      fake_id = Ecto.UUID.generate()

      assert {:error, {:redirect, %{to: "/new"}}} =
               live(conn, "/teams/#{fake_id}")
    end
  end

  describe "team with invite access" do
    test "renders team name and members with valid invite", %{conn: conn} do
      {code, team_id} = create_team_with_invite()

      {:ok, _view, html} = live(conn, "/teams/#{team_id}?invite=#{code}")

      assert html =~ "test-team"
      assert html =~ "dev"
    end

    test "shows join command with invite code", %{conn: conn} do
      {code, team_id} = create_team_with_invite()

      {:ok, _view, html} = live(conn, "/teams/#{team_id}?invite=#{code}")

      assert html =~ "npx @teamrc/cli join #{code}"
      assert html =~ "Invite code expires in"
    end

    test "invite holder cannot see edit controls", %{conn: conn} do
      {code, team_id} = create_team_with_invite()

      {:ok, view, _html} = live(conn, "/teams/#{team_id}?invite=#{code}")

      refute has_element?(view, "button", "Add team member")
      refute has_element?(view, "button", "Add skill")
    end

    test "invite holder cannot add member via event", %{conn: conn} do
      {code, team_id} = create_team_with_invite()

      {:ok, view, _html} = live(conn, "/teams/#{team_id}?invite=#{code}")

      # Set up member form state, then attempt to add
      render_click(view, "custom_member", %{})
      render_keyup(view, "update_new_member_name", %{"value" => "hacker-agent"})
      render_keyup(view, "update_new_member_role", %{"value" => "hacking"})
      render_click(view, "add_member", %{})

      # Verify member was NOT added
      team = Repo.get!(Team, team_id) |> Repo.preload(:members)
      refute Enum.any?(team.members, &(&1.name == "hacker-agent"))
    end
  end

  describe "public team" do
    test "renders team for unauthenticated viewer", %{conn: conn} do
      {_code, team_id} = create_team_with_invite()
      make_team_public(team_id)

      {:ok, _view, html} = live(conn, "/teams/#{team_id}")

      assert html =~ "test-team"
      assert html =~ "dev"
      assert html =~ "public"
    end

    test "viewer cannot see edit controls", %{conn: conn} do
      {_code, team_id} = create_team_with_invite()
      make_team_public(team_id)

      {:ok, view, _html} = live(conn, "/teams/#{team_id}")

      refute has_element?(view, "button", "Add team member")
    end
  end

  describe "owner access" do
    test "shows owner controls (share button)", %{conn: conn} do
      %{user: user, team_id: team_id} = create_owner_with_team()
      conn = log_in_user(conn, user)

      {:ok, view, html} = live(conn, "/teams/#{team_id}")

      assert html =~ "test-team"
      assert has_element?(view, "button[phx-click='open_share_modal']", "Share")
    end

    test "owner can rename team", %{conn: conn} do
      %{user: user, team_id: team_id} = create_owner_with_team()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, "/teams/#{team_id}")

      # Open name edit
      view |> element("button[phx-click='toggle_edit'][phx-value-section='name']") |> render_click()

      # Update name
      view |> element("input#team-name") |> render_keyup(%{"value" => "renamed-team"})

      # Save
      view |> element("button[phx-click='save_team_name']") |> render_click()

      html = render(view)
      assert html =~ "renamed-team"
    end

    test "owner can share team via share flow", %{conn: conn} do
      %{user: user, team_id: team_id} = create_owner_with_team()
      conn = log_in_user(conn, user)

      {:ok, view, html} = live(conn, "/teams/#{team_id}")

      assert html =~ "private"

      # Open share modal
      view |> element("button[phx-click='open_share_modal']") |> render_click()
      html = render(view)
      assert html =~ "Share your team publicly?"

      # Confirm share
      view |> element("button[phx-click='confirm_share']") |> render_click()

      html = render(view)
      assert html =~ "public"
      assert html =~ "Share this team"
    end

    test "owner can stop sharing", %{conn: conn} do
      %{user: user, team_id: team_id} = create_owner_with_team()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, "/teams/#{team_id}")

      # First make it public via share flow
      view |> element("button[phx-click='open_share_modal']") |> render_click()
      view |> element("button[phx-click='confirm_share']") |> render_click()

      html = render(view)
      assert html =~ "public"

      # Stop sharing
      view |> element("button[phx-click='stop_sharing']") |> render_click()

      html = render(view)
      assert html =~ "private"
    end
  end

  describe "team deletion" do
    test "owner can delete team", %{conn: conn} do
      %{user: user, team_id: team_id} = create_owner_with_team()
      conn = log_in_user(conn, user)

      {:ok, view, html} = live(conn, "/teams/#{team_id}")

      assert html =~ "Danger zone"
      assert html =~ "Delete team"

      view |> element("button[phx-click='delete_team']") |> render_click()

      # Should redirect to dashboard
      assert_redirect(view, "/dashboard")

      # Team should be soft-deleted (record exists but marked deleted)
      team = Repo.get(Team, team_id)
      assert team.deleted_at != nil
      # Should not be findable through normal queries
      assert Teamrc.Teams.get_team_by_id(team_id) == nil
    end

    test "non-owner cannot see delete button", %{conn: conn} do
      {code, team_id} = create_team_with_invite()

      {:ok, _view, html} = live(conn, "/teams/#{team_id}?invite=#{code}")

      refute html =~ "Danger zone"
      refute html =~ "Delete team"
    end

    test "non-owner cannot delete team via event", %{conn: conn} do
      {code, team_id} = create_team_with_invite()

      {:ok, view, _html} = live(conn, "/teams/#{team_id}?invite=#{code}")

      render_click(view, "delete_team", %{})

      # Team should still exist
      assert Repo.get(Team, team_id) != nil
    end

    test "participant (non-owner) cannot delete team", %{conn: conn} do
      # Create team with a different owner
      %{team_id: team_id, invite_code: invite_code} = create_owner_with_team()

      # Create a second user who joins as participant
      participant = Teamrc.AccountsFixtures.user_fixture()
      participant_token = "trc_ak_part_#{System.unique_integer([:positive])}"
      {:ok, _mt} = Accounts.link_machine_token(participant.id, participant_token, "part-machine")
      Teams.join_by_invite(invite_code, participant_token)

      conn = log_in_user(conn, participant)
      {:ok, view, html} = live(conn, "/teams/#{team_id}")

      # Participant can see the team but not the delete button
      assert html =~ "test-team"
      refute html =~ "Danger zone"

      # Attempting delete via event should fail
      render_click(view, "delete_team", %{})
      assert Repo.get(Team, team_id) != nil
    end
  end

  describe "claim ownership" do
    test "participant sees claim button for unclaimed team", %{conn: conn} do
      # Create team without owner_user_id
      {_code, team_id} = create_team_with_invite()

      # Create a user who joins as participant
      user = Teamrc.AccountsFixtures.user_fixture()
      token = "trc_ak_claim_#{System.unique_integer([:positive])}"
      {:ok, _mt} = Accounts.link_machine_token(user.id, token, "claim-machine")
      invite_code = Teams.create_invite_by_team_id(team_id, 24) |> elem(1)
      Teams.join_by_invite(invite_code, token)

      conn = log_in_user(conn, user)
      {:ok, _view, html} = live(conn, "/teams/#{team_id}")

      assert html =~ "Claim ownership"
      assert html =~ "This team has no owner"
    end

    test "participant can claim ownership with valid secret", %{conn: conn} do
      # Create team and get the plaintext claim secret
      team_attrs = %{
        name: "claim-test",
        members: [%{name: "dev", role: "development"}],
        skills: [],
        platforms: []
      }
      {:ok, _invite, team_id, claim_secret} = Teams.create_team_with_invite(team_attrs)

      # Create a user who joins as participant
      user = Teamrc.AccountsFixtures.user_fixture()
      token = "trc_ak_claim2_#{System.unique_integer([:positive])}"
      {:ok, _mt} = Accounts.link_machine_token(user.id, token, "claim-machine2")
      invite_code = Teams.create_invite_by_team_id(team_id, 24) |> elem(1)
      Teams.join_by_invite(invite_code, token)

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/teams/#{team_id}")

      # Show claim form
      view |> element("button[phx-click='show_claim_form']") |> render_click()

      # Enter secret
      view |> element("input#claim-secret") |> render_keyup(%{"value" => claim_secret})

      # Submit
      view |> element("button[phx-click='submit_claim']") |> render_click()

      # Should now be owner
      team = Repo.get!(Team, team_id)
      assert team.owner_user_id == user.id
      assert is_nil(team.owner_claim_secret)
    end

    test "claim with invalid secret fails", %{conn: conn} do
      {_code, team_id} = create_team_with_invite()

      user = Teamrc.AccountsFixtures.user_fixture()
      token = "trc_ak_claim3_#{System.unique_integer([:positive])}"
      {:ok, _mt} = Accounts.link_machine_token(user.id, token, "claim-machine3")
      invite_code = Teams.create_invite_by_team_id(team_id, 24) |> elem(1)
      Teams.join_by_invite(invite_code, token)

      conn = log_in_user(conn, user)
      {:ok, view, _html} = live(conn, "/teams/#{team_id}")

      render_click(view, "show_claim_form", %{})
      render_keyup(view, "update_claim_secret", %{"value" => "trc_ocs_wrong_secret"})
      render_click(view, "submit_claim", %{})

      html = render(view)
      assert html =~ "Invalid claim secret"

      # Team should still have no owner
      team = Repo.get!(Team, team_id)
      assert is_nil(team.owner_user_id)
    end

    test "owner does not see claim button", %{conn: conn} do
      %{user: user, team_id: team_id} = create_owner_with_team()
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, "/teams/#{team_id}")

      refute html =~ "Claim ownership"
    end

    test "unauthenticated user cannot claim via event", %{conn: conn} do
      {code, team_id} = create_team_with_invite()

      {:ok, view, _html} = live(conn, "/teams/#{team_id}?invite=#{code}")

      render_click(view, "submit_claim", %{})

      html = render(view)
      assert html =~ "Sign in to claim ownership"

      # Team should still have no owner
      team = Repo.get!(Team, team_id)
      assert is_nil(team.owner_user_id)
    end

    test "logged-in viewer (non-participant) cannot claim via event", %{conn: conn} do
      {_code, team_id} = create_team_with_invite()
      make_team_public(team_id)

      non_participant = Teamrc.AccountsFixtures.user_fixture()
      conn = log_in_user(conn, non_participant)

      {:ok, view, html} = live(conn, "/teams/#{team_id}")

      # Viewer should not see claim UI
      refute html =~ "Claim ownership"

      # Attempt claim via event (bypassing UI)
      render_click(view, "update_claim_secret", %{"value" => "trc_ocs_fake"})
      render_click(view, "submit_claim", %{})

      html = render(view)
      assert html =~ "don&#39;t have permission"

      # Team should still have no owner
      team = Repo.get!(Team, team_id)
      assert is_nil(team.owner_user_id)
    end
  end

  describe "member management" do
    test "owner can add a custom member", %{conn: conn} do
      %{user: user, team_id: team_id} = create_owner_with_team()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, "/teams/#{team_id}")

      # Open member picker
      view |> element("button", "Add team member") |> render_click()

      # Go to custom form
      view |> element("button[phx-click='custom_member']") |> render_click()

      # Fill in form
      view |> element("input#member-name") |> render_keyup(%{"value" => "new-agent"})
      view |> element("input#member-role") |> render_keyup(%{"value" => "testing"})

      # Submit
      view |> element("button[phx-click='add_member']") |> render_click()

      html = render(view)
      assert html =~ "new-agent"
      assert html =~ "testing"
    end

    test "member cards link to member detail page with invite code", %{conn: conn} do
      {code, team_id} = create_team_with_invite()

      {:ok, _view, html} = live(conn, "/teams/#{team_id}?invite=#{code}")

      assert html =~ "/teams/#{team_id}/members/"
      assert html =~ "invite=#{code}"
    end
  end

  describe "skill management" do
    test "owner can add a custom skill", %{conn: conn} do
      %{user: user, team_id: team_id} = create_owner_with_team()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, "/teams/#{team_id}")

      # Open skill picker
      view |> element("button", "Add skill") |> render_click()

      # Go to custom form
      view |> element("button[phx-click='custom_skill']") |> render_click()

      # Fill in form
      view
      |> element("input#skill-id")
      |> render_keyup(%{"field" => "id", "value" => "test-skill"})

      view
      |> element("textarea#skill-body")
      |> render_keyup(%{"field" => "body", "value" => "Do the thing"})

      # Save
      view |> element("button[phx-click='save_skill']") |> render_click()

      html = render(view)
      assert html =~ "test-skill"
    end

    test "owner can delete a skill", %{conn: conn} do
      skills = [%{"id" => "my-skill", "body" => "skill body", "title" => "My Skill"}]
      %{user: user, team_id: team_id} = create_owner_with_team(skills: skills)
      conn = log_in_user(conn, user)

      {:ok, view, html} = live(conn, "/teams/#{team_id}")

      assert html =~ "my-skill"

      view
      |> element("button[phx-click='delete_skill'][phx-value-skill-id='my-skill']")
      |> render_click()

      html = render(view)
      refute html =~ "my-skill"
    end

    test "invite holder cannot delete a skill via event", %{conn: conn} do
      skills = [%{"id" => "my-skill", "body" => "skill body", "title" => "My Skill"}]
      {code, team_id} = create_team_with_invite(skills: skills)

      {:ok, view, _html} = live(conn, "/teams/#{team_id}?invite=#{code}")

      # Attempt to delete skill via event (bypassing UI)
      render_click(view, "delete_skill", %{"skill-id" => "my-skill"})

      # Verify skill was NOT deleted
      team = Teams.get_team_by_id(team_id)
      assert Enum.any?(team.skills, &(&1["id"] == "my-skill"))
    end
  end
end
