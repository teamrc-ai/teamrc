defmodule TeamrcWeb.InviteLive do
  use TeamrcWeb, :live_view

  alias Teamrc.Repo
  alias Teamrc.Schema.Invite
  import Ecto.Query

  @impl true
  def mount(%{"code" => code}, _session, socket) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case Repo.one(from(i in Invite, where: i.code == ^code)) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Invite not found.")
         |> redirect(to: ~p"/new")}

      %Invite{expires_at: expires_at} when expires_at <= now ->
        {:ok,
         socket
         |> put_flash(:error, "This invite has expired.")
         |> redirect(to: ~p"/new")}

      %Invite{team_id: team_id, code: invite_code} ->
        {:ok, redirect(socket, to: "/teams/#{team_id}?invite=#{invite_code}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H""
  end
end
