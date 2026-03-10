defmodule TeamrcWeb.PageControllerTest do
  use TeamrcWeb.ConnCase

  test "GET / redirects to /new when not signed in", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == "/new"
  end

  test "GET / redirects to /dashboard when signed in", %{conn: conn} do
    conn =
      conn
      |> init_test_session(%{"clerk_user_id" => "test_user", "clerk_email" => "test@example.com"})
      |> get(~p"/")

    assert redirected_to(conn) == "/dashboard"
  end

  test "GET /health returns ok", %{conn: conn} do
    conn = get(conn, "/health")
    assert json_response(conn, 200) == %{"status" => "ok"}
  end

  test "GET /auth/sign-out clears session and redirects", %{conn: conn} do
    conn =
      conn
      |> init_test_session(%{"clerk_user_id" => "test_user"})
      |> get(~p"/auth/sign-out")

    assert redirected_to(conn) == "/"
  end
end
