defmodule TeamrcWeb.PageControllerTest do
  use TeamrcWeb.ConnCase

  test "GET / renders landing page", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "One team definition"
  end

  test "GET /health returns ok", %{conn: conn} do
    conn = get(conn, "/health")
    assert json_response(conn, 200) == %{"status" => "ok"}
  end
end
