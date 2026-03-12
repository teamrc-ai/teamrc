defmodule TeamrcWeb.PageControllerTest do
  use TeamrcWeb.ConnCase

  test "GET / redirects to /new when not signed in", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == "/new"
  end

  test "GET / redirects to /dashboard when signed in", %{conn: conn} do
    user = Teamrc.AccountsFixtures.user_fixture()

    conn =
      conn
      |> log_in_user(user)
      |> get(~p"/")

    assert redirected_to(conn) == "/dashboard"
  end

  test "GET /health returns ok", %{conn: conn} do
    conn = get(conn, "/health")
    assert json_response(conn, 200) == %{"status" => "ok"}
  end
end
