defmodule TeamrcWeb.InviteLive do
  use TeamrcWeb, :live_view

  alias Teamrc.Teams
  alias Teamrc.Schema.Invite

  @impl true
  def mount(%{"code" => code}, _session, socket) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    case Teams.get_invite_by_code(code) do
      nil ->
        {:ok, assign(socket, page_title: "Invalid Invite", error: :not_found)}

      %Invite{expires_at: expires_at} when expires_at <= now ->
        {:ok, assign(socket, page_title: "Expired Invite", error: :expired)}

      %Invite{team_id: team_id, code: invite_code} ->
        {:ok, socket |> put_flash(:invite_code, invite_code) |> redirect(to: "/teams/#{team_id}")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-md mx-auto mt-16 text-center">
      <div class="rounded-lg border border-base-300 bg-base-100 p-8">
        <div class="mb-4">
          <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="h-12 w-12 mx-auto text-base-content/30">
            <path stroke-linecap="round" stroke-linejoin="round" d="M12 9v3.75m9-.75a9 9 0 1 1-18 0 9 9 0 0 1 18 0Zm-9 3.75h.008v.008H12v-.008Z" />
          </svg>
        </div>
        <h1 class="text-lg font-semibold mb-2">
          <%= if @error == :expired, do: "Invite Expired", else: "Invalid Invite" %>
        </h1>
        <p class="text-sm text-base-content/60 mb-6">
          This invite has expired or is invalid. Ask the team owner to generate a new invite code.
        </p>
        <a href={~p"/new"} class="inline-flex items-center rounded-md bg-primary px-4 py-2 text-sm font-medium text-white hover:bg-primary/90 transition-colors">
          Create a new team
        </a>
      </div>
    </div>
    """
  end
end
