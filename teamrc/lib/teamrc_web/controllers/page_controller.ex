defmodule TeamrcWeb.PageController do
  use TeamrcWeb, :controller

  def health(conn, _params) do
    case Ecto.Adapters.SQL.query(Teamrc.Repo, "SELECT 1", [], timeout: 2_000) do
      {:ok, _} ->
        json(conn, %{status: "ok"})

      {:error, _} ->
        conn
        |> put_status(503)
        |> json(%{status: "unavailable"})
    end
  end
end
