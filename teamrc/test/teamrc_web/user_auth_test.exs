defmodule TeamrcWeb.UserAuthTest do
  use TeamrcWeb.ConnCase, async: false

  import Teamrc.AccountsFixtures

  alias Teamrc.Accounts
  alias TeamrcWeb.UserAuth

  setup %{conn: conn} do
    conn =
      conn
      |> Map.replace!(:secret_key_base, TeamrcWeb.Endpoint.config(:secret_key_base))
      |> init_test_session(%{})

    {:ok, conn: conn}
  end

  describe "fetch_current_scope_for_user/2" do
    test "assigns current_scope with valid session token", %{conn: conn} do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)

      conn =
        conn
        |> put_session(:user_token, token)
        |> UserAuth.fetch_current_scope_for_user([])

      assert conn.assigns.current_scope.user.id == user.id
    end

    test "assigns nil current_scope when no token in session", %{conn: conn} do
      conn = UserAuth.fetch_current_scope_for_user(conn, [])

      assert is_nil(conn.assigns.current_scope)
    end
  end

  describe "require_authenticated_user/2" do
    test "passes through for authenticated user with accepted ToS", %{conn: conn} do
      user = user_fixture()
      {:ok, user} = Accounts.accept_terms(user, "2026-03-11")

      conn =
        conn
        |> assign(:current_scope, %Accounts.Scope{user: user})
        |> UserAuth.require_authenticated_user([])

      refute conn.halted
    end

    test "redirects to login without authentication", %{conn: conn} do
      conn =
        conn
        |> assign(:current_scope, nil)
        |> Phoenix.ConnTest.fetch_flash()
        |> UserAuth.require_authenticated_user([])

      assert conn.halted
      assert redirected_to(conn) == ~p"/users/log-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "You must log in"
    end

    test "redirects to accept-terms when user has not accepted ToS", %{conn: conn} do
      user = user_fixture()

      # Clear ToS acceptance
      user =
        user
        |> Ecto.Changeset.change(%{accepted_terms_at: nil, terms_version_accepted: nil})
        |> Teamrc.Repo.update!()

      conn =
        conn
        |> assign(:current_scope, %Accounts.Scope{user: user})
        |> Phoenix.ConnTest.fetch_flash()
        |> UserAuth.require_authenticated_user([])

      assert conn.halted
      assert redirected_to(conn) == ~p"/users/accept-terms"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "You must accept the Terms of Service"
    end
  end

  describe "log_in_user/3" do
    test "sets session token and redirects", %{conn: conn} do
      user = user_fixture()

      conn =
        conn
        |> fetch_flash()
        |> UserAuth.log_in_user(user)

      assert get_session(conn, :user_token)
      assert redirected_to(conn)
    end

    test "sets remember_me cookie when requested", %{conn: conn} do
      user = user_fixture()

      conn =
        conn
        |> fetch_flash()
        |> UserAuth.log_in_user(user, %{"remember_me" => "true"})

      assert conn.resp_cookies["_teamrc_web_user_remember_me"]
    end
  end

  describe "log_out_user/1" do
    test "clears session and redirects to /", %{conn: conn} do
      user = user_fixture()

      conn =
        conn
        |> log_in_user(user)
        |> fetch_flash()
        |> UserAuth.log_out_user()

      refute get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/"
    end
  end

  describe "renew_session (via log_out_user)" do
    test "log_out_user with nil session token does not crash", %{conn: conn} do
      # No user logged in, session has no :user_token
      conn =
        conn
        |> fetch_flash()
        |> UserAuth.log_out_user()

      refute get_session(conn, :user_token)
      assert redirected_to(conn) == ~p"/"
    end
  end

end
