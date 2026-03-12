defmodule TeamrcWeb.PageControllerTest do
  use TeamrcWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert html_response(conn, 200) =~ "Create a team"
  end
end
