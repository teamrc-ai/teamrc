defmodule TeambridgeWeb.TeamLive do
  use TeambridgeWeb, :live_view

  alias Teambridge.Teams

  @templates %{
    "fullstack" => %{
      label: "Full-Stack Product",
      description: "Ship features end-to-end with PM, design, and engineering",
      icon: "code",
      team_name: "product-team",
      members: [
        %{name: "product-manager", role: "Define requirements, prioritize the backlog, write user stories and acceptance criteria"},
        %{name: "team-lead", role: "Break down work, coordinate across agents, make technical decisions, unblock the team"},
        %{name: "ux-designer", role: "Design user flows, wireframes, and UI components. Ensure accessibility and usability"},
        %{name: "frontend-dev", role: "Build UI components, integrate APIs, implement responsive layouts and interactions"},
        %{name: "backend-dev", role: "Design APIs, write business logic, manage data models and database queries"},
        %{name: "qa-engineer", role: "Write test plans, automate E2E and integration tests, validate edge cases and regressions"}
      ]
    },
    "backend" => %{
      label: "Backend / API",
      description: "Build APIs, services, and data pipelines",
      icon: "server",
      team_name: "backend-team",
      members: [
        %{name: "architect", role: "Design system architecture, define API contracts, choose technologies and patterns"},
        %{name: "implementer", role: "Write clean, tested code following the architect's design and API specs"},
        %{name: "reviewer", role: "Review code for correctness, performance, security, and adherence to standards"},
        %{name: "dba", role: "Design schemas, write migrations, optimize queries, manage data integrity"}
      ]
    },
    "security" => %{
      label: "Security Testing",
      description: "Assess, test, and harden your application security",
      icon: "shield",
      team_name: "security-team",
      members: [
        %{name: "pentest-lead", role: "Plan testing scope, coordinate assessments, prioritize findings by risk severity"},
        %{name: "vuln-analyst", role: "Scan for OWASP Top 10 vulnerabilities, test authentication and authorization flows"},
        %{name: "code-auditor", role: "Review source code for injection flaws, insecure patterns, and dependency risks"},
        %{name: "report-writer", role: "Document findings with reproduction steps, impact analysis, and remediation guidance"}
      ]
    },
    "marketing" => %{
      label: "Marketing & Growth",
      description: "Plan campaigns, create content, and drive growth",
      icon: "megaphone",
      team_name: "marketing-team",
      members: [
        %{name: "marketing-lead", role: "Define campaign strategy, set KPIs, coordinate messaging across channels"},
        %{name: "copywriter", role: "Write landing pages, email sequences, ad copy, and social media posts"},
        %{name: "seo-specialist", role: "Research keywords, optimize content for search, analyze traffic and rankings"},
        %{name: "analytics-lead", role: "Track campaign performance, build dashboards, run A/B tests, report on ROI"}
      ]
    },
    "research" => %{
      label: "Research & Analysis",
      description: "Deep research with verification and synthesis",
      icon: "search",
      team_name: "research-team",
      members: [
        %{name: "lead-researcher", role: "Define research questions, coordinate investigation, synthesize findings into actionable insights"},
        %{name: "analyst", role: "Gather and analyze data, identify patterns, build models and visualizations"},
        %{name: "fact-checker", role: "Verify claims, cross-reference sources, flag inconsistencies and biases"},
        %{name: "writer", role: "Produce clear, well-structured reports and presentations from research findings"}
      ]
    },
    "devops" => %{
      label: "DevOps & Infrastructure",
      description: "Manage deployments, monitoring, and reliability",
      icon: "wrench",
      team_name: "devops-team",
      members: [
        %{name: "platform-engineer", role: "Design and maintain infrastructure, CI/CD pipelines, and developer tooling"},
        %{name: "sre", role: "Monitor reliability, respond to incidents, define SLOs and error budgets"},
        %{name: "security-engineer", role: "Audit configurations, scan for vulnerabilities, enforce security policies and compliance"}
      ]
    },
    "custom" => %{
      label: "Custom Team",
      description: "Start from scratch with your own roles",
      icon: "plus",
      team_name: "",
      members: [%{name: "", role: ""}]
    }
  }

  @template_order ["fullstack", "backend", "security", "marketing", "research", "devops", "custom"]

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Create Team",
       team_name: "",
       members: [%{name: "", role: ""}],
       token: nil,
       step: :choose_template,
       templates: @templates,
       template_order: @template_order
     )}
  end

  @impl true
  def handle_event("select_template", %{"template" => template_key}, socket) do
    template = Map.get(@templates, template_key)

    {:noreply,
     assign(socket,
       step: :define,
       team_name: template.team_name,
       members: Enum.map(template.members, &Map.take(&1, [:name, :role]))
     )}
  end

  def handle_event("update_team_name", %{"value" => value}, socket) do
    {:noreply, assign(socket, team_name: value)}
  end

  def handle_event("update_member", %{"index" => idx, "field" => field, "value" => value}, socket) do
    field_atom =
      case field do
        "name" -> :name
        "role" -> :role
        _ -> nil
      end

    if field_atom == nil do
      {:noreply, socket}
    else
      index = String.to_integer(idx)

      members =
        List.update_at(socket.assigns.members, index, fn member ->
          Map.put(member, field_atom, value)
        end)

      {:noreply, assign(socket, members: members)}
    end
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

  def handle_event("back_to_templates", _params, socket) do
    {:noreply, assign(socket, step: :choose_template)}
  end

  def handle_event("create_team", _params, socket) do
    team = %{
      name: socket.assigns.team_name,
      members:
        socket.assigns.members
        |> Enum.filter(fn m -> m.name != "" end)
        |> Enum.map(fn m -> %{name: m.name, role: m.role} end)
    }

    {:ok, invite_code} = Teams.create_team_with_invite(team)

    {:noreply,
     assign(socket,
       step: :created,
       token: invite_code,
       page_title: "Team Created"
     )}
  end

  def handle_event("reset", _params, socket) do
    {:noreply,
     assign(socket,
       step: :choose_template,
       team_name: "",
       members: [%{name: "", role: ""}],
       token: nil,
       page_title: "Create Team"
     )}
  end

  defp template_icon("code") do
    ~s(<path stroke-linecap="round" stroke-linejoin="round" d="M17.25 6.75 22.5 12l-5.25 5.25m-10.5 0L1.5 12l5.25-5.25m7.5-3-4.5 16.5" />)
  end

  defp template_icon("search") do
    ~s(<path stroke-linecap="round" stroke-linejoin="round" d="m21 21-5.197-5.197m0 0A7.5 7.5 0 1 0 5.196 5.196a7.5 7.5 0 0 0 10.607 10.607Z" />)
  end

  defp template_icon("server") do
    ~s(<path stroke-linecap="round" stroke-linejoin="round" d="M5.25 14.25h13.5m-13.5 0a3 3 0 0 1-3-3m3 3a3 3 0 1 0 0 6h13.5a3 3 0 1 0 0-6m-16.5-3a3 3 0 0 1 3-3h13.5a3 3 0 0 1 3 3m-19.5 0a4.5 4.5 0 0 1 .9-2.7L5.737 5.1a3.375 3.375 0 0 1 2.7-1.35h7.126c1.062 0 2.062.5 2.7 1.35l2.587 3.45a4.5 4.5 0 0 1 .9 2.7m0 0a3 3 0 0 1-3 3m0 3h.008v.008h-.008v-.008Zm0-6h.008v.008h-.008v-.008Zm-3 6h.008v.008h-.008v-.008Zm0-6h.008v.008h-.008v-.008Z" />)
  end

  defp template_icon("shield") do
    ~s(<path stroke-linecap="round" stroke-linejoin="round" d="M9 12.75 11.25 15 15 9.75m-3-7.036A11.959 11.959 0 0 1 3.598 6 11.99 11.99 0 0 0 3 9.749c0 5.592 3.824 10.29 9 11.623 5.176-1.332 9-6.03 9-11.622 0-1.31-.21-2.571-.598-3.751h-.152c-3.196 0-6.1-1.248-8.25-3.285Z" />)
  end

  defp template_icon("megaphone") do
    ~s(<path stroke-linecap="round" stroke-linejoin="round" d="M10.34 15.84c-.688-.06-1.386-.09-2.09-.09H7.5a4.5 4.5 0 1 1 0-9h.75c.704 0 1.402-.03 2.09-.09m0 9.18c.253.962.584 1.892.985 2.783.247.55.06 1.21-.463 1.511l-.657.38a.954.954 0 0 1-1.305-.427 19.867 19.867 0 0 1-1.14-2.66m2.58-1.587-.58.344a15.003 15.003 0 0 1-2 .854m2.58-1.198c2.094-.656 4.108-1.594 6.01-2.79a.75.75 0 0 0 0-1.284 24.138 24.138 0 0 0-6.01-2.79m0 6.864V6.916" />)
  end

  defp template_icon("wrench") do
    ~s(<path stroke-linecap="round" stroke-linejoin="round" d="M11.42 15.17 17.25 21A2.652 2.652 0 0 0 21 17.25l-5.877-5.877M11.42 15.17l2.496-3.03c.317-.384.74-.626 1.208-.766M11.42 15.17l-4.655 5.653a2.548 2.548 0 1 1-3.586-3.586l6.837-5.63m5.108-.233c.55-.164 1.163-.188 1.743-.14a4.5 4.5 0 0 0 4.486-6.336l-3.276 3.277a3.004 3.004 0 0 1-2.25-2.25l3.276-3.276a4.5 4.5 0 0 0-6.336 4.486c.049.58.025 1.193-.14 1.743Z" />)
  end

  defp template_icon("plus") do
    ~s(<path stroke-linecap="round" stroke-linejoin="round" d="M12 4.5v15m7.5-7.5h-15" />)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="max-w-2xl mx-auto py-12 px-4">
      <%!-- Step 1: Choose template --%>
      <div :if={@step == :choose_template}>
        <h1 class="text-3xl font-bold text-zinc-900 mb-2">Create a Team</h1>
        <p class="text-zinc-500 mb-8">
          Choose a starting point for your agent team.
        </p>

        <div class="grid gap-3">
          <button
            :for={key <- @template_order}
            phx-click="select_template"
            phx-value-template={key}
            class="group flex items-start gap-4 rounded-lg border border-zinc-200 bg-white p-4 text-left transition-all hover:border-zinc-400 hover:shadow-sm"
          >
            <div class="flex h-10 w-10 shrink-0 items-center justify-center rounded-lg bg-zinc-100 text-zinc-500 group-hover:bg-zinc-200 group-hover:text-zinc-700 transition-colors">
              <svg
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
                stroke-width="1.5"
                stroke="currentColor"
                class="h-5 w-5"
              >
                <%= raw(template_icon(@templates[key].icon)) %>
              </svg>
            </div>
            <div>
              <div class="font-semibold text-zinc-900"><%= @templates[key].label %></div>
              <div class="text-sm text-zinc-500 mt-0.5"><%= @templates[key].description %></div>
              <div :if={key != "custom"} class="mt-2 flex flex-wrap gap-1.5">
                <span
                  :for={member <- @templates[key].members}
                  class="inline-flex items-center rounded-full bg-zinc-100 px-2.5 py-0.5 text-xs font-medium text-zinc-600"
                >
                  <%= member.name %>
                </span>
              </div>
            </div>
          </button>
        </div>
      </div>

      <%!-- Step 2: Customize team --%>
      <div :if={@step == :define}>
        <button
          phx-click="back_to_templates"
          class="mb-6 inline-flex items-center gap-1 text-sm text-zinc-500 hover:text-zinc-700 transition-colors"
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            class="h-4 w-4"
            viewBox="0 0 20 20"
            fill="currentColor"
          >
            <path
              fill-rule="evenodd"
              d="M9.707 16.707a1 1 0 01-1.414 0l-6-6a1 1 0 010-1.414l6-6a1 1 0 011.414 1.414L5.414 9H17a1 1 0 110 2H5.414l4.293 4.293a1 1 0 010 1.414z"
              clip-rule="evenodd"
            />
          </svg>
          Back to templates
        </button>

        <h1 class="text-3xl font-bold text-zinc-900 mb-2">Customize Your Team</h1>
        <p class="text-zinc-500 mb-8">
          Edit the roles below or add your own.
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
                    placeholder="Role description"
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
                  <svg xmlns="http://www.w3.org/2000/svg" class="h-5 w-5" viewBox="0 0 20 20" fill="currentColor">
                    <path fill-rule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clip-rule="evenodd" />
                  </svg>
                </button>
              </div>
            </div>

            <button
              phx-click="add_member"
              class="mt-3 inline-flex items-center gap-1 text-sm font-medium text-zinc-600 hover:text-zinc-900 transition-colors"
            >
              <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
                <path fill-rule="evenodd" d="M10 3a1 1 0 011 1v5h5a1 1 0 110 2h-5v5a1 1 0 11-2 0v-5H4a1 1 0 110-2h5V4a1 1 0 011-1z" clip-rule="evenodd" />
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

      <%!-- Step 3: Team created --%>
      <div :if={@step == :created}>
        <div class="mb-6 flex items-center gap-3">
          <div class="flex h-10 w-10 items-center justify-center rounded-full bg-green-100">
            <svg xmlns="http://www.w3.org/2000/svg" class="h-6 w-6 text-green-600" viewBox="0 0 20 20" fill="currentColor">
              <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd" />
            </svg>
          </div>
          <div>
            <h1 class="text-2xl font-bold text-zinc-900">
              Team "<%= @team_name %>" created
            </h1>
            <p class="text-sm text-zinc-500">Run this on each machine to connect.</p>
          </div>
        </div>

        <div class="rounded-lg bg-zinc-900 p-4 mb-6">
          <p class="text-xs text-zinc-400 mb-2 font-medium uppercase tracking-wide">
            Join command
          </p>
          <code class="text-green-400 text-sm font-mono break-all">
            npx teambridge join <%= @token %>
          </code>
        </div>

        <div class="rounded-lg border border-zinc-200 bg-zinc-50 p-4 mb-8">
          <p class="text-sm font-medium text-zinc-700 mb-2">
            This command will:
          </p>
          <ul class="space-y-1 text-sm text-zinc-600">
            <li class="flex items-start gap-2">
              <span class="mt-1 block h-1.5 w-1.5 rounded-full bg-zinc-400 shrink-0"></span>
              Detect your platform (Claude Code, OpenClaw, etc.)
            </li>
            <li class="flex items-start gap-2">
              <span class="mt-1 block h-1.5 w-1.5 rounded-full bg-zinc-400 shrink-0"></span>
              Scaffold all team agents with their roles locally
            </li>
            <li class="flex items-start gap-2">
              <span class="mt-1 block h-1.5 w-1.5 rounded-full bg-zinc-400 shrink-0"></span>
              Set up automatic sync on every session start
            </li>
            <li class="flex items-start gap-2">
              <span class="mt-1 block h-1.5 w-1.5 rounded-full bg-zinc-400 shrink-0"></span>
              Share memory and context across all connected platforms
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
