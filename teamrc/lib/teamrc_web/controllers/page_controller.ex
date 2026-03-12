defmodule TeamrcWeb.PageController do
  use TeamrcWeb, :controller

  def index(conn, _params) do
    if get_session(conn, "clerk_user_id") do
      redirect(conn, to: ~p"/dashboard")
    else
      redirect(conn, to: ~p"/new")
    end
  end

  def sign_out(conn, _params) do
    conn
    |> clear_session()
    |> redirect(to: ~p"/")
  end
end
