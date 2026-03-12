defmodule TeamrcWeb.TeamLive do
  use TeamrcWeb, :live_view

  alias Teamrc.Teams
  alias Teamrc.Catalog

  @impl true
  def mount(_params, _session, socket) do
    template_order = Catalog.list_teams()
    templates = Map.new(template_order, fn id -> {id, Catalog.resolve_team(id)} end)

    {:ok,
     assign(socket,
       page_title: "Create Team",
       templates: templates,
       template_order: template_order
     )}
  end

  @impl true
  def handle_event("select_template", %{"template" => key}, socket) do
    template = socket.assigns.templates[key]

    if is_nil(template) do
      {:noreply, put_flash(socket, :error, "Unknown template.")}
    else
      do_create_team(template, socket)
    end
  end

  defp do_create_team(template, socket) do
    members =
      Enum.map(template.members, fn m ->
        Map.take(m, [:name, :role, :soul, :skills])
      end)

    team = build_team_payload(template.team_name, members, template.skills, template.default_platforms)

    # If the user is authenticated, set them as owner immediately
    current_user = socket.assigns[:current_scope] && socket.assigns.current_scope.user
    opts = resolve_owner_opts(current_user)

    case Teams.create_team_with_invite(team, opts) do
      {:ok, invite_code, team_id} ->
        {:noreply, socket |> put_flash(:invite_code, invite_code) |> redirect(to: "/teams/#{team_id}")}

      {:error, _reason} ->
        {:noreply, put_flash(socket, :error, "Failed to create team.")}
    end
  end

  defp build_team_payload(team_name, members, skills, default_platforms) do
    skills_clean =
      skills
      |> Enum.filter(&(&1.id != ""))
      |> Enum.map(fn s ->
        %{id: s.id}
        |> put_if(s[:title], :title)
        |> put_if(s[:description], :description)
        |> put_if(s[:alwaysApply], :alwaysApply)
        |> put_if(s[:globs], :globs)
        |> put_if(s[:userInvocable], :userInvocable)
        |> put_if(s[:body], :body)
      end)

    skill_ids = MapSet.new(skills_clean, & &1.id)

    %{
      name: team_name,
      platforms: default_platforms,
      members:
        members
        |> Enum.filter(&(&1.name != ""))
        |> Enum.map(fn m ->
          member = %{name: m.name, role: m.role}
          member = if m[:soul] && m.soul != "", do: Map.put(member, :soul, m.soul), else: member
          member_skills = (m[:skills] || []) |> Enum.filter(&MapSet.member?(skill_ids, &1))
          if member_skills != [], do: Map.put(member, :skills, member_skills), else: member
        end),
      skills: skills_clean
    }
  end

  defp resolve_owner_opts(nil), do: []

  defp resolve_owner_opts(current_user) do
    [owner_user_id: current_user.id]
  end

  defp put_if(map, nil, _key), do: map
  defp put_if(map, false, _key), do: map
  defp put_if(map, "", _key), do: map
  defp put_if(map, value, key), do: Map.put(map, key, value)

  @known_icons ~w(code server shield megaphone wrench book cloud)

  defp validated_icon(icon) when icon in @known_icons, do: icon
  defp validated_icon(_), do: "code"

  defp template_icon("code"),
    do: ~s(<path stroke-linecap="round" stroke-linejoin="round" d="M17.25 6.75 22.5 12l-5.25 5.25m-10.5 0L1.5 12l5.25-5.25m7.5-3-4.5 16.5" />)

  defp template_icon("server"),
    do: ~s(<path stroke-linecap="round" stroke-linejoin="round" d="M5.25 14.25h13.5m-13.5 0a3 3 0 0 1-3-3m3 3a3 3 0 1 0 0 6h13.5a3 3 0 1 0 0-6m-16.5-3a3 3 0 0 1 3-3h13.5a3 3 0 0 1 3 3m-19.5 0a4.5 4.5 0 0 1 .9-2.7L5.737 5.1a3.375 3.375 0 0 1 2.7-1.35h7.126c1.062 0 2.062.5 2.7 1.35l2.587 3.45a4.5 4.5 0 0 1 .9 2.7m0 0a3 3 0 0 1-3 3m0 3h.008v.008h-.008v-.008Zm0-6h.008v.008h-.008v-.008Zm-3 6h.008v.008h-.008v-.008Zm0-6h.008v.008h-.008v-.008Z" />)

  defp template_icon("shield"),
    do: ~s(<path stroke-linecap="round" stroke-linejoin="round" d="M9 12.75 11.25 15 15 9.75m-3-7.036A11.959 11.959 0 0 1 3.598 6 11.99 11.99 0 0 0 3 9.749c0 5.592 3.824 10.29 9 11.623 5.176-1.332 9-6.03 9-11.622 0-1.31-.21-2.571-.598-3.751h-.152c-3.196 0-6.1-1.248-8.25-3.285Z" />)

  defp template_icon("megaphone"),
    do: ~s(<path stroke-linecap="round" stroke-linejoin="round" d="M10.34 15.84c-.688-.06-1.386-.09-2.09-.09H7.5a4.5 4.5 0 1 1 0-9h.75c.704 0 1.402-.03 2.09-.09m0 9.18c.253.962.584 1.892.985 2.783.247.55.06 1.21-.463 1.511l-.657.38a.954.954 0 0 1-1.305-.427 19.867 19.867 0 0 1-1.14-2.66m2.58-1.587-.58.344a15.003 15.003 0 0 1-2 .854m2.58-1.198c2.094-.656 4.108-1.594 6.01-2.79a.75.75 0 0 0 0-1.284 24.138 24.138 0 0 0-6.01-2.79m0 6.864V6.916" />)

  defp template_icon("wrench"),
    do: ~s(<path stroke-linecap="round" stroke-linejoin="round" d="M11.42 15.17 17.25 21A2.652 2.652 0 0 0 21 17.25l-5.877-5.877M11.42 15.17l2.496-3.03c.317-.384.74-.626 1.208-.766M11.42 15.17l-4.655 5.653a2.548 2.548 0 1 1-3.586-3.586l6.837-5.63m5.108-.233c.55-.164 1.163-.188 1.743-.14a4.5 4.5 0 0 0 4.486-6.336l-3.276 3.277a3.004 3.004 0 0 1-2.25-2.25l3.276-3.276a4.5 4.5 0 0 0-6.336 4.486c.049.58.025 1.193-.14 1.743Z" />)

  defp template_icon("book"),
    do: ~s(<path stroke-linecap="round" stroke-linejoin="round" d="M12 6.042A8.967 8.967 0 0 0 6 3.75c-1.052 0-2.062.18-3 .512v14.25A8.987 8.987 0 0 1 6 18c2.305 0 4.408.867 6 2.292m0-14.25a8.966 8.966 0 0 1 6-2.292c1.052 0 2.062.18 3 .512v14.25A8.987 8.987 0 0 0 18 18a8.967 8.967 0 0 0-6 2.292m0-14.25v14.25" />)

  defp template_icon("cloud"),
    do: ~s(<path stroke-linecap="round" stroke-linejoin="round" d="M2.25 15a4.5 4.5 0 0 0 4.5 4.5H18a3.75 3.75 0 0 0 1.332-7.257 3 3 0 0 0-3.758-3.848 5.25 5.25 0 0 0-10.233 2.33A4.502 4.502 0 0 0 2.25 15Z" />)

  defp template_icon(_), do: template_icon("code")

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto">
      <div class="mb-8">
        <p class="text-sm font-medium text-primary/80 mb-2">One team. Every platform. Always in sync.</p>
        <h1 class="text-2xl font-bold tracking-tight mb-1">Create a team</h1>
        <p class="text-sm text-base-content/60">
          Pick a template to get started instantly.
          <a href={~p"/guide"} class="text-primary/80 hover:text-primary transition-colors">Learn how teamrc works &rarr;</a>
        </p>
      </div>

      <div class="grid gap-2">
        <button
          :for={key <- @template_order}
          phx-click="select_template"
          phx-value-template={key}
          class="trc-card trc-focus group flex items-start gap-4 rounded-lg border border-base-300 bg-base-100 p-4 text-left hover:border-primary/30 hover:shadow-sm"
        >
          <div class="flex h-9 w-9 shrink-0 items-center justify-center rounded-md bg-base-200 text-base-content/60 group-hover:bg-primary/10 group-hover:text-primary transition-colors">
            <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="h-[18px] w-[18px]">
              <%= raw(template_icon(validated_icon(@templates[key].icon))) %>
            </svg>
          </div>
          <div class="min-w-0 flex-1">
            <div class="flex items-center gap-2">
              <span class="font-semibold text-sm"><%= @templates[key].label %></span>
              <span :if={key != "custom"} class="text-xs text-base-content/60 font-mono">
                <%= length(@templates[key].members) %> agents
              </span>
            </div>
            <div class="text-sm text-base-content/70 mt-0.5"><%= @templates[key].description %></div>
            <div :if={key != "custom"} class="mt-2.5 flex flex-wrap gap-1.5">
              <span
                :for={member <- @templates[key].members}
                class="inline-flex items-center rounded bg-base-200 px-2 py-0.5 text-xs font-mono text-base-content/70"
              >
                <%= member.name %>
              </span>
            </div>
          </div>
          <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4 text-base-content/50 group-hover:text-primary/80 mt-1 shrink-0 transition-colors" viewBox="0 0 20 20" fill="currentColor">
            <path fill-rule="evenodd" d="M7.21 14.77a.75.75 0 01.02-1.06L11.168 10 7.23 6.29a.75.75 0 111.04-1.08l4.5 4.25a.75.75 0 010 1.08l-4.5 4.25a.75.75 0 01-1.06-.02z" clip-rule="evenodd" />
          </svg>
        </button>
      </div>
    </div>
    """
  end
end
