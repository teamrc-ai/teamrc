defmodule TeamrcWeb.TeamLiveTest do
  use TeamrcWeb.ConnCase
  import Phoenix.LiveViewTest

  test "renders template chooser", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/new")
    assert html =~ "One team. Every platform. Always in sync."
    assert html =~ "Create a team"
    assert html =~ "Full-Stack Product"
    assert html =~ "Security Testing"
    assert html =~ "Marketing"
    assert html =~ "Custom"
  end

  test "selecting a template creates team and redirects to team dashboard", %{conn: conn} do
    conn = post(conn, "/teams/create-web", %{"template" => "fullstack"})
    assert redirected_to(conn) =~ "/teams/"
  end

  test "custom template creates and redirects", %{conn: conn} do
    conn = post(conn, "/teams/create-web", %{"template" => "custom"})
    assert redirected_to(conn) =~ "/teams/"
  end

  test "template cards show member chips", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/new")

    assert html =~ "product-manager"
    assert html =~ "frontend-dev"
    assert html =~ "backend-dev"
  end

  test "unknown template returns error flash", %{conn: conn} do
    conn = post(conn, "/teams/create-web", %{"template" => "nonexistent"})
    assert redirected_to(conn) == "/new"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Unknown template"
  end

  test "creator session is set for non-logged-in user", %{conn: conn} do
    conn = post(conn, "/teams/create-web", %{"template" => "fullstack"})
    "/teams/" <> team_id = redirected_to(conn)
    creator_sessions = get_session(conn, "creator_sessions")
    assert is_map(creator_sessions)
    assert Map.has_key?(creator_sessions, team_id)
  end
end
