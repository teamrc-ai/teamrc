defmodule TeamrcWeb.InviteLiveTest do
  use TeamrcWeb.ConnCase
  import Phoenix.LiveViewTest

  alias Teamrc.{Repo, Teams}
  alias Teamrc.Schema.{Invite, Member, Team}

  defp create_team_with_invite do
    team = %{
      name: "test-team",
      members: [%{name: "dev", role: "development"}],
      skills: [],
      platforms: []
    }

    {:ok, invite_code, team_id, _} = Teams.create_team_with_invite(team)
    {invite_code, team_id}
  end

  defp team_member(team_id) do
    team = Repo.get(Team, team_id) |> Repo.preload(:members)
    hd(team.members)
  end

  test "valid invite redirects to team dashboard via flash", %{conn: conn} do
    {code, team_id} = create_team_with_invite()

    assert {:error, {:redirect, %{to: "/teams/" <> rest, flash: flash}}} =
             live(conn, "/invite/#{code}")

    assert rest =~ team_id
    assert flash["invite_code"] == code
  end

  test "invalid invite renders error page", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/invite/trc_inv_nonexistent")
    assert html =~ "Invalid Invite"
    assert html =~ "This invite has expired or is invalid"
  end

  test "expired invite shows error page instead of redirect", %{conn: conn} do
    {code, _team_id} = create_team_with_invite()

    expires_at = DateTime.utc_now() |> DateTime.add(-3600) |> DateTime.truncate(:second)
    invite = Repo.get_by!(Invite, code: code)
    invite |> Ecto.Changeset.change(%{expires_at: expires_at}) |> Repo.update!()

    {:ok, _view, html} = live(conn, "/invite/#{code}")
    assert html =~ "Invite Expired"
    assert html =~ "This invite has expired or is invalid"
    assert html =~ "Create a new team"
  end

  test "team dashboard shows join command via invite", %{conn: conn} do
    {code, team_id} = create_team_with_invite()
    {:ok, _view, html} = live(conn, "/teams/#{team_id}?invite=#{code}")

    assert html =~ "test-team"
    assert html =~ "dev"
    assert html =~ "npx @teamrc/cli join #{code}"
    assert html =~ "copy"
    assert html =~ "Expires in"
  end

  test "private team dashboard without invite is gated", %{conn: conn} do
    {_code, team_id} = create_team_with_invite()
    {:ok, _view, html} = live(conn, "/teams/#{team_id}")

    assert html =~ "This team is private"
    assert html =~ "You need an invite code to view this team."
  end

  test "invite access gives read-only view on team page", %{conn: conn} do
    {code, team_id} = create_team_with_invite()
    {:ok, view, html} = live(conn, "/teams/#{team_id}?invite=#{code}")

    # Invite holder can view the team
    assert html =~ "test-team"
    assert html =~ "dev"

    # But cannot see edit controls
    refute has_element?(view, "button", "Add team member")
    refute has_element?(view, "button", "Add skill")
  end

  test "member cards link to member detail page", %{conn: conn} do
    {code, team_id} = create_team_with_invite()
    {:ok, _view, html} = live(conn, "/teams/#{team_id}?invite=#{code}")

    assert html =~ "dev"
    # Member cards are links to the detail page with invite code preserved
    assert html =~ "/teams/#{team_id}/members/"
    assert html =~ "invite=#{code}"
  end

  test "member detail page loads via invite access as read-only", %{conn: conn} do
    {code, team_id} = create_team_with_invite()

    member = team_member(team_id)

    {:ok, view, html} = live(conn, "/teams/#{team_id}/members/#{member.id}?invite=#{code}")

    # Can view the member
    assert html =~ "Instructions"
    assert html =~ "dev"

    # But read-only: no edit inputs or delete button
    refute has_element?(view, "input#member-name")
    refute has_element?(view, "button[phx-click='delete_member']")
  end

  test "invite holder cannot remove a member via event", %{conn: conn} do
    {code, team_id} = create_team_with_invite()

    member = team_member(team_id)

    {:ok, view, _html} = live(conn, "/teams/#{team_id}/members/#{member.id}?invite=#{code}")

    # Attempt delete via event (bypassing UI)
    render_click(view, "delete_member", %{})

    # Member should still exist
    assert Repo.get(Member, member.id)
  end

  test "member detail without invite is denied for unauthenticated users", %{conn: conn} do
    {_code, team_id} = create_team_with_invite()
    member = team_member(team_id)

    assert {:error, {:redirect, %{to: "/teams/" <> rest}}} =
             live(conn, "/teams/#{team_id}/members/#{member.id}")

    assert rest == team_id
  end
end
