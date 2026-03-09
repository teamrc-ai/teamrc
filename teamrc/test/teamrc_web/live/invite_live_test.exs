defmodule TeamrcWeb.InviteLiveTest do
  use TeamrcWeb.ConnCase
  import Phoenix.LiveViewTest

  alias Teamrc.Teams

  defp create_team_with_invite do
    team = %{
      name: "test-team",
      members: [%{name: "dev", role: "development"}],
      skills: [],
      platforms: []
    }

    {:ok, invite_code, team_id} = Teams.create_team_with_invite(team)
    {invite_code, team_id}
  end

  test "valid invite redirects to team dashboard", %{conn: conn} do
    {code, team_id} = create_team_with_invite()

    assert {:error, {:redirect, %{to: "/teams/" <> rest}}} = live(conn, "/invite/#{code}")
    assert rest =~ team_id
    assert rest =~ "invite=#{code}"
  end

  test "invalid invite redirects to /new", %{conn: conn} do
    assert {:error, {:redirect, %{to: "/new"}}} = live(conn, "/invite/trc_inv_nonexistent")
  end

  test "team dashboard shows join command via invite", %{conn: conn} do
    {code, team_id} = create_team_with_invite()
    {:ok, _view, html} = live(conn, "/teams/#{team_id}?invite=#{code}")

    assert html =~ "test-team"
    assert html =~ "dev"
    assert html =~ "npx teamrc join #{code}"
    assert html =~ "copy"
    assert html =~ "Expires in"
  end

  test "can add a member via invite access", %{conn: conn} do
    {code, team_id} = create_team_with_invite()
    {:ok, view, _html} = live(conn, "/teams/#{team_id}?invite=#{code}")

    view |> element("button", "Add team member") |> render_click()

    view |> element("input[placeholder='agent-name']") |> render_keyup(%{"value" => "new-agent"})
    view |> element("input[placeholder='Role description']") |> render_keyup(%{"value" => "testing"})
    view |> element("button[phx-click='add_member']", "Add") |> render_click()

    html = render(view)
    assert html =~ "new-agent"
    assert html =~ "testing"
  end

  test "member cards link to member detail page", %{conn: conn} do
    {code, team_id} = create_team_with_invite()
    {:ok, _view, html} = live(conn, "/teams/#{team_id}?invite=#{code}")

    assert html =~ "dev"
    # Member cards are links to the detail page with invite code preserved
    assert html =~ "/teams/#{team_id}/members/"
    assert html =~ "invite=#{code}"
  end

  test "member detail page loads via invite access", %{conn: conn} do
    {code, team_id} = create_team_with_invite()

    # Get the member id from the team
    team = Teamrc.Repo.get(Teamrc.Schema.Team, team_id) |> Teamrc.Repo.preload(:members)
    member = hd(team.members)

    {:ok, _view, html} = live(conn, "/teams/#{team_id}/members/#{member.id}?invite=#{code}")

    # Should show editable fields
    assert html =~ "Name"
    assert html =~ "Role"
    assert html =~ "Instructions"
    assert html =~ "Remove member"
  end

  test "can remove a member via invite on detail page", %{conn: conn} do
    {code, team_id} = create_team_with_invite()

    team = Teamrc.Repo.get(Teamrc.Schema.Team, team_id) |> Teamrc.Repo.preload(:members)
    member = hd(team.members)

    {:ok, view, _html} = live(conn, "/teams/#{team_id}/members/#{member.id}?invite=#{code}")

    assert {:error, {:redirect, %{to: "/teams/" <> _}}} =
             view |> element("button[phx-click='delete_member']") |> render_click()
  end
end
