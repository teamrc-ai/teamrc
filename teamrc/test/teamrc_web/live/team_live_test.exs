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
    {:ok, view, _html} = live(conn, "/new")

    assert {:error, {:redirect, %{to: "/teams/" <> _rest}}} =
             view |> element("button[phx-value-template='fullstack']") |> render_click()
  end

  test "custom template creates and redirects", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/new")

    assert {:error, {:redirect, %{to: "/teams/" <> _rest}}} =
             view |> element("button[phx-value-template='custom']") |> render_click()
  end

  test "template cards show member chips", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/new")

    assert html =~ "product-manager"
    assert html =~ "frontend-dev"
    assert html =~ "backend-dev"
  end
end
