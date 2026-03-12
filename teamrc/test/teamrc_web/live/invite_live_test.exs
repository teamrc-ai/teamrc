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

    {:ok, invite_code, team_id} = Teams.create_team_with_invite(team)
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
    set_invite_expiry!(code, DateTime.utc_now() |> DateTime.add(-3600))

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

  test "invite access allows editing on team page", %{conn: conn} do
    {code, team_id} = create_team_with_invite()
    {:ok, view, _html} = live(conn, "/teams/#{team_id}?invite=#{code}")

    assert has_element?(view, "button", "Add team member")
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

    member = team_member(team_id)

    {:ok, _view, html} = live(conn, "/teams/#{team_id}/members/#{member.id}?invite=#{code}")

    assert html =~ "Name"
    assert html =~ "Role"
    assert html =~ "Instructions"
    assert html =~ "Remove member"
  end

  test "can remove a member via invite on detail page", %{conn: conn} do
    {code, team_id} = create_team_with_invite()

    member = team_member(team_id)

    {:ok, view, _html} = live(conn, "/teams/#{team_id}/members/#{member.id}?invite=#{code}")

    assert {:error, {:redirect, %{to: "/teams/" <> _}}} =
             view |> element("button[phx-click='delete_member']") |> render_click()
  end

  test "member detail without invite is denied for unauthenticated users", %{conn: conn} do
    {_code, team_id} = create_team_with_invite()
    member = team_member(team_id)

    assert {:error, {:redirect, %{to: "/teams/" <> rest}}} =
             live(conn, "/teams/#{team_id}/members/#{member.id}")

    assert rest == team_id
  end

  test "member detail blocks save after invite expires", %{conn: conn} do
    {code, team_id} = create_team_with_invite()
    set_invite_expiry!(code, DateTime.utc_now() |> DateTime.add(2, :second))
    member = team_member(team_id)

    {:ok, view, _html} = live(conn, "/teams/#{team_id}/members/#{member.id}?invite=#{code}")
    view |> element("input[phx-keyup='update_name']") |> render_keyup(%{"value" => "new-name"})

    Process.sleep(2_500)

    view |> element("button[phx-click='save']") |> render_click()

    html = render(view)
    assert html =~ "This invite has expired."

    db_member = Repo.get!(Member, member.id)
    assert db_member.name == member.name
  end
end
