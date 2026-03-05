defmodule TeambridgeWeb.TeamLive do
  use TeambridgeWeb, :live_view

  alias Teambridge.{Teams, Auth}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Create Team",
       team_name: "",
       members: [%{name: "", role: ""}],
       token: nil,
       step: :define
     )}
  end

  @impl true
  def handle_event("update_team_name", %{"value" => value}, socket) do
    {:noreply, assign(socket, team_name: value)}
  end

  def handle_event("update_member", %{"index" => idx, "field" => field, "value" => value}, socket) do
    index = String.to_integer(idx)
    field = String.to_existing_atom(field)

    members =
      List.update_at(socket.assigns.members, index, fn member ->
        Map.put(member, field, value)
      end)

    {:noreply, assign(socket, members: members)}
  end

  def handle_event("add_member", _params, socket) do
    members = socket.assigns.members ++ [%{name: "", role: ""}]
    {:noreply, assign(socket, members: members)}
  end

  def handle_event("remove_member", %{"index" => idx}, socket) do
    index = String.to_integer(idx)

    members =
      if length(socket.assigns.members) > 1 do
        List.delete_at(socket.assigns.members, index)
      else
        socket.assigns.members
      end

    {:noreply, assign(socket, members: members)}
  end

  # Security note (v1 design decision):
  # The LiveView generates Ed25519 keypairs server-side for web-created teams.
  # The private key is discarded — only the public key is embedded in the token.
  # This means web-created teams cannot sign API requests (the private key is lost).
  # This is intentional: the web UI is a convenience for team creation only.
  # Agents that need API access must generate their own keypairs client-side.
  # The token shown to users IS the team identifier, not an authentication credential.
  def handle_event("create_team", _params, socket) do
    {pub, _priv} = :crypto.generate_key(:eddsa, :ed25519)
    token = Auth.to_token(pub)

    team = %{
      name: socket.assigns.team_name,
      members:
        Enum.map(socket.assigns.members, fn m ->
          %{name: m.name, role: m.role}
        end)
    }

    :ok = Teams.put_team(token, team)

    {:noreply,
     assign(socket,
       step: :created,
       token: token,
       page_title: "Team Created"
     )}
  end

  def handle_event("reset", _params, socket) do
    {:noreply,
     assign(socket,
       step: :define,
       team_name: "",
       members: [%{name: "", role: ""}],
       token: nil,
       page_title: "Create Team"
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto py-12 px-4">
      <div :if={@step == :define}>
        <h1 class="text-3xl font-bold text-zinc-900 mb-2">Create a Team</h1>
        <p class="text-zinc-500 mb-8">
          Define your agent team and get a join command for each member.
        </p>

        <div class="space-y-6">
          <div>
            <label class="block text-sm font-medium text-zinc-700 mb-1" for="team-name">
              Team name
            </label>
            <input
              id="team-name"
              type="text"
              value={@team_name}
              phx-keyup="update_team_name"
              placeholder="e.g. backend-squad"
              class="w-full rounded-md border border-zinc-300 px-3 py-2 text-sm shadow-sm focus:border-zinc-500 focus:outline-none focus:ring-1 focus:ring-zinc-500"
            />
          </div>

          <div>
            <label class="block text-sm font-medium text-zinc-700 mb-3">Team members</label>
            <div class="space-y-3">
              <div
                :for={{member, idx} <- Enum.with_index(@members)}
                class="flex items-start gap-3 rounded-md border border-zinc-200 bg-zinc-50 p-3"
              >
                <div class="flex-1 space-y-2">
                  <input
                    type="text"
                    value={member.name}
                    phx-keyup="update_member"
                    phx-value-index={idx}
                    phx-value-field="name"
                    placeholder="Agent name (e.g. architect)"
                    class="w-full rounded-md border border-zinc-300 px-3 py-1.5 text-sm shadow-sm focus:border-zinc-500 focus:outline-none focus:ring-1 focus:ring-zinc-500"
                  />
                  <input
                    type="text"
                    value={member.role}
                    phx-keyup="update_member"
                    phx-value-index={idx}
                    phx-value-field="role"
                    placeholder="Role description (e.g. Focus on system design and API contracts)"
                    class="w-full rounded-md border border-zinc-300 px-3 py-1.5 text-sm shadow-sm focus:border-zinc-500 focus:outline-none focus:ring-1 focus:ring-zinc-500"
                  />
                </div>
                <button
                  :if={length(@members) > 1}
                  phx-click="remove_member"
                  phx-value-index={idx}
                  class="mt-1 rounded p-1 text-zinc-400 hover:bg-zinc-200 hover:text-zinc-600 transition-colors"
                  aria-label="Remove member"
                >
                  <svg
                    xmlns="http://www.w3.org/2000/svg"
                    class="h-5 w-5"
                    viewBox="0 0 20 20"
                    fill="currentColor"
                  >
                    <path
                      fill-rule="evenodd"
                      d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z"
                      clip-rule="evenodd"
                    />
                  </svg>
                </button>
              </div>
            </div>

            <button
              phx-click="add_member"
              class="mt-3 inline-flex items-center gap-1 text-sm font-medium text-zinc-600 hover:text-zinc-900 transition-colors"
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                class="h-4 w-4"
                viewBox="0 0 20 20"
                fill="currentColor"
              >
                <path
                  fill-rule="evenodd"
                  d="M10 3a1 1 0 011 1v5h5a1 1 0 110 2h-5v5a1 1 0 11-2 0v-5H4a1 1 0 110-2h5V4a1 1 0 011-1z"
                  clip-rule="evenodd"
                />
              </svg>
              Add member
            </button>
          </div>

          <div class="pt-4">
            <button
              phx-click="create_team"
              disabled={@team_name == ""}
              class={[
                "w-full rounded-md px-4 py-2.5 text-sm font-semibold text-white shadow-sm transition-colors",
                if(@team_name == "",
                  do: "bg-zinc-300 cursor-not-allowed",
                  else: "bg-zinc-900 hover:bg-zinc-700"
                )
              ]}
            >
              Create Team
            </button>
          </div>
        </div>
      </div>

      <div :if={@step == :created}>
        <div class="mb-6 flex items-center gap-3">
          <div class="flex h-10 w-10 items-center justify-center rounded-full bg-green-100">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              class="h-6 w-6 text-green-600"
              viewBox="0 0 20 20"
              fill="currentColor"
            >
              <path
                fill-rule="evenodd"
                d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z"
                clip-rule="evenodd"
              />
            </svg>
          </div>
          <div>
            <h1 class="text-2xl font-bold text-zinc-900">
              Team "{@team_name}" created
            </h1>
            <p class="text-sm text-zinc-500">Share the command below with each agent.</p>
          </div>
        </div>

        <div class="rounded-lg bg-zinc-900 p-4 mb-6">
          <p class="text-xs text-zinc-400 mb-2 font-medium uppercase tracking-wide">
            Join command
          </p>
          <code class="text-green-400 text-sm font-mono break-all">
            npx teambridge join {@token}
          </code>
        </div>

        <div class="rounded-lg border border-zinc-200 bg-zinc-50 p-4 mb-8">
          <p class="text-sm font-medium text-zinc-700 mb-2">
            When an agent runs this command, it will:
          </p>
          <ul class="space-y-1 text-sm text-zinc-600">
            <li class="flex items-start gap-2">
              <span class="mt-1 block h-1.5 w-1.5 rounded-full bg-zinc-400 shrink-0"></span>
              Connect to the TeamBridge relay server
            </li>
            <li class="flex items-start gap-2">
              <span class="mt-1 block h-1.5 w-1.5 rounded-full bg-zinc-400 shrink-0"></span>
              Authenticate using the embedded token
            </li>
            <li class="flex items-start gap-2">
              <span class="mt-1 block h-1.5 w-1.5 rounded-full bg-zinc-400 shrink-0"></span>
              Start syncing context with other team members
            </li>
            <li class="flex items-start gap-2">
              <span class="mt-1 block h-1.5 w-1.5 rounded-full bg-zinc-400 shrink-0"></span>
              Receive role assignments and team configuration
            </li>
          </ul>
        </div>

        <button
          phx-click="reset"
          class="text-sm font-medium text-zinc-600 hover:text-zinc-900 transition-colors underline underline-offset-2"
        >
          Create another team
        </button>
      </div>
    </div>
    """
  end
end
