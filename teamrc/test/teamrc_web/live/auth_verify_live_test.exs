defmodule TeamrcWeb.AuthVerifyLiveTest do
  use TeamrcWeb.ConnCase
  import Phoenix.LiveViewTest

  alias Teamrc.DeviceAuth

  # --- Helpers ---

  defp create_device_request do
    token = "trc_ak_test_#{System.unique_integer([:positive])}"
    {:ok, request} = DeviceAuth.create_request(token)
    {request, token}
  end

  # --- Tests ---

  describe "unauthenticated user" do
    test "shows sign-in step without code", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/auth/verify")

      assert html =~ "Sign in to continue"
      assert html =~ "Sign in"
    end

    test "shows sign-in step with code in params", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/auth/verify?code=ABCD-1234")

      assert html =~ "Sign in to continue"
      assert html =~ "ABCD-1234"
    end
  end

  describe "authenticated user" do
    setup %{conn: conn} do
      user = Teamrc.AccountsFixtures.user_fixture()
      conn = log_in_user(conn, user)
      %{conn: conn, user: user}
    end

    test "shows enter code step when no code provided", %{conn: conn, user: user} do
      {:ok, _view, html} = live(conn, "/auth/verify")

      assert html =~ "Link your machine"
      assert html =~ "Enter the code shown in your terminal"
      assert html =~ user.email
    end

    test "shows consent step when valid code is in params", %{conn: conn, user: user} do
      {:ok, _view, html} = live(conn, "/auth/verify?code=ABCD-1234")

      assert html =~ "Confirm device link"
      assert html =~ "ABCD-1234"
      assert html =~ user.email
      assert html =~ "Security check"
    end

    test "code formatting auto-uppercases and inserts dash", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/auth/verify")

      view |> element("input#user-code") |> render_keyup(%{"value" => "abcd1234"})

      html = render(view)
      assert html =~ "ABCD-1234"
    end

    test "submit_code with invalid format shows error", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/auth/verify")

      view |> element("input#user-code") |> render_keyup(%{"value" => "AB"})
      view |> element("form") |> render_submit()

      html = render(view)
      assert html =~ "Please enter a valid 8-character code"
    end

    test "submit_code with valid format transitions to consent", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/auth/verify")

      view |> element("input#user-code") |> render_keyup(%{"value" => "ABCD1234"})
      view |> element("form") |> render_submit()

      html = render(view)
      assert html =~ "Confirm device link"
    end

    test "cancel from consent goes back to enter code", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/auth/verify?code=ABCD-1234")

      # Should be in consent step
      assert render(view) =~ "Confirm device link"

      view |> element("button[phx-click='cancel']") |> render_click()

      html = render(view)
      assert html =~ "Link your machine"
    end

    test "confirm with invalid/expired code shows error", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/auth/verify?code=ZZZZ-9999")

      view |> element("button[phx-click='confirm']") |> render_click()

      html = render(view)
      assert html =~ "expired or is invalid"
    end

    test "confirm with valid device code shows success", %{conn: conn} do
      {request, _token} = create_device_request()

      {:ok, view, _html} = live(conn, "/auth/verify?code=#{request.user_code}")

      assert render(view) =~ "Confirm device link"

      view |> element("button[phx-click='confirm']") |> render_click()

      html = render(view)
      assert html =~ "Machine linked"
      assert html =~ "Go to dashboard"
    end
  end
end
