defmodule TeambridgeWeb.TeamLiveTest do
  use TeambridgeWeb.ConnCase
  import Phoenix.LiveViewTest

  test "renders template chooser on mount", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/")
    assert html =~ "Create a team"
    assert html =~ "Pick a starting point"
    assert html =~ "Full-Stack Product"
    assert html =~ "Security Testing"
    assert html =~ "Marketing"
    assert html =~ "Custom Team"
  end

  test "selecting a template shows the customize form", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

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
    {:ok, view, _html} = live(conn, "/")

    view |> element("button[phx-value-template='backend']") |> render_click()
    assert render(view) =~ "Configure your team"

    view |> element("button", "Templates") |> render_click()
    assert render(view) =~ "Pick a starting point"
  end

  test "updates team name and enables create button", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    # Select custom template (empty name)
    view |> element("button[phx-value-template='custom']") |> render_click()
    html = render(view)
    assert html =~ "cursor-not-allowed"

    # Set a team name
    view |> element("#team-name") |> render_keyup(%{"value" => "my-project"})
    html = render(view)
    assert html =~ "bg-primary"
  end

  test "adds and removes team members", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    view |> element("button[phx-value-template='custom']") |> render_click()

    # Add a member
    view |> element("button", "Add member") |> render_click()
    html = render(view)
    assert length(Regex.scan(~r/agent-name/, html)) == 2

    # Remove second member (index 1)
    view |> element("button[phx-click='remove_member'][phx-value-index='1']") |> render_click()
    html = render(view)
    assert length(Regex.scan(~r/agent-name/, html)) == 1
  end

  test "creates team and shows join command", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    # Select a template with a pre-filled name
    view |> element("button[phx-value-template='fullstack']") |> render_click()

    # Create team
    view |> element("button", "Create team") |> render_click()

    html = render(view)
    assert html =~ "product-team"
    assert html =~ "npx teambridge join"
    assert html =~ "tb_inv_"
  end

  test "reset returns to template chooser", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    view |> element("button[phx-value-template='backend']") |> render_click()
    view |> element("button", "Create team") |> render_click()
    assert render(view) =~ "npx teambridge join"

    view |> element("button", "Create another team") |> render_click()
    assert render(view) =~ "Pick a starting point"
  end

  test "security template has expected members", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    view |> element("button[phx-value-template='security']") |> render_click()
    html = render(view)

    assert html =~ "pentest-lead"
    assert html =~ "vuln-analyst"
    assert html =~ "code-auditor"
    assert html =~ "report-writer"
  end

  test "marketing template has expected members", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    view |> element("button[phx-value-template='marketing']") |> render_click()
    html = render(view)

    assert html =~ "marketing-lead"
    assert html =~ "copywriter"
    assert html =~ "seo-specialist"
    assert html =~ "analytics-lead"
  end

  test "per-member rule assignment toggles", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/")

    # Select fullstack template (has rules)
    view |> element("button[phx-value-template='fullstack']") |> render_click()

    # Enable advanced mode
    view |> element("button", "Advanced") |> render_click()
    html = render(view)

    # Rules should appear as toggleable chips on each member
    assert html =~ "write-tests"
    assert html =~ "small-commits"

    # Toggle a rule on a member
    view |> element("button[phx-click='toggle_member_rule'][phx-value-member-index='0'][phx-value-rule-id='write-tests']") |> render_click()
    html = render(view)
    assert html =~ "bg-primary/15"
  end
end
