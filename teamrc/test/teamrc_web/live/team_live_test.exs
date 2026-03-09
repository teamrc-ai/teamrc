defmodule TeamrcWeb.TeamLiveTest do
  use TeamrcWeb.ConnCase
  import Phoenix.LiveViewTest

  test "renders template chooser on mount", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/new")
    assert html =~ "Create a team"
    assert html =~ "Pick a starting point"
    assert html =~ "Full-Stack Product"
    assert html =~ "Security Testing"
    assert html =~ "Marketing"
    assert html =~ "Custom"
  end

  test "selecting a template shows the customize form", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/new")

    view |> element("button[phx-value-template='fullstack']") |> render_click()
    html = render(view)

    assert html =~ "Configure your team"
    assert html =~ "product-manager"
    assert html =~ "team-lead"
    assert html =~ "ux-designer"
    assert html =~ "frontend-dev"
    assert html =~ "backend-dev"
    assert html =~ "qa-engineer"
  end

  test "back button returns to template chooser", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/new")

    view |> element("button[phx-value-template='backend']") |> render_click()
    assert render(view) =~ "Configure your team"

    view |> element("button", "Templates") |> render_click()
    assert render(view) =~ "Pick a starting point"
  end

  test "updates team name and enables create button", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/new")

    # Select custom template (pre-fills "my-team")
    view |> element("button[phx-value-template='custom']") |> render_click()
    html = render(view)
    assert html =~ "bg-primary"

    # Clear the name — button should disable
    view |> element("#team-name") |> render_keyup(%{"value" => ""})
    html = render(view)
    assert html =~ "cursor-not-allowed"

    # Set a new name — button should re-enable
    view |> element("#team-name") |> render_keyup(%{"value" => "my-project"})
    html = render(view)
    assert html =~ "bg-primary"
  end

  test "adds catalog agent and removes member", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/new")

    view |> element("button[phx-value-template='custom']") |> render_click()

    # Open agent picker and add a catalog agent
    view |> element("button", "Add agent") |> render_click()
    view |> element("button[phx-click='add_catalog_agent'][phx-value-name='frontend-dev']") |> render_click()
    html = render(view)
    assert html =~ "frontend-dev"

    # Close picker, then remove the agent
    view |> element("button", "Close") |> render_click()
    view |> element("button[phx-click='remove_member'][phx-value-index='0']") |> render_click()
    html = render(view)
    assert html =~ "Add agents from the catalog"
  end

  test "adds custom agent with editable fields", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/new")

    view |> element("button[phx-value-template='custom']") |> render_click()

    # Open agent picker and add custom agent
    view |> element("button", "Add agent") |> render_click()
    view |> element("button", "Custom agent") |> render_click()
    html = render(view)

    # Custom agent shows editable inputs
    assert html =~ "agent-name"
    assert html =~ "Role description"
  end

  test "creates team and shows join command", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/new")

    # Select a template with a pre-filled name
    view |> element("button[phx-value-template='fullstack']") |> render_click()

    # Create team
    view |> element("button", "Create team") |> render_click()

    html = render(view)
    assert html =~ "product-team"
    assert html =~ "npx teamrc join"
    assert html =~ "trc_inv_"
  end

  test "reset returns to template chooser", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/new")

    view |> element("button[phx-value-template='backend']") |> render_click()
    view |> element("button", "Create team") |> render_click()
    assert render(view) =~ "npx teamrc join"

    view |> element("button", "Create another team") |> render_click()
    assert render(view) =~ "Pick a starting point"
  end

  test "security template has expected members", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/new")

    view |> element("button[phx-value-template='security']") |> render_click()
    html = render(view)

    assert html =~ "pentest-lead"
    assert html =~ "vuln-analyst"
    assert html =~ "code-auditor"
    assert html =~ "report-writer"
  end

  test "marketing template has expected members", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/new")

    view |> element("button[phx-value-template='marketing']") |> render_click()
    html = render(view)

    assert html =~ "marketing-lead"
    assert html =~ "copywriter"
    assert html =~ "seo-specialist"
    assert html =~ "analytics-lead"
  end

  test "per-member skill assignment is visible on template teams", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/new")

    # Select fullstack template (has skills)
    view |> element("button[phx-value-template='fullstack']") |> render_click()
    html = render(view)

    # Skills should appear as toggleable chips on each member (no Advanced toggle needed)
    assert html =~ "write-tests"
    assert html =~ "small-commits"

    # Toggle a skill on a member
    view
    |> element("button[phx-click='toggle_member_skill'][phx-value-member-index='0'][phx-value-skill-id='write-tests']")
    |> render_click()

    html = render(view)
    assert html =~ "bg-primary/15"
  end

  test "skill picker toggles catalog skills", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/new")

    view |> element("button[phx-value-template='custom']") |> render_click()

    # Open skill picker
    view |> element("button", "Add skill") |> render_click()
    html = render(view)
    assert html =~ "write-tests"
    assert html =~ "tdd"

    # Add a skill via the picker
    view |> element("button[phx-click='toggle_catalog_skill'][phx-value-id='tdd']") |> render_click()
    html = render(view)
    # Should show as a chip above the picker
    assert html =~ "tdd"

    # Close picker and remove via the chip's X button
    view |> element("button", "Close") |> render_click()
    view |> element("button[aria-label='Remove tdd']") |> render_click()
    html = render(view)
    assert html =~ "No skills yet"
  end

  test "agent picker search filters agents", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/new")

    view |> element("button[phx-value-template='custom']") |> render_click()
    view |> element("button", "Add agent") |> render_click()

    # Search for "frontend"
    view |> element("input[placeholder='Search agents...']") |> render_keyup(%{"value" => "frontend"})
    html = render(view)
    assert html =~ "frontend-dev"
    refute html =~ "backend-dev"
  end
end
