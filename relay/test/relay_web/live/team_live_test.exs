defmodule TeambridgeWeb.TeamLiveTest do
  use TeambridgeWeb.ConnCase
  import Phoenix.LiveViewTest

  test "renders team creation form", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")
    assert html =~ "Create a Team"
    assert html =~ "Team name"
    assert html =~ "Team members"
  end

  test "updates team name and enables create button", %{conn: conn} do
    {:ok, view, html} = live(conn, "/")
    # Initially button should be disabled
    assert html =~ "bg-zinc-300"
    assert html =~ "cursor-not-allowed"

    # Simulate keyup on team name input
    view |> element("#team-name") |> render_keyup(%{"value" => "my-project"})
    html = render(view)
    # Create button should now be enabled (bg-zinc-900 instead of bg-zinc-300)
    assert html =~ "bg-zinc-900"
  end

  test "adds and removes team members", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    # Add a member
    view |> element("button", "Add member") |> render_click()
    html = render(view)
    # Should now have 2 member sections (look for placeholder text)
    assert length(Regex.scan(~r/Agent name/, html)) == 2

    # Remove second member (index 1)
    view |> element("button[phx-value-index='1']") |> render_click()
    html = render(view)
    assert length(Regex.scan(~r/Agent name/, html)) == 1
  end

  test "creates team and shows join command", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    # Set team name
    view |> element("#team-name") |> render_keyup(%{"value" => "test-team"})

    # Set member name and role via the update_member event
    render_keyup(view, "update_member", %{"index" => "0", "field" => "name", "value" => "architect"})
    render_keyup(view, "update_member", %{"index" => "0", "field" => "role", "value" => "System design"})

    # Create team
    view |> element("button", "Create Team") |> render_click()

    html = render(view)
    assert html =~ "test-team"
    assert html =~ "npx teambridge join"
    assert html =~ "tb_ak_"
  end

  test "reset returns to form", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    # Create a team first
    view |> element("#team-name") |> render_keyup(%{"value" => "test"})
    view |> element("button", "Create Team") |> render_click()
    assert render(view) =~ "npx teambridge join"

    # Reset
    view |> element("button", "Create another team") |> render_click()
    assert render(view) =~ "Create a Team"
  end

  test "cannot create team with empty name", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")
    # Button should be disabled
    assert html =~ "bg-zinc-300"
    assert html =~ "cursor-not-allowed"
  end

  test "cannot remove member when only one exists", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")
    # With only one member, remove button should not be rendered
    refute html =~ "Remove member"
  end
end
