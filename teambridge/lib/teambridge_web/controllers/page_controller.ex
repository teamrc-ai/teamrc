defmodule TeambridgeWeb.PageController do
  use TeambridgeWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
