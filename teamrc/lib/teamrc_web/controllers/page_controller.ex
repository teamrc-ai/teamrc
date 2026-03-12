defmodule TeamrcWeb.PageController do
  use TeamrcWeb, :controller

  def index(conn, _params) do
    if conn.assigns[:current_scope] && conn.assigns.current_scope.user do
      redirect(conn, to: ~p"/dashboard")
    else
      redirect(conn, to: ~p"/new")
    end
  end

  def health(conn, _params) do
    Ecto.Adapters.SQL.query!(Teamrc.Repo, "SELECT 1")
    json(conn, %{status: "ok"})
  end
end
