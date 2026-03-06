defmodule TeamrcWeb.PageController do
  use TeamrcWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
