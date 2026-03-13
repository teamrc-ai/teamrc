defmodule TeamrcWeb.DashboardLiveTest do
  use TeamrcWeb.ConnCase
  import Phoenix.LiveViewTest

  alias Teamrc.{Accounts, Teams}

  # --- Helpers ---

  defp create_user_with_team(opts \\ []) do
    user = Teamrc.AccountsFixtures.user_fixture()
    token = "trc_ak_test_#{System.unique_integer([:positive])}"
    {:ok, _mt} = Accounts.link_machine_token(user.id, token, opts[:machine_name] || "test-machine")

    team_attrs = %{
      name: opts[:team_name] || "my-team",
      members: [%{name: "dev", role: "development"}],
      skills: [],
      platforms: opts[:platforms] || []
    }

    {:ok, invite_code, team_id, _} =
      Teams.create_team_with_invite(team_attrs, owner_user_id: user.id)

    # Join with the user's token so they're a participant
    Teams.join_by_invite(invite_code, token)

    %{user: user, team_id: team_id, token: token, invite_code: invite_code}
  end

  # --- Tests ---

  describe "unauthenticated access" do
    test "redirects to login page", %{conn: conn} do
      assert {:error, {:redirect, %{to: "/users/log-in" <> _}}} =
               live(conn, "/dashboard")
    end
  end

  describe "authenticated with no teams" do
    test "shows empty state", %{conn: conn} do
      user = Teamrc.AccountsFixtures.user_fixture()
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, "/dashboard")

      assert html =~ "Dashboard"
      assert html =~ "No teams yet"
      assert html =~ "Create a team"
      assert html =~ "No machines linked yet"
    end

    test "shows user email in account section", %{conn: conn} do
      user = Teamrc.AccountsFixtures.user_fixture()
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, "/dashboard")

      assert html =~ user.email
      assert html =~ "Signed in"
    end
  end

  describe "authenticated with teams" do
    test "displays team with member count", %{conn: conn} do
      %{user: user, team_id: _team_id} = create_user_with_team(team_name: "cool-team")
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, "/dashboard")

      assert html =~ "cool-team"
      assert html =~ "1 agents"
    end

    test "displays machine info", %{conn: conn} do
      %{user: user} = create_user_with_team(machine_name: "my-laptop")
      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, "/dashboard")

      assert html =~ "my-laptop"
    end

    test "displays multiple teams", %{conn: conn} do
      user = Teamrc.AccountsFixtures.user_fixture()

      # Create two teams
      for name <- ["team-alpha", "team-beta"] do
        token = "trc_ak_test_#{System.unique_integer([:positive])}"
        {:ok, _mt} = Accounts.link_machine_token(user.id, token, "machine-#{name}")

        team_attrs = %{
          name: name,
          members: [%{name: "dev", role: "dev"}],
          skills: [],
          platforms: []
        }

        {:ok, invite_code, _team_id, _} =
          Teams.create_team_with_invite(team_attrs, owner_user_id: user.id)

        Teams.join_by_invite(invite_code, token)
      end

      conn = log_in_user(conn, user)

      {:ok, _view, html} = live(conn, "/dashboard")

      assert html =~ "team-alpha"
      assert html =~ "team-beta"
    end

    test "expanding a team shows members", %{conn: conn} do
      %{user: user, team_id: team_id} = create_user_with_team()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, "/dashboard")

      view
      |> element("button[phx-click='toggle_team'][phx-value-team-id='#{team_id}']")
      |> render_click()

      html = render(view)
      assert html =~ "Members"
      assert html =~ "dev"
      assert html =~ "View team details"
    end

    test "collapsing a team hides details", %{conn: conn} do
      %{user: user, team_id: team_id} = create_user_with_team()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, "/dashboard")

      # Expand
      view
      |> element("button[phx-click='toggle_team'][phx-value-team-id='#{team_id}']")
      |> render_click()

      assert render(view) =~ "View team details"

      # Collapse
      view
      |> element("button[phx-click='toggle_team'][phx-value-team-id='#{team_id}']")
      |> render_click()

      refute render(view) =~ "View team details"
    end
  end

  describe "machine revocation" do
    test "confirm_revoke shows confirmation UI", %{conn: conn} do
      %{user: user, token: token} = create_user_with_team()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, "/dashboard")

      view
      |> element("button[phx-click='confirm_revoke'][phx-value-token='#{token}']")
      |> render_click()

      html = render(view)
      assert html =~ "Revoke access?"
      assert html =~ "Confirm"
      assert html =~ "Cancel"
    end

    test "cancel_revoke hides confirmation", %{conn: conn} do
      %{user: user, token: token} = create_user_with_team()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, "/dashboard")

      view
      |> element("button[phx-click='confirm_revoke'][phx-value-token='#{token}']")
      |> render_click()

      assert render(view) =~ "Revoke access?"

      view |> element("button[phx-click='cancel_revoke']") |> render_click()

      refute render(view) =~ "Revoke access?"
    end

    test "revoking a machine removes it from the list", %{conn: conn} do
      %{user: user, token: token} = create_user_with_team(machine_name: "doomed-machine")
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, "/dashboard")

      assert render(view) =~ "doomed-machine"

      # Confirm revoke
      view
      |> element("button[phx-click='confirm_revoke'][phx-value-token='#{token}']")
      |> render_click()

      view
      |> element("button[phx-click='revoke_machine'][phx-value-token='#{token}']")
      |> render_click()

      html = render(view)
      refute html =~ "doomed-machine"
      assert html =~ "Machine revoked successfully"
    end
  end

  describe "account management" do
    test "confirm_delete_account shows confirmation", %{conn: conn} do
      user = Teamrc.AccountsFixtures.user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, "/dashboard")

      view |> element("button[phx-click='confirm_delete_account']") |> render_click()

      html = render(view)
      assert html =~ "Delete account and all data?"
      assert html =~ "Yes, delete everything"
    end

    test "cancel_delete_account hides confirmation", %{conn: conn} do
      user = Teamrc.AccountsFixtures.user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, "/dashboard")

      view |> element("button[phx-click='confirm_delete_account']") |> render_click()
      assert render(view) =~ "Delete account and all data?"

      view |> element("button[phx-click='cancel_delete_account']") |> render_click()
      refute render(view) =~ "Delete account and all data?"
    end

    test "deleting account redirects to home", %{conn: conn} do
      user = Teamrc.AccountsFixtures.user_fixture()
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, "/dashboard")

      view |> element("button[phx-click='confirm_delete_account']") |> render_click()

      assert {:error, {:redirect, %{to: "/"}}} =
               view |> element("button[phx-click='delete_account']") |> render_click()
    end
  end
end
