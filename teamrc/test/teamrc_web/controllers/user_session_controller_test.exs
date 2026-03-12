defmodule TeamrcWeb.UserSessionControllerTest do
  use TeamrcWeb.ConnCase, async: false

  import Teamrc.AccountsFixtures

  setup %{conn: conn} do
    {:ok, conn: conn}
  end

  describe "POST /users/log-in with email+password" do
    test "redirects to dashboard with valid credentials", %{conn: conn} do
      user = user_with_password_fixture()

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"email" => user.email, "password" => user.password}
        })

      assert redirected_to(conn) =~ "/"
      assert get_session(conn, :user_token)
    end

    test "redirects back to login with invalid credentials", %{conn: conn} do
      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"email" => "nobody@example.com", "password" => "wrong_password_1234"}
        })

      assert redirected_to(conn) == ~p"/users/log-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Invalid email or password"
    end

    test "redirects to accept-terms when user has not accepted ToS", %{conn: conn} do
      # Create a user with password but no ToS acceptance
      email = unique_user_email()
      password = valid_user_password()

      {:ok, user} =
        Teamrc.Accounts.register_user(%{
          email: email,
          accepted_terms_at: DateTime.utc_now(:second),
          terms_version_accepted: "2026-03-11"
        })

      {:ok, user} =
        user
        |> Teamrc.Accounts.User.password_changeset(%{password: password})
        |> Teamrc.Repo.update()

      # Clear the terms acceptance to simulate a user who hasn't accepted
      user
      |> Ecto.Changeset.change(%{accepted_terms_at: nil, terms_version_accepted: nil})
      |> Teamrc.Repo.update!()

      conn =
        post(conn, ~p"/users/log-in", %{
          "user" => %{"email" => email, "password" => password}
        })

      # The user should be redirected and a session should exist
      assert redirected_to(conn) =~ "/users/accept-terms"
    end
  end

  describe "DELETE /users/log-out" do
    test "logs out the user and redirects to /", %{conn: conn} do
      user = user_fixture()
      conn = log_in_user(conn, user)

      conn = delete(conn, ~p"/users/log-out")

      assert redirected_to(conn) == ~p"/"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Logged out successfully."
    end
  end

  describe "POST /users/forgot-password" do
    test "sends reset instructions for valid email", %{conn: conn} do
      user = user_fixture()

      conn =
        post(conn, ~p"/users/forgot-password", %{"user" => %{"email" => user.email}})

      assert redirected_to(conn) == ~p"/users/log-in"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "If your email is in our system"
    end

    test "sends same flash for unknown email (no enumeration)", %{conn: conn} do
      conn =
        post(conn, ~p"/users/forgot-password", %{
          "user" => %{"email" => "unknown@example.com"}
        })

      assert redirected_to(conn) == ~p"/users/log-in"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "If your email is in our system"
    end
  end

  describe "POST /users/reset-password/:token" do
    test "resets password with valid token", %{conn: conn} do
      user = user_fixture()

      token =
        extract_user_token(fn url_fun ->
          Teamrc.Accounts.deliver_user_reset_password_instructions(user, url_fun)
        end)

      new_password = "new_valid_password_123"

      conn =
        post(conn, ~p"/users/reset-password/#{token}", %{
          "user" => %{"password" => new_password}
        })

      assert redirected_to(conn) == ~p"/users/log-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Password reset successfully"
    end

    test "returns error with invalid token", %{conn: conn} do
      conn =
        post(conn, ~p"/users/reset-password/invalidtoken", %{
          "user" => %{"password" => "new_valid_password_123"}
        })

      assert redirected_to(conn) == ~p"/users/forgot-password"

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "Reset password link is invalid or it has expired"
    end
  end

  describe "GET /users/complete-login" do
    test "creates session for authenticated user who accepted terms", %{conn: conn} do
      user = user_fixture()
      {:ok, user} = Teamrc.Accounts.accept_terms(user, "2026-03-11")
      conn = log_in_user(conn, user)

      conn = get(conn, ~p"/users/complete-login")

      # Should redirect (log_in_user issues a redirect)
      assert redirected_to(conn)
    end

    test "redirects to login without authentication", %{conn: conn} do
      conn = get(conn, ~p"/users/complete-login")

      assert redirected_to(conn) == ~p"/users/log-in"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "Please log in again"
    end
  end
end
