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

    {:ok, invite_code, team_id} = Teams.create_team_with_invite(team, opts)
    {invite_code, team_id}
  end

  defp make_team_public(team_id) do
    team = Repo.get!(Team, team_id)
    team |> Ecto.Changeset.change(%{visibility: "public"}) |> Repo.update!()
  end

  defp create_owner_with_team do
    user = Teamrc.AccountsFixtures.user_fixture()
    {invite_code, team_id} = create_team_with_invite(owner_user_id: user.id)

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
      assert html =~ "Expires in"
    end

    test "shows add member button with invite access", %{conn: conn} do
      {code, team_id} = create_team_with_invite()

      {:ok, view, _html} = live(conn, "/teams/#{team_id}?invite=#{code}")

      assert has_element?(view, "button", "Add team member")
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
    test "shows owner controls (visibility toggle)", %{conn: conn} do
      %{user: user, team_id: team_id} = create_owner_with_team()
      conn = log_in_user(conn, user)

      {:ok, view, html} = live(conn, "/teams/#{team_id}")

      assert html =~ "test-team"
      assert has_element?(view, "button", "Make public")
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

    test "owner can toggle visibility", %{conn: conn} do
      %{user: user, team_id: team_id} = create_owner_with_team()
      conn = log_in_user(conn, user)

      {:ok, view, html} = live(conn, "/teams/#{team_id}")

      assert html =~ "private"
      view |> element("button[phx-click='toggle_visibility']") |> render_click()

      html = render(view)
      assert html =~ "public"
    end
  end

  describe "member management" do
    test "can add a custom member via invite", %{conn: conn} do
      {code, team_id} = create_team_with_invite()

      {:ok, view, _html} = live(conn, "/teams/#{team_id}?invite=#{code}")

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

    test "member cards link to member detail page", %{conn: conn} do
      {code, team_id} = create_team_with_invite()

      {:ok, _view, html} = live(conn, "/teams/#{team_id}?invite=#{code}")

      assert html =~ "/teams/#{team_id}/members/"
      assert html =~ "invite=#{code}"
    end
  end

  describe "skill management" do
    test "can add a custom skill via invite", %{conn: conn} do
      {code, team_id} = create_team_with_invite()

      {:ok, view, _html} = live(conn, "/teams/#{team_id}?invite=#{code}")

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

    test "can delete a skill", %{conn: conn} do
      skills = [%{"id" => "my-skill", "body" => "skill body", "title" => "My Skill"}]
      {code, team_id} = create_team_with_invite(skills: skills)

      {:ok, view, html} = live(conn, "/teams/#{team_id}?invite=#{code}")

      assert html =~ "my-skill"

      view
      |> element("button[phx-click='delete_skill'][phx-value-skill-id='my-skill']")
      |> render_click()

      html = render(view)
      refute html =~ "my-skill"
    end
  end
end
