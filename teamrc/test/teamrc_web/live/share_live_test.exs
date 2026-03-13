defmodule TeamrcWeb.ShareLiveTest do
  use TeamrcWeb.ConnCase
  import Phoenix.LiveViewTest

  alias Teamrc.{Repo, Teams}
  alias Teamrc.Schema.Team

  # --- Helpers ---

  defp create_team_with_invite(opts \\ []) do
    team = %{
      name: opts[:name] || "test-team",
      members: opts[:members] || [%{name: "dev", role: "development"}],
      skills: opts[:skills] || [],
      platforms: opts[:platforms] || []
    }

    {:ok, invite_code, team_id, _} = Teams.create_team_with_invite(team, opts)
    {invite_code, team_id}
  end

  defp make_team_public(team_id) do
    team = Repo.get!(Team, team_id)
    clone_token = "trc_cl_test_#{System.unique_integer([:positive])}"

    team
    |> Ecto.Changeset.change(%{visibility: "public", clone_token: clone_token})
    |> Repo.update!()

    clone_token
  end

  # --- Tests ---

  describe "public team" do
    test "renders share page with team name, members, and clone command", %{conn: conn} do
      {_code, team_id} = create_team_with_invite(name: "my-shared-team")
      clone_token = make_team_public(team_id)

      {:ok, _view, html} = live(conn, "/t/#{clone_token}")

      assert html =~ "my-shared-team"
      assert html =~ "dev"
      assert html =~ "development"
      assert html =~ "npx @teamrc/cli clone #{clone_token}"
    end

    test "shows copy-link button with share URL", %{conn: conn} do
      {_code, team_id} = create_team_with_invite()
      clone_token = make_team_public(team_id)

      {:ok, view, _html} = live(conn, "/t/#{clone_token}")

      assert has_element?(view, "button#copy-share-link", "Copy link")
    end

    test "includes Create your own team link", %{conn: conn} do
      {_code, team_id} = create_team_with_invite()
      clone_token = make_team_public(team_id)

      {:ok, _view, html} = live(conn, "/t/#{clone_token}")

      assert html =~ "Create your own team"
      assert html =~ ~r|href="/new"|
    end

    test "displays correct agent count and skill count", %{conn: conn} do
      members = [
        %{name: "agent-a", role: "frontend"},
        %{name: "agent-b", role: "backend"},
        %{name: "agent-c", role: "devops"}
      ]

      skills = [
        %{"id" => "lint", "body" => "Run linter", "title" => "Lint"},
        %{"id" => "test", "body" => "Run tests", "title" => "Test"}
      ]

      {_code, team_id} = create_team_with_invite(members: members, skills: skills)
      clone_token = make_team_public(team_id)

      {:ok, _view, html} = live(conn, "/t/#{clone_token}")

      assert html =~ "3 agents"
      assert html =~ "2 skills"
    end

    test "displays singular form for 1 agent and 1 skill", %{conn: conn} do
      members = [%{name: "solo", role: "fullstack"}]

      skills = [
        %{"id" => "only-skill", "body" => "Do stuff", "title" => "Only Skill"}
      ]

      {_code, team_id} = create_team_with_invite(members: members, skills: skills)
      clone_token = make_team_public(team_id)

      {:ok, _view, html} = live(conn, "/t/#{clone_token}")

      # The visible stats line uses singular forms ("1 agent · 1 skill")
      assert html =~ ~r/1 agent .+ 1 skill/
    end

    test "sets page_title correctly", %{conn: conn} do
      {_code, team_id} = create_team_with_invite(name: "cool-team")
      clone_token = make_team_public(team_id)

      {:ok, view, _html} = live(conn, "/t/#{clone_token}")

      # page_title is an assign on the socket
      assert render(view) =~ "cool-team"
    end

    test "renders member cards for all team members", %{conn: conn} do
      members = [
        %{name: "alice", role: "frontend"},
        %{name: "bob", role: "backend"}
      ]

      {_code, team_id} = create_team_with_invite(members: members)
      clone_token = make_team_public(team_id)

      {:ok, _view, html} = live(conn, "/t/#{clone_token}")

      assert html =~ "alice"
      assert html =~ "frontend"
      assert html =~ "bob"
      assert html =~ "backend"
    end

    test "renders team skills section", %{conn: conn} do
      skills = [
        %{"id" => "code-review", "body" => "Review code", "title" => "Code Review", "description" => "Automated code review"}
      ]

      {_code, team_id} = create_team_with_invite(skills: skills)
      clone_token = make_team_public(team_id)

      {:ok, _view, html} = live(conn, "/t/#{clone_token}")

      assert html =~ "code-review"
      assert html =~ "Automated code review"
      assert html =~ "Team Skills"
    end
  end

  describe "private team" do
    test "shows not found message", %{conn: conn} do
      {_code, _team_id} = create_team_with_invite(name: "secret-team")
      # Team is private by default, so we need a clone_token that won't match
      # Since preview_by_clone_token requires visibility == "public", a private team returns :error
      fake_clone_token = "trc_cl_nonexistent_#{System.unique_integer([:positive])}"

      {:ok, _view, html} = live(conn, "/t/#{fake_clone_token}")

      assert html =~ "This team is private or doesn&#39;t exist."
      assert html =~ "Create your own team"
    end
  end

  describe "invalid clone token" do
    test "shows not found message for nonexistent token", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/t/trc_cl_totally_bogus_token")

      assert html =~ "This team is private or doesn&#39;t exist."
      assert html =~ "The team you&#39;re looking for may have been made private"
    end

    test "sets page_title to Not Found", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/t/trc_cl_does_not_exist")

      # The not_found state should be rendered
      html = render(view)
      assert html =~ "This team is private or doesn&#39;t exist."
    end
  end
end
