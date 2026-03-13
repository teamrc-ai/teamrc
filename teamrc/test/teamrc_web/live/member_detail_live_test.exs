defmodule TeamrcWeb.MemberDetailLiveTest do
  use TeamrcWeb.ConnCase
  import Phoenix.LiveViewTest

  alias Teamrc.{Accounts, Repo, Teams}
  alias Teamrc.Schema.{Member, Team}

  # --- Helpers ---

  defp create_team_with_invite(opts \\ []) do
    skills = opts[:skills] || []

    team = %{
      name: opts[:name] || "test-team",
      members: opts[:members] || [%{name: "dev", role: "development"}],
      skills: skills,
      platforms: opts[:platforms] || []
    }

    {:ok, invite_code, team_id} = Teams.create_team_with_invite(team, opts)
    {invite_code, team_id}
  end

  defp team_member(team_id) do
    team = Repo.get(Team, team_id) |> Repo.preload(:members)
    hd(team.members)
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

  # --- Tests: rendering ---

  describe "page rendering" do
    test "loads member detail page with invite access", %{conn: conn} do
      {code, team_id} = create_team_with_invite()
      member = team_member(team_id)

      {:ok, _view, html} = live(conn, "/teams/#{team_id}/members/#{member.id}?invite=#{code}")

      assert html =~ "Instructions"
      assert html =~ "dev"
    end

    test "invite holder sees read-only view", %{conn: conn} do
      {code, team_id} = create_team_with_invite()
      member = team_member(team_id)

      {:ok, view, _html} = live(conn, "/teams/#{team_id}/members/#{member.id}?invite=#{code}")

      # Read-only view doesn't have edit inputs
      refute has_element?(view, "input#member-name")
      refute has_element?(view, "input#member-role")
      refute has_element?(view, "textarea#member-soul")
      refute has_element?(view, "button[phx-click='delete_member']")
    end

    test "owner sees editable fields", %{conn: conn} do
      %{user: user, team_id: team_id} = create_owner_with_team()
      conn = log_in_user(conn, user)
      member = team_member(team_id)

      {:ok, view, _html} = live(conn, "/teams/#{team_id}/members/#{member.id}")

      assert has_element?(view, "input#member-name")
      assert has_element?(view, "input#member-role")
      assert has_element?(view, "textarea#member-soul")
      assert has_element?(view, "button[phx-click='delete_member']")
    end

    test "shows read-only view on public team without invite", %{conn: conn} do
      {_code, team_id} = create_team_with_invite()
      make_team_public(team_id)
      member = team_member(team_id)

      {:ok, view, html} = live(conn, "/teams/#{team_id}/members/#{member.id}")

      assert html =~ "dev"
      # Read-only view doesn't have edit inputs
      refute has_element?(view, "input#member-name")
      refute has_element?(view, "button[phx-click='delete_member']")
    end
  end

  describe "access control" do
    test "redirects to team page without access on private team", %{conn: conn} do
      {_code, team_id} = create_team_with_invite()
      member = team_member(team_id)

      assert {:error, {:redirect, %{to: "/teams/" <> rest}}} =
               live(conn, "/teams/#{team_id}/members/#{member.id}")

      assert rest == team_id
    end

    test "redirects for non-existent team", %{conn: conn} do
      fake_team_id = Ecto.UUID.generate()
      fake_member_id = Ecto.UUID.generate()

      assert {:error, {:redirect, %{to: "/new"}}} =
               live(conn, "/teams/#{fake_team_id}/members/#{fake_member_id}")
    end

    test "redirects for non-existent member in valid team", %{conn: conn} do
      {code, team_id} = create_team_with_invite()
      fake_member_id = Ecto.UUID.generate()

      assert {:error, {:redirect, %{to: "/teams/" <> ^team_id}}} =
               live(conn, "/teams/#{team_id}/members/#{fake_member_id}?invite=#{code}")
    end

    test "invite holder cannot save via event", %{conn: conn} do
      {code, team_id} = create_team_with_invite()
      member = team_member(team_id)

      {:ok, view, _html} = live(conn, "/teams/#{team_id}/members/#{member.id}?invite=#{code}")

      # Attempt save via event (bypassing UI which hides the button)
      render_click(view, "save", %{})

      # Verify no changes in database
      db_member = Repo.get!(Member, member.id)
      assert db_member.name == member.name
    end

    test "invite holder cannot delete member via event", %{conn: conn} do
      {code, team_id} = create_team_with_invite()
      member = team_member(team_id)

      {:ok, view, _html} = live(conn, "/teams/#{team_id}/members/#{member.id}?invite=#{code}")

      # Attempt delete via event (bypassing UI which hides the button)
      render_click(view, "delete_member", %{})

      # Member should still exist
      assert Repo.get(Member, member.id)
    end

    test "invite holder cannot toggle skill via event", %{conn: conn} do
      skills = [%{"id" => "test-skill", "body" => "Do things", "title" => "Test"}]

      {code, team_id} =
        create_team_with_invite(
          skills: skills,
          members: [%{name: "dev", role: "development", skills: []}]
        )

      member = team_member(team_id)

      {:ok, view, _html} = live(conn, "/teams/#{team_id}/members/#{member.id}?invite=#{code}")

      # Attempt toggle via event (bypassing UI which hides the button)
      render_click(view, "toggle_skill", %{"skill-id" => "test-skill"})

      # Skill should not be assigned
      db_member = Repo.get!(Member, member.id)
      refute "test-skill" in (db_member.skills || [])
    end
  end

  describe "editing member" do
    test "owner can update name and role", %{conn: conn} do
      %{user: user, team_id: team_id} = create_owner_with_team()
      conn = log_in_user(conn, user)
      member = team_member(team_id)

      {:ok, view, _html} = live(conn, "/teams/#{team_id}/members/#{member.id}")

      # Update name
      view |> element("input[phx-keyup='update_name']") |> render_keyup(%{"value" => "new-name"})
      # Update role
      view |> element("input[phx-keyup='update_role']") |> render_keyup(%{"value" => "new-role"})
      # Save
      view |> element("button[phx-click='save']") |> render_click()

      html = render(view)
      assert html =~ "Saved."

      # Verify in database
      db_member = Repo.get!(Member, member.id)
      assert db_member.name == "new-name"
      assert db_member.role == "new-role"
    end

    test "owner can update soul/instructions", %{conn: conn} do
      %{user: user, team_id: team_id} = create_owner_with_team()
      conn = log_in_user(conn, user)
      member = team_member(team_id)

      {:ok, view, _html} = live(conn, "/teams/#{team_id}/members/#{member.id}")

      view |> element("textarea[phx-keyup='update_soul']") |> render_keyup(%{"value" => "Be helpful"})
      view |> element("button[phx-click='save']") |> render_click()

      db_member = Repo.get!(Member, member.id)
      assert db_member.soul == "Be helpful"
    end

    test "save with empty name fails", %{conn: conn} do
      %{user: user, team_id: team_id} = create_owner_with_team()
      conn = log_in_user(conn, user)
      member = team_member(team_id)

      {:ok, view, _html} = live(conn, "/teams/#{team_id}/members/#{member.id}")

      view |> element("input[phx-keyup='update_name']") |> render_keyup(%{"value" => ""})
      view |> element("button[phx-click='save']") |> render_click()

      html = render(view)
      assert html =~ "Name and role are required."
    end
  end

  describe "deleting member" do
    test "owner can delete member and redirects to team page", %{conn: conn} do
      %{user: user, team_id: team_id} = create_owner_with_team()
      conn = log_in_user(conn, user)
      member = team_member(team_id)

      {:ok, view, _html} = live(conn, "/teams/#{team_id}/members/#{member.id}")

      assert {:error, {:redirect, %{to: "/teams/" <> _}}} =
               view |> element("button[phx-click='delete_member']") |> render_click()

      # Verify member is deleted
      assert is_nil(Repo.get(Member, member.id))
    end
  end

  describe "skill toggling" do
    test "owner can toggle a skill on a member", %{conn: conn} do
      skills = [%{"id" => "test-skill", "body" => "Do things", "title" => "Test"}]

      %{user: user, team_id: team_id} =
        create_owner_with_team(
          skills: skills,
          members: [%{name: "dev", role: "development", skills: []}]
        )

      conn = log_in_user(conn, user)
      member = team_member(team_id)

      {:ok, view, _html} = live(conn, "/teams/#{team_id}/members/#{member.id}")

      # Toggle skill on
      view
      |> element("button[phx-click='toggle_skill'][phx-value-skill-id='test-skill']")
      |> render_click()

      db_member = Repo.get!(Member, member.id)
      assert "test-skill" in db_member.skills

      # Toggle skill off
      view
      |> element("button[phx-click='toggle_skill'][phx-value-skill-id='test-skill']")
      |> render_click()

      db_member = Repo.get!(Member, member.id)
      refute "test-skill" in (db_member.skills || [])
    end
  end
end
