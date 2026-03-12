defmodule TeamrcWeb.MemberDetailLiveTest do
  use TeamrcWeb.ConnCase
  import Phoenix.LiveViewTest

  alias Teamrc.{Repo, Teams}
  alias Teamrc.Schema.{Invite, Member, Team}

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

  defp set_invite_expiry!(invite_code, expires_at) do
    expires_at = DateTime.truncate(expires_at, :second)
    invite = Repo.get_by!(Invite, code: invite_code)
    invite |> Ecto.Changeset.change(%{expires_at: expires_at}) |> Repo.update!()
  end

  defp make_team_public(team_id) do
    team = Repo.get!(Team, team_id)
    team |> Ecto.Changeset.change(%{visibility: "public"}) |> Repo.update!()
  end

  # --- Tests: rendering ---

  describe "page rendering" do
    test "loads member detail page with invite access", %{conn: conn} do
      {code, team_id} = create_team_with_invite()
      member = team_member(team_id)

      {:ok, _view, html} = live(conn, "/teams/#{team_id}/members/#{member.id}?invite=#{code}")

      assert html =~ "Name"
      assert html =~ "Role"
      assert html =~ "Instructions"
      assert html =~ "dev"
    end

    test "shows editable fields with invite access", %{conn: conn} do
      {code, team_id} = create_team_with_invite()
      member = team_member(team_id)

      {:ok, view, _html} = live(conn, "/teams/#{team_id}/members/#{member.id}?invite=#{code}")

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
  end

  describe "editing member" do
    test "can update name and role", %{conn: conn} do
      {code, team_id} = create_team_with_invite()
      member = team_member(team_id)

      {:ok, view, _html} = live(conn, "/teams/#{team_id}/members/#{member.id}?invite=#{code}")

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

    test "can update soul/instructions", %{conn: conn} do
      {code, team_id} = create_team_with_invite()
      member = team_member(team_id)

      {:ok, view, _html} = live(conn, "/teams/#{team_id}/members/#{member.id}?invite=#{code}")

      view |> element("textarea[phx-keyup='update_soul']") |> render_keyup(%{"value" => "Be helpful"})
      view |> element("button[phx-click='save']") |> render_click()

      db_member = Repo.get!(Member, member.id)
      assert db_member.soul == "Be helpful"
    end

    test "save with empty name fails", %{conn: conn} do
      {code, team_id} = create_team_with_invite()
      member = team_member(team_id)

      {:ok, view, _html} = live(conn, "/teams/#{team_id}/members/#{member.id}?invite=#{code}")

      view |> element("input[phx-keyup='update_name']") |> render_keyup(%{"value" => ""})
      view |> element("button[phx-click='save']") |> render_click()

      html = render(view)
      assert html =~ "Name and role are required."
    end
  end

  describe "deleting member" do
    test "can delete member and redirects to team page", %{conn: conn} do
      {code, team_id} = create_team_with_invite()
      member = team_member(team_id)

      {:ok, view, _html} = live(conn, "/teams/#{team_id}/members/#{member.id}?invite=#{code}")

      assert {:error, {:redirect, %{to: "/teams/" <> _}}} =
               view |> element("button[phx-click='delete_member']") |> render_click()

      # Verify member is deleted
      assert is_nil(Repo.get(Member, member.id))
    end
  end

  describe "skill toggling" do
    test "can toggle a skill on a member", %{conn: conn} do
      skills = [%{"id" => "test-skill", "body" => "Do things", "title" => "Test"}]

      {code, team_id} =
        create_team_with_invite(
          skills: skills,
          members: [%{name: "dev", role: "development", skills: []}]
        )

      member = team_member(team_id)

      {:ok, view, _html} = live(conn, "/teams/#{team_id}/members/#{member.id}?invite=#{code}")

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

  describe "invite expiry on member detail" do
    test "blocks save after invite expires", %{conn: conn} do
      {code, team_id} = create_team_with_invite()
      set_invite_expiry!(code, DateTime.utc_now() |> DateTime.add(2, :second))
      member = team_member(team_id)

      {:ok, view, _html} = live(conn, "/teams/#{team_id}/members/#{member.id}?invite=#{code}")
      view |> element("input[phx-keyup='update_name']") |> render_keyup(%{"value" => "new-name"})

      Process.sleep(2_500)

      view |> element("button[phx-click='save']") |> render_click()

      html = render(view)
      assert html =~ "This invite has expired or been revoked."

      db_member = Repo.get!(Member, member.id)
      assert db_member.name == member.name
    end
  end
end
