defmodule TeamrcWeb.TeamLive do
  use TeamrcWeb, :live_view

  alias Phoenix.LiveView.JS
  alias Teamrc.Teams
  alias Teamrc.Catalog

  @all_platforms [
    %{id: "claude-code", label: "Claude Code"},
    %{id: "cursor", label: "Cursor"},
    %{id: "codex", label: "Codex"},
    %{id: "copilot", label: "Copilot"},
    %{id: "gemini", label: "Gemini"},
    %{id: "openclaw", label: "OpenClaw"},
    %{id: "windsurf", label: "Windsurf"},
    %{id: "cline", label: "Cline"},
    %{id: "amazon-q", label: "Amazon Q"}
  ]

  @impl true
  def mount(_params, _session, socket) do
    template_order = Catalog.list_teams()
    templates = Map.new(template_order, fn id -> {id, Catalog.resolve_team(id)} end)
    agent_categories = Catalog.list_agent_categories()
    skill_categories = Catalog.list_skill_categories()

    agent_roles =
      agent_categories
      |> Enum.flat_map(& &1["agents"])
      |> Map.new(fn name -> {name, Catalog.load_agent(name)["role"]} end)

    skill_meta =
      skill_categories
      |> Enum.flat_map(& &1["skills"])
      |> Map.new(fn id ->
        s = Catalog.load_skill(id)
        {id, %{title: s["title"], description: s["description"], always_apply: s["alwaysApply"] || false}}
      end)

    {:ok,
     assign(socket,
       page_title: "Create Team",
       step: :choose_template,
       templates: templates,
       template_order: template_order,
       all_platforms: @all_platforms,
       agent_categories: agent_categories,
       skill_categories: skill_categories,
       agent_roles: agent_roles,
       skill_meta: skill_meta,
       team_name: "",
       members: [],
       skills: [],
       selected_platforms: MapSet.new(),
       invite_code: nil,
       show_agent_picker: false,
       show_skill_picker: false,
       agent_search: ""
     )}
  end

  # --- Navigation ---

  @impl true
  def handle_event("select_template", %{"template" => key}, socket) do
    template = socket.assigns.templates[key]

    members =
      Enum.map(template.members, fn m ->
        m |> Map.take([:name, :role, :soul, :skills]) |> Map.put(:from_catalog, true)
      end)

    {:noreply,
     assign(socket,
       step: :define,
       team_name: template.team_name,
       members: members,
       skills: template.skills,
       selected_platforms: MapSet.new(template.default_platforms),
       show_agent_picker: false,
       show_skill_picker: false,
       agent_search: ""
     )}
  end

  def handle_event("back_to_templates", _params, socket) do
    {:noreply, assign(socket, step: :choose_template, show_agent_picker: false, show_skill_picker: false)}
  end

  def handle_event("reset", _params, socket) do
    {:noreply,
     assign(socket,
       step: :choose_template,
       page_title: "Create Team",
       team_name: "",
       members: [],
       skills: [],
       selected_platforms: MapSet.new(),
       invite_code: nil,
       show_agent_picker: false,
       show_skill_picker: false,
       agent_search: ""
     )}
  end

  # --- Form fields ---

  def handle_event("update_team_name", %{"value" => value}, socket) do
    {:noreply, assign(socket, team_name: value)}
  end

  def handle_event("toggle_platform", %{"platform" => platform_id}, socket) do
    platforms = socket.assigns.selected_platforms

    platforms =
      if MapSet.member?(platforms, platform_id),
        do: MapSet.delete(platforms, platform_id),
        else: MapSet.put(platforms, platform_id)

    {:noreply, assign(socket, selected_platforms: platforms)}
  end

  # --- Members ---

  def handle_event("add_catalog_agent", %{"name" => name}, socket) do
    if agent_added?(socket.assigns.members, name) do
      {:noreply, socket}
    else
      agent = Catalog.load_agent(name)
      member = %{name: agent["name"], role: agent["role"], soul: agent["soul"] || "", from_catalog: true}
      {:noreply, assign(socket, members: socket.assigns.members ++ [member])}
    end
  end

  def handle_event("add_custom_member", _params, socket) do
    member = %{name: "", role: "", soul: "", from_catalog: false}
    {:noreply, assign(socket, members: socket.assigns.members ++ [member], show_agent_picker: false)}
  end

  def handle_event("update_member", %{"index" => idx, "field" => field, "value" => value}, socket) do
    field_atom =
      case field do
        "name" -> :name
        "role" -> :role
        "soul" -> :soul
        _ -> nil
      end

    if field_atom do
      index = String.to_integer(idx)
      members = List.update_at(socket.assigns.members, index, &Map.put(&1, field_atom, value))
      {:noreply, assign(socket, members: members)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("remove_member", %{"index" => idx}, socket) do
    index = String.to_integer(idx)
    {:noreply, assign(socket, members: List.delete_at(socket.assigns.members, index))}
  end

  def handle_event("toggle_agent_picker", _params, socket) do
    {:noreply, assign(socket, show_agent_picker: !socket.assigns.show_agent_picker, agent_search: "")}
  end

  def handle_event("update_agent_search", %{"value" => value}, socket) do
    {:noreply, assign(socket, agent_search: value)}
  end

  # --- Skills ---

  def handle_event("toggle_catalog_skill", %{"id" => id}, socket) do
    skills = socket.assigns.skills

    if skill_selected?(skills, id) do
      # Remove skill from project and from all member assignments
      new_skills = Enum.reject(skills, &(&1.id == id))

      new_members =
        Enum.map(socket.assigns.members, fn m ->
          case m[:skills] do
            nil -> m
            s -> Map.put(m, :skills, List.delete(s, id))
          end
        end)

      {:noreply, assign(socket, skills: new_skills, members: new_members)}
    else
      raw = Catalog.load_skill(id)

      skill =
        %{id: raw["id"]}
        |> put_if(raw["title"], :title)
        |> put_if(raw["description"], :description)
        |> put_if(raw["alwaysApply"], :alwaysApply)
        |> put_if(raw["globs"], :globs)
        |> put_if(raw["userInvocable"], :userInvocable)
        |> put_if(raw["body"], :body)

      {:noreply, assign(socket, skills: skills ++ [skill])}
    end
  end

  def handle_event("toggle_skill_picker", _params, socket) do
    {:noreply, assign(socket, show_skill_picker: !socket.assigns.show_skill_picker)}
  end

  def handle_event("toggle_member_skill", %{"member-index" => member_idx, "skill-id" => skill_id}, socket) do
    index = String.to_integer(member_idx)

    members =
      List.update_at(socket.assigns.members, index, fn member ->
        current = member[:skills] || []

        if skill_id in current,
          do: Map.put(member, :skills, List.delete(current, skill_id)),
          else: Map.put(member, :skills, current ++ [skill_id])
      end)

    {:noreply, assign(socket, members: members)}
  end

  # --- Create ---

  def handle_event("create_team", _params, socket) do
    skills =
      socket.assigns.skills
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

    skill_ids = MapSet.new(skills, & &1.id)

    team = %{
      name: socket.assigns.team_name,
      platforms: MapSet.to_list(socket.assigns.selected_platforms),
      members:
        socket.assigns.members
        |> Enum.filter(&(&1.name != ""))
        |> Enum.map(fn m ->
          member = %{name: m.name, role: m.role}
          member = if m[:soul] && m.soul != "", do: Map.put(member, :soul, m.soul), else: member
          member_skills = (m[:skills] || []) |> Enum.filter(&MapSet.member?(skill_ids, &1))
          if member_skills != [], do: Map.put(member, :skills, member_skills), else: member
        end),
      skills: skills
    }

    {:ok, invite_code} = Teams.create_team_with_invite(team)

    {:noreply,
     assign(socket,
       step: :created,
       invite_code: invite_code,
       page_title: "Team Created"
     )}
  end

  # --- Helpers ---

  defp put_if(map, nil, _key), do: map
  defp put_if(map, false, _key), do: map
  defp put_if(map, "", _key), do: map
  defp put_if(map, value, key), do: Map.put(map, key, value)

  defp agent_added?(members, name), do: Enum.any?(members, &(&1.name == name))
  defp skill_selected?(skills, id), do: Enum.any?(skills, &(&1.id == id))

  defp soul_excerpt(nil), do: nil
  defp soul_excerpt(""), do: nil

  defp soul_excerpt(soul) do
    soul
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))
    |> Enum.take(2)
    |> Enum.join(" ")
    |> then(fn text ->
      if String.length(text) > 140, do: String.slice(text, 0, 137) <> "...", else: text
    end)
  end

  defp filtered_agent_categories(categories, search, agent_roles) do
    search = String.downcase(String.trim(search))

    if search == "" do
      categories
    else
      categories
      |> Enum.map(fn cat ->
        agents =
          Enum.filter(cat["agents"], fn name ->
            String.contains?(String.downcase(name), search) or
              String.contains?(String.downcase(agent_roles[name] || ""), search)
          end)

        Map.put(cat, "agents", agents)
      end)
      |> Enum.reject(&(&1["agents"] == []))
    end
  end

  defp selected_platform_labels(selected_platforms, all_platforms) do
    all_platforms
    |> Enum.filter(&MapSet.member?(selected_platforms, &1.id))
    |> Enum.map(& &1.label)
  end

  defp step_number(:choose_template), do: 1
  defp step_number(:define), do: 2
  defp step_number(:created), do: 3

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

  # --- SVG path fragments ---

  defp svg(:check),
    do: ~s(<path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd" />)

  defp svg(:plus),
    do: ~s(<path fill-rule="evenodd" d="M10 3a1 1 0 011 1v5h5a1 1 0 110 2h-5v5a1 1 0 11-2 0v-5H4a1 1 0 110-2h5V4a1 1 0 011-1z" clip-rule="evenodd" />)

  defp svg(:x),
    do: ~s(<path fill-rule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clip-rule="evenodd" />)

  defp svg(:back),
    do: ~s(<path fill-rule="evenodd" d="M9.707 16.707a1 1 0 01-1.414 0l-6-6a1 1 0 010-1.414l6-6a1 1 0 011.414 1.414L5.414 9H17a1 1 0 110 2H5.414l4.293 4.293a1 1 0 010 1.414z" clip-rule="evenodd" />)

  defp svg(:chevron),
    do: ~s(<path fill-rule="evenodd" d="M7.21 14.77a.75.75 0 01.02-1.06L11.168 10 7.23 6.29a.75.75 0 111.04-1.08l4.5 4.25a.75.75 0 010 1.08l-4.5 4.25a.75.75 0 01-1.06-.02z" clip-rule="evenodd" />)

  # --- Render ---

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto">
      <%!-- Step indicator --%>
      <div class="flex items-center gap-2 mb-10 text-xs font-medium">
        <.step_indicator number={1} label="Template" active={step_number(@step) >= 1} current={@step == :choose_template} />
        <div class={"w-8 h-px " <> if(step_number(@step) >= 2, do: "bg-primary/40", else: "bg-base-300")} />
        <.step_indicator number={2} label="Configure" active={step_number(@step) >= 2} current={@step == :define} />
        <div class={"w-8 h-px " <> if(step_number(@step) >= 3, do: "bg-primary/40", else: "bg-base-300")} />
        <.step_indicator number={3} label="Connect" active={step_number(@step) >= 3} current={@step == :created} />
      </div>

      <%!-- ================================================================ --%>
      <%!-- Step 1: Choose template                                         --%>
      <%!-- ================================================================ --%>
      <div :if={@step == :choose_template}>
        <div class="mb-8">
          <h1 class="text-2xl font-bold tracking-tight mb-1">Create a team</h1>
          <p class="text-sm text-base-content/50">
            Pick a starting point. You can customize everything next.
          </p>
        </div>

        <div class="grid gap-2">
          <button
            :for={key <- @template_order}
            phx-click="select_template"
            phx-value-template={key}
            class="trc-card trc-focus group flex items-start gap-4 rounded-lg border border-base-300 bg-base-100 p-4 text-left hover:border-primary/30 hover:shadow-sm"
          >
            <div class="flex h-9 w-9 shrink-0 items-center justify-center rounded-md bg-base-200 text-base-content/50 group-hover:bg-primary/10 group-hover:text-primary transition-colors">
              <svg xmlns="http://www.w3.org/2000/svg" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor" class="h-[18px] w-[18px]">
                <%= raw(template_icon(@templates[key].icon)) %>
              </svg>
            </div>
            <div class="min-w-0 flex-1">
              <div class="flex items-center gap-2">
                <span class="font-semibold text-sm"><%= @templates[key].label %></span>
                <span :if={key != "custom"} class="text-xs text-base-content/30 font-mono">
                  <%= length(@templates[key].members) %> agents
                </span>
              </div>
              <div class="text-sm text-base-content/50 mt-0.5"><%= @templates[key].description %></div>
              <div :if={key != "custom"} class="mt-2.5 flex flex-wrap gap-1.5">
                <span
                  :for={member <- @templates[key].members}
                  class="inline-flex items-center rounded bg-base-200 px-2 py-0.5 text-xs font-mono text-base-content/60"
                >
                  <%= member.name %>
                </span>
              </div>
            </div>
            <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4 text-base-content/20 group-hover:text-primary/50 mt-1 shrink-0 transition-colors" viewBox="0 0 20 20" fill="currentColor">
              <%= raw(svg(:chevron)) %>
            </svg>
          </button>
        </div>
      </div>

      <%!-- ================================================================ --%>
      <%!-- Step 2: Configure team                                          --%>
      <%!-- ================================================================ --%>
      <div :if={@step == :define}>
        <button
          phx-click="back_to_templates"
          class="trc-focus mb-6 inline-flex items-center gap-1.5 text-xs font-medium text-base-content/40 hover:text-base-content/70 transition-colors rounded px-1 -ml-1"
        >
          <svg xmlns="http://www.w3.org/2000/svg" class="h-3.5 w-3.5" viewBox="0 0 20 20" fill="currentColor">
            <%= raw(svg(:back)) %>
          </svg>
          Templates
        </button>

        <div class="mb-8">
          <h1 class="text-2xl font-bold tracking-tight mb-1">Configure your team</h1>
          <p class="text-sm text-base-content/50">
            Review your agents and skills, then create.
          </p>
        </div>

        <div class="space-y-8">
          <%!-- Team name --%>
          <div>
            <label class="block text-xs font-medium text-base-content/60 uppercase tracking-wider mb-2" for="team-name">
              Team name
            </label>
            <input
              id="team-name"
              type="text"
              value={@team_name}
              phx-keyup="update_team_name"
              phx-mounted={JS.focus()}
              placeholder="e.g. backend-squad"
              class="trc-focus w-full rounded-md border border-base-300 bg-base-100 px-3 py-2 text-sm font-mono placeholder:text-base-content/25 focus:border-primary/50 focus:ring-1 focus:ring-primary/20 transition-colors"
            />
          </div>

          <%!-- Platform picker --%>
          <div>
            <label class="block text-xs font-medium text-base-content/60 uppercase tracking-wider mb-3">
              Platforms
              <span :if={MapSet.size(@selected_platforms) > 0} class="font-mono text-base-content/30 normal-case ml-1">
                (<%= MapSet.size(@selected_platforms) %> selected)
              </span>
            </label>
            <div class="grid grid-cols-3 gap-2">
              <button
                :for={platform <- @all_platforms}
                phx-click="toggle_platform"
                phx-value-platform={platform.id}
                class={[
                  "trc-focus flex items-center gap-2 rounded-md border px-3 py-2 text-sm transition-colors",
                  if(MapSet.member?(@selected_platforms, platform.id),
                    do: "border-primary/40 bg-primary/5 text-base-content",
                    else: "border-base-300 bg-base-100 text-base-content/50 hover:border-base-300/80"
                  )
                ]}
              >
                <div class={[
                  "flex h-4 w-4 shrink-0 items-center justify-center rounded border transition-colors",
                  if(MapSet.member?(@selected_platforms, platform.id),
                    do: "border-primary bg-primary",
                    else: "border-base-300"
                  )
                ]}>
                  <svg
                    :if={MapSet.member?(@selected_platforms, platform.id)}
                    xmlns="http://www.w3.org/2000/svg"
                    class="h-3 w-3 text-primary-content"
                    viewBox="0 0 20 20"
                    fill="currentColor"
                  >
                    <%= raw(svg(:check)) %>
                  </svg>
                </div>
                <span class="font-mono text-xs"><%= platform.label %></span>
              </button>
            </div>
            <p class="text-xs text-base-content/30 mt-2">
              The CLI will auto-detect platforms. These are stored as defaults.
            </p>
          </div>

          <%!-- ========== Members ========== --%>
          <div>
            <label class="block text-xs font-medium text-base-content/60 uppercase tracking-wider mb-3">
              Agents
              <span :if={@members != []} class="font-mono text-base-content/30 normal-case ml-1">
                (<%= length(@members) %>)
              </span>
            </label>

            <%!-- Empty state --%>
            <p :if={@members == []} class="text-sm text-base-content/30 mb-3">
              Add agents from the catalog to build your team.
            </p>

            <%!-- Agent cards --%>
            <div class="space-y-2">
              <%!-- Catalog agent card (read-only) --%>
              <div
                :for={{member, idx} <- Enum.with_index(@members)}
                :if={member[:from_catalog]}
                class="group rounded-lg border border-base-300 bg-base-100 p-3"
              >
                <div class="flex items-start gap-3">
                  <div class="min-w-0 flex-1">
                    <div class="flex items-baseline gap-2">
                      <span class="font-mono font-semibold text-sm"><%= member.name %></span>
                      <span class="text-xs text-base-content/40"><%= member.role %></span>
                    </div>
                    <p :if={soul_excerpt(member[:soul])} class="text-xs text-base-content/35 mt-1 leading-relaxed">
                      <%= soul_excerpt(member.soul) %>
                    </p>
                  </div>
                  <button
                    phx-click="remove_member"
                    phx-value-index={idx}
                    class="trc-focus rounded p-1 text-base-content/15 hover:bg-error/10 hover:text-error transition-colors sm:opacity-0 sm:group-hover:opacity-100"
                    aria-label="Remove member"
                  >
                    <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" viewBox="0 0 20 20" fill="currentColor"><%= raw(svg(:x)) %></svg>
                  </button>
                </div>
                <%!-- Per-agent skill chips --%>
                <div :if={@skills != []} class="mt-2.5 flex flex-wrap items-center gap-1">
                  <span class="text-[10px] uppercase tracking-wider text-base-content/25 font-medium mr-0.5">Skills</span>
                  <button
                    :for={skill <- @skills}
                    phx-click="toggle_member_skill"
                    phx-value-member-index={idx}
                    phx-value-skill-id={skill.id}
                    class={[
                      "trc-focus inline-flex items-center rounded px-1.5 py-0.5 text-[11px] font-mono transition-colors",
                      if(skill.id in (member[:skills] || []),
                        do: "bg-primary/15 text-primary border border-primary/30",
                        else: "bg-base-200/50 text-base-content/25 border border-transparent hover:border-base-300 hover:text-base-content/40"
                      )
                    ]}
                  >
                    <%= skill.id %>
                  </button>
                </div>
              </div>

              <%!-- Custom agent card (editable) --%>
              <div
                :for={{member, idx} <- Enum.with_index(@members)}
                :if={!member[:from_catalog]}
                class="group rounded-lg border border-base-300 bg-base-200/30 p-3"
              >
                <div class="flex items-start gap-3">
                  <div class="min-w-0 flex-1 space-y-2">
                    <input
                      type="text"
                      value={member.name}
                      phx-keyup="update_member"
                      phx-value-index={idx}
                      phx-value-field="name"
                      placeholder="agent-name"
                      class="trc-focus w-full rounded border border-base-300 bg-base-100 px-2.5 py-1.5 text-sm font-mono placeholder:text-base-content/25 focus:border-primary/50 focus:ring-1 focus:ring-primary/20 transition-colors"
                    />
                    <input
                      type="text"
                      value={member.role}
                      phx-keyup="update_member"
                      phx-value-index={idx}
                      phx-value-field="role"
                      placeholder="Role description"
                      class="trc-focus w-full rounded border border-base-300 bg-base-100 px-2.5 py-1.5 text-sm placeholder:text-base-content/25 focus:border-primary/50 focus:ring-1 focus:ring-primary/20 transition-colors"
                    />
                    <textarea
                      phx-keyup="update_member"
                      phx-value-index={idx}
                      phx-value-field="soul"
                      placeholder="System prompt (optional)"
                      rows="3"
                      class="trc-focus w-full rounded border border-base-300 bg-base-100 px-2.5 py-1.5 text-sm placeholder:text-base-content/25 focus:border-primary/50 focus:ring-1 focus:ring-primary/20 transition-colors resize-none"
                    ><%= member[:soul] || "" %></textarea>
                  </div>
                  <button
                    phx-click="remove_member"
                    phx-value-index={idx}
                    class="trc-focus rounded p-1 text-base-content/15 hover:bg-error/10 hover:text-error transition-colors sm:opacity-0 sm:group-hover:opacity-100"
                    aria-label="Remove member"
                  >
                    <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" viewBox="0 0 20 20" fill="currentColor"><%= raw(svg(:x)) %></svg>
                  </button>
                </div>
                <%!-- Per-agent skill chips for custom agents --%>
                <div :if={@skills != []} class="mt-2.5 flex flex-wrap items-center gap-1">
                  <span class="text-[10px] uppercase tracking-wider text-base-content/25 font-medium mr-0.5">Skills</span>
                  <button
                    :for={skill <- @skills}
                    phx-click="toggle_member_skill"
                    phx-value-member-index={idx}
                    phx-value-skill-id={skill.id}
                    class={[
                      "trc-focus inline-flex items-center rounded px-1.5 py-0.5 text-[11px] font-mono transition-colors",
                      if(skill.id in (member[:skills] || []),
                        do: "bg-primary/15 text-primary border border-primary/30",
                        else: "bg-base-200/50 text-base-content/25 border border-transparent hover:border-base-300 hover:text-base-content/40"
                      )
                    ]}
                  >
                    <%= skill.id %>
                  </button>
                </div>
              </div>
            </div>

            <%!-- Add agent button --%>
            <button
              phx-click="toggle_agent_picker"
              class="trc-focus mt-3 inline-flex items-center gap-1.5 rounded px-2 py-1 text-xs font-medium text-base-content/40 hover:text-primary hover:bg-primary/5 transition-colors"
            >
              <svg xmlns="http://www.w3.org/2000/svg" class="h-3.5 w-3.5" viewBox="0 0 20 20" fill="currentColor"><%= raw(svg(:plus)) %></svg>
              <%= if @show_agent_picker, do: "Close", else: "Add agent" %>
            </button>

            <%!-- Agent catalog picker --%>
            <div :if={@show_agent_picker} class="mt-3 rounded-lg border border-primary/20 bg-base-100 overflow-hidden animate-[fadeIn_150ms_ease-out]">
              <div class="p-3 border-b border-base-300/50">
                <input
                  type="text"
                  value={@agent_search}
                  phx-keyup="update_agent_search"
                  phx-mounted={JS.focus()}
                  placeholder="Search agents..."
                  class="trc-focus w-full rounded border border-base-300 bg-base-100 px-2.5 py-1.5 text-sm placeholder:text-base-content/25 focus:border-primary/50 focus:ring-1 focus:ring-primary/20 transition-colors"
                />
              </div>
              <div class="max-h-72 overflow-y-auto p-2 space-y-3">
                <div :for={cat <- filtered_agent_categories(@agent_categories, @agent_search, @agent_roles)}>
                  <div class="px-2 py-1 text-[10px] uppercase tracking-wider text-base-content/30 font-medium">
                    <%= cat["label"] %>
                  </div>
                  <div class="space-y-px">
                    <button
                      :for={name <- cat["agents"]}
                      phx-click={unless(agent_added?(@members, name), do: "add_catalog_agent")}
                      phx-value-name={name}
                      disabled={agent_added?(@members, name)}
                      class={[
                        "trc-focus w-full flex items-center gap-2 rounded px-2 py-1.5 text-left transition-colors",
                        if(agent_added?(@members, name),
                          do: "text-base-content/25 cursor-default",
                          else: "hover:bg-primary/5 text-base-content/70"
                        )
                      ]}
                    >
                      <svg
                        :if={agent_added?(@members, name)}
                        xmlns="http://www.w3.org/2000/svg"
                        class="h-3.5 w-3.5 text-primary/50 shrink-0"
                        viewBox="0 0 20 20"
                        fill="currentColor"
                      ><%= raw(svg(:check)) %></svg>
                      <svg
                        :if={!agent_added?(@members, name)}
                        xmlns="http://www.w3.org/2000/svg"
                        class="h-3.5 w-3.5 text-base-content/20 shrink-0"
                        viewBox="0 0 20 20"
                        fill="currentColor"
                      ><%= raw(svg(:plus)) %></svg>
                      <span class="font-mono text-xs"><%= name %></span>
                      <span class="text-xs text-base-content/30 truncate"><%= @agent_roles[name] %></span>
                    </button>
                  </div>
                </div>

                <%!-- Custom agent option --%>
                <div class="border-t border-base-300/50 pt-2">
                  <button
                    phx-click="add_custom_member"
                    class="trc-focus w-full flex items-center gap-2 rounded px-2 py-1.5 text-left text-base-content/50 hover:bg-primary/5 hover:text-base-content/70 transition-colors"
                  >
                    <svg xmlns="http://www.w3.org/2000/svg" class="h-3.5 w-3.5 shrink-0" viewBox="0 0 20 20" fill="currentColor"><%= raw(svg(:plus)) %></svg>
                    <span class="text-xs">Custom agent</span>
                    <span class="text-xs text-base-content/25">name + role + prompt</span>
                  </button>
                </div>
              </div>
            </div>
          </div>

          <%!-- ========== Skills ========== --%>
          <div>
            <label class="block text-xs font-medium text-base-content/60 uppercase tracking-wider mb-3">
              Skills
              <span :if={@skills != []} class="font-mono text-base-content/30 normal-case ml-1">
                (<%= length(@skills) %>)
              </span>
            </label>

            <%!-- Current skills as removable chips --%>
            <div :if={@skills != []} class="flex flex-wrap gap-1.5 mb-3">
              <span
                :for={skill <- @skills}
                class="inline-flex items-center gap-1.5 rounded-md bg-base-200 px-2 py-1 text-xs font-mono text-base-content/60"
              >
                <%= skill.id %>
                <span :if={skill[:alwaysApply]} class="text-[9px] text-warning font-medium">always</span>
                <button
                  phx-click="toggle_catalog_skill"
                  phx-value-id={skill.id}
                  class="text-base-content/25 hover:text-error transition-colors"
                  aria-label={"Remove #{skill.id}"}
                >
                  <svg xmlns="http://www.w3.org/2000/svg" class="h-3 w-3" viewBox="0 0 20 20" fill="currentColor"><%= raw(svg(:x)) %></svg>
                </button>
              </span>
            </div>

            <p :if={@skills == []} class="text-sm text-base-content/30 mb-3">
              No skills yet. Add rules and capabilities from the catalog.
            </p>

            <%!-- Add skill button --%>
            <button
              phx-click="toggle_skill_picker"
              class="trc-focus inline-flex items-center gap-1.5 rounded px-2 py-1 text-xs font-medium text-base-content/40 hover:text-primary hover:bg-primary/5 transition-colors"
            >
              <svg xmlns="http://www.w3.org/2000/svg" class="h-3.5 w-3.5" viewBox="0 0 20 20" fill="currentColor"><%= raw(svg(:plus)) %></svg>
              <%= if @show_skill_picker, do: "Close", else: "Add skill" %>
            </button>

            <%!-- Skill catalog picker --%>
            <div :if={@show_skill_picker} class="mt-3 rounded-lg border border-primary/20 bg-base-100 overflow-hidden animate-[fadeIn_150ms_ease-out]">
              <div class="max-h-80 overflow-y-auto p-2 space-y-3">
                <div :for={cat <- @skill_categories}>
                  <div class="px-2 py-1 text-[10px] uppercase tracking-wider text-base-content/30 font-medium">
                    <%= cat["label"] %>
                  </div>
                  <div class="space-y-px">
                    <button
                      :for={id <- cat["skills"]}
                      phx-click="toggle_catalog_skill"
                      phx-value-id={id}
                      class={[
                        "trc-focus w-full flex items-center gap-2 rounded px-2 py-1.5 text-left transition-colors",
                        if(skill_selected?(@skills, id),
                          do: "bg-primary/5 text-base-content",
                          else: "text-base-content/60 hover:bg-base-200/50"
                        )
                      ]}
                    >
                      <div class={[
                        "flex h-4 w-4 shrink-0 items-center justify-center rounded border transition-colors",
                        if(skill_selected?(@skills, id),
                          do: "border-primary bg-primary",
                          else: "border-base-300"
                        )
                      ]}>
                        <svg
                          :if={skill_selected?(@skills, id)}
                          xmlns="http://www.w3.org/2000/svg"
                          class="h-3 w-3 text-primary-content"
                          viewBox="0 0 20 20"
                          fill="currentColor"
                        ><%= raw(svg(:check)) %></svg>
                      </div>
                      <span class="font-mono text-xs"><%= id %></span>
                      <span :if={@skill_meta[id]} class="text-xs text-base-content/30 truncate"><%= @skill_meta[id].description %></span>
                      <span :if={@skill_meta[id] && @skill_meta[id].always_apply} class="ml-auto shrink-0 text-[10px] text-warning font-medium">always</span>
                    </button>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <%!-- Create button --%>
          <div class="pt-2 pb-12">
            <button
              phx-click="create_team"
              phx-disable-with="Creating..."
              disabled={@team_name == ""}
              class={[
                "trc-focus w-full rounded-md px-4 py-2.5 text-sm font-semibold shadow-sm transition-all duration-150",
                if(@team_name == "",
                  do: "bg-base-300 text-base-content/30 cursor-not-allowed",
                  else: "bg-primary text-primary-content hover:brightness-110 active:scale-[0.99]"
                )
              ]}
            >
              Create team
            </button>
          </div>
        </div>
      </div>

      <%!-- ================================================================ --%>
      <%!-- Step 3: Team created                                            --%>
      <%!-- ================================================================ --%>
      <div :if={@step == :created}>
        <div class="mb-8">
          <div class="flex items-center gap-3 mb-4">
            <div class="flex h-8 w-8 items-center justify-center rounded-full bg-success/15">
              <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4 text-success" viewBox="0 0 20 20" fill="currentColor">
                <%= raw(svg(:check)) %>
              </svg>
            </div>
            <div>
              <h1 class="text-xl font-bold tracking-tight">
                <span class="font-mono text-primary"><%= @team_name %></span> created
              </h1>
            </div>
          </div>
          <p class="text-sm text-base-content/50">
            Run this command on each machine to connect and sync.
          </p>
        </div>

        <%!-- Account linking prompt for non-signed-in users --%>
        <div :if={!@clerk_email} class="rounded-lg border border-info/30 bg-info/5 p-4 mb-6">
          <div class="flex items-start gap-3">
            <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5 text-info shrink-0 mt-0.5" viewBox="0 0 20 20" fill="currentColor">
              <path fill-rule="evenodd" d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a.75.75 0 000 1.5h.253a.25.25 0 01.244.304l-.459 2.066A1.75 1.75 0 0010.747 15H11a.75.75 0 000-1.5h-.253a.25.25 0 01-.244-.304l.459-2.066A1.75 1.75 0 009.253 9H9z" clip-rule="evenodd" />
            </svg>
            <div>
              <p class="text-sm font-medium text-info">Link your account</p>
              <p class="text-sm text-base-content/60 mt-1">
                Sign in to manage your teams from the dashboard, link multiple machines, and recover access if you lose a key.
              </p>
            </div>
          </div>
        </div>

        <%!-- Terminal block --%>
        <div class="terminal-block rounded-lg overflow-hidden mb-6">
          <div class="flex items-center justify-between px-4 py-2.5 border-b border-white/5">
            <div class="flex items-center gap-2">
              <div class="flex gap-1.5">
                <div class="w-2.5 h-2.5 rounded-full bg-white/10"></div>
                <div class="w-2.5 h-2.5 rounded-full bg-white/10"></div>
                <div class="w-2.5 h-2.5 rounded-full bg-white/10"></div>
              </div>
              <span class="text-[10px] font-mono text-white/25 ml-2">terminal</span>
            </div>
            <button
              id="copy-btn"
              phx-click={JS.dispatch("trc:copy", detail: %{text: "npx teamrc join #{@invite_code}"})}
              class="trc-focus text-[10px] font-mono text-white/30 hover:text-white/60 transition-colors rounded px-1.5 py-0.5 hover:bg-white/5"
            >
              copy
            </button>
          </div>
          <div class="p-4">
            <div class="flex items-start gap-2">
              <span class="text-white/30 font-mono text-sm select-none">$</span>
              <code class="text-emerald-400 text-sm font-mono break-all select-all">npx teamrc join <%= @invite_code %></code>
            </div>
          </div>
        </div>

        <%!-- What happens next --%>
        <div class="rounded-lg border border-base-300 bg-base-200/30 p-4 mb-6">
          <p class="text-xs font-medium text-base-content/60 uppercase tracking-wider mb-3">
            What this does
          </p>
          <div class="space-y-2">
            <div class="flex items-start gap-2.5 text-sm text-base-content/60">
              <div class="mt-1.5 h-1 w-1 rounded-full bg-primary/40 shrink-0"></div>
              Downloads your team definition
            </div>
            <div :if={MapSet.size(@selected_platforms) > 0} class="flex items-start gap-2.5 text-sm text-base-content/60">
              <div class="mt-1.5 h-1 w-1 rounded-full bg-primary/40 shrink-0"></div>
              Generates agent files for: <%= Enum.join(selected_platform_labels(@selected_platforms, @all_platforms), ", ") %>
            </div>
            <div :if={MapSet.size(@selected_platforms) == 0} class="flex items-start gap-2.5 text-sm text-base-content/60">
              <div class="mt-1.5 h-1 w-1 rounded-full bg-primary/40 shrink-0"></div>
              Auto-detects your platforms and generates agent files
            </div>
            <div class="flex items-start gap-2.5 text-sm text-base-content/60">
              <div class="mt-1.5 h-1 w-1 rounded-full bg-primary/40 shrink-0"></div>
              Applies team skills to each platform
            </div>
            <div class="flex items-start gap-2.5 text-sm text-base-content/60">
              <div class="mt-1.5 h-1 w-1 rounded-full bg-primary/40 shrink-0"></div>
              Starts syncing team knowledge
            </div>
          </div>
        </div>

        <%!-- Clone alternative --%>
        <div class="rounded-lg border border-base-300/60 bg-base-200/20 p-4 mb-8">
          <p class="text-xs text-base-content/40 mb-1">Or clone without syncing:</p>
          <code class="text-xs font-mono text-base-content/60">npx teamrc clone <%= @invite_code %></code>
        </div>

        <button
          phx-click="reset"
          class="trc-focus text-xs font-medium text-base-content/40 hover:text-base-content/60 transition-colors rounded px-1 -ml-1"
        >
          Create another team
        </button>
      </div>
    </div>
    """
  end

  # --- Components ---

  defp step_indicator(assigns) do
    ~H"""
    <div class="flex items-center gap-1.5">
      <div class={[
        "flex items-center justify-center h-5 w-5 rounded-full text-[10px] font-semibold transition-colors",
        if(@current, do: "bg-primary text-primary-content", else:
          if(@active && !@current, do: "bg-primary/15 text-primary", else: "bg-base-300 text-base-content/30")
        )
      ]}>
        <%= if @active && !@current do %>
          <svg xmlns="http://www.w3.org/2000/svg" class="h-3 w-3" viewBox="0 0 20 20" fill="currentColor">
            <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd" />
          </svg>
        <% else %>
          <%= @number %>
        <% end %>
      </div>
      <span class={[
        "text-xs transition-colors hidden sm:inline",
        if(@current, do: "text-base-content font-medium", else:
          if(@active, do: "text-base-content/50", else: "text-base-content/30")
        )
      ]}>
        <%= @label %>
      </span>
    </div>
    """
  end
end
