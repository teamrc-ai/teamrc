defmodule TeamrcWeb.TeamLive do
  use TeamrcWeb, :live_view

  alias Phoenix.LiveView.JS
  alias Teamrc.Teams

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
      ],
      rules: [
        %{id: "write-tests", body: "Always write tests for new code. Include unit tests and integration tests where appropriate."},
        %{id: "small-commits", body: "Prefer small, reviewable commits. Each commit should represent a single logical change."}
      ],
      skills: []
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
      ],
      rules: [
        %{id: "api-first", body: "Define API contracts before implementation. Use OpenAPI or similar specs."},
        %{id: "write-tests", body: "Always write tests for new code. Include unit tests and integration tests where appropriate."}
      ],
      skills: []
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
      ],
      rules: [
        %{id: "document-findings", body: "Document all findings with severity, reproduction steps, and remediation guidance."},
        %{id: "verify-fixes", body: "Always verify that fixes actually resolve the vulnerability before closing."}
      ],
      skills: []
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
      ],
      rules: [
        %{id: "brand-voice", body: "Maintain consistent brand voice and tone across all content and channels."}
      ],
      skills: []
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
      ],
      rules: [
        %{id: "cite-sources", body: "Always cite sources. Cross-reference claims against multiple sources before reporting."}
      ],
      skills: []
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
      ],
      rules: [
        %{id: "infra-as-code", body: "All infrastructure changes must be defined as code. No manual changes to production."},
        %{id: "rollback-plan", body: "Every deployment must have a rollback plan documented before proceeding."}
      ],
      skills: []
    },
    "custom" => %{
      label: "Custom Team",
      description: "Start from scratch with your own roles",
      icon: "plus",
      team_name: "",
      members: [%{name: "", role: ""}],
      rules: [],
      skills: []
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
       rules: [],
       skills: [],
       show_advanced: false,
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
       members: Enum.map(template.members, &Map.take(&1, [:name, :role])),
       rules: template.rules,
       skills: template.skills,
       show_advanced: false
     )}
  end

  def handle_event("update_team_name", %{"value" => value}, socket) do
    {:noreply, assign(socket, team_name: value)}
  end

  def handle_event("update_member", params, socket),
    do: update_list_item(socket, :members, params, %{"name" => :name, "role" => :role})

  def handle_event("toggle_member_rule", %{"member-index" => member_idx, "rule-id" => rule_id}, socket) do
    index = String.to_integer(member_idx)
    members = List.update_at(socket.assigns.members, index, fn member ->
      current = member[:rules] || []
      if rule_id in current do
        Map.put(member, :rules, List.delete(current, rule_id))
      else
        Map.put(member, :rules, current ++ [rule_id])
      end
    end)
    {:noreply, assign(socket, members: members)}
  end

  def handle_event("toggle_member_skill", %{"member-index" => member_idx, "skill-id" => skill_id}, socket) do
    index = String.to_integer(member_idx)
    members = List.update_at(socket.assigns.members, index, fn member ->
      current = member[:skills] || []
      if skill_id in current do
        Map.put(member, :skills, List.delete(current, skill_id))
      else
        Map.put(member, :skills, current ++ [skill_id])
      end
    end)
    {:noreply, assign(socket, members: members)}
  end

  def handle_event("add_member", _params, socket),
    do: add_list_item(socket, :members, %{name: "", role: ""})

  def handle_event("remove_member", %{"index" => idx}, socket),
    do: remove_list_item(socket, :members, idx, 1)

  # --- Advanced: Rules ---

  def handle_event("toggle_advanced", _params, socket) do
    {:noreply, assign(socket, show_advanced: !socket.assigns.show_advanced)}
  end

  def handle_event("update_rule", params, socket),
    do: update_list_item(socket, :rules, params, %{"id" => :id, "body" => :body})

  def handle_event("add_rule", _params, socket),
    do: add_list_item(socket, :rules, %{id: "", body: ""})

  def handle_event("remove_rule", %{"index" => idx}, socket),
    do: remove_list_item(socket, :rules, idx)

  # --- Advanced: Skills ---

  def handle_event("update_skill", params, socket),
    do: update_list_item(socket, :skills, params, %{"id" => :id, "description" => :description, "body" => :body})

  def handle_event("add_skill", _params, socket),
    do: add_list_item(socket, :skills, %{id: "", description: "", body: ""})

  def handle_event("remove_skill", %{"index" => idx}, socket),
    do: remove_list_item(socket, :skills, idx)

  def handle_event("back_to_templates", _params, socket) do
    {:noreply, assign(socket, step: :choose_template)}
  end

  def handle_event("create_team", _params, socket) do
    rules =
      socket.assigns.rules
      |> Enum.filter(fn r -> r.id != "" end)
      |> Enum.map(fn r -> %{id: r.id, body: r.body} end)

    skills =
      socket.assigns.skills
      |> Enum.filter(fn s -> s.id != "" end)
      |> Enum.map(fn s ->
        base = %{id: s.id}
        base = if s[:description] && s.description != "", do: Map.put(base, :description, s.description), else: base
        base = if s[:body] && s.body != "", do: Map.put(base, :body, s.body), else: base
        base
      end)

    rule_ids = MapSet.new(rules, & &1.id)
    skill_ids = MapSet.new(skills, & &1.id)

    team = %{
      name: socket.assigns.team_name,
      members:
        socket.assigns.members
        |> Enum.filter(fn m -> m.name != "" end)
        |> Enum.map(fn m ->
          member = %{name: m.name, role: m.role}
          member_rules = (m[:rules] || []) |> Enum.filter(&MapSet.member?(rule_ids, &1))
          member_skills = (m[:skills] || []) |> Enum.filter(&MapSet.member?(skill_ids, &1))
          member = if member_rules != [], do: Map.put(member, :rules, member_rules), else: member
          if member_skills != [], do: Map.put(member, :skills, member_skills), else: member
        end),
      rules: rules,
      skills: skills
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
       rules: [],
       skills: [],
       show_advanced: false,
       token: nil,
       page_title: "Create Team"
     )}
  end

  # --- List helpers ---

  defp update_list_item(socket, key, %{"index" => idx, "field" => field, "value" => value}, allowed_fields) do
    case Map.get(allowed_fields, field) do
      nil -> {:noreply, socket}
      field_atom ->
        index = String.to_integer(idx)
        list = List.update_at(Map.get(socket.assigns, key), index, &Map.put(&1, field_atom, value))
        {:noreply, assign(socket, [{key, list}])}
    end
  end

  defp add_list_item(socket, key, default) do
    list = Map.get(socket.assigns, key) ++ [default]
    {:noreply, assign(socket, [{key, list}])}
  end

  defp remove_list_item(socket, key, idx, min_count \\ 0) do
    index = String.to_integer(idx)
    list = Map.get(socket.assigns, key)
    list = if length(list) > min_count, do: List.delete_at(list, index), else: list
    {:noreply, assign(socket, [{key, list}])}
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

  defp has_defined_rules?(rules), do: Enum.any?(rules, & &1.id != "")
  defp has_defined_skills?(skills), do: Enum.any?(skills, & &1.id != "")

  defp item_count(items, label) do
    count = Enum.count(items, fn i -> i.id != "" end)
    case count do
      0 -> nil
      1 -> "1 #{label}"
      n -> "#{n} #{label}s"
    end
  end

  defp step_number(:choose_template), do: 1
  defp step_number(:define), do: 2
  defp step_number(:created), do: 3

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

      <%!-- Step 1: Choose template --%>
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
              <svg
                xmlns="http://www.w3.org/2000/svg"
                fill="none"
                viewBox="0 0 24 24"
                stroke-width="1.5"
                stroke="currentColor"
                class="h-[18px] w-[18px]"
              >
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
              <path fill-rule="evenodd" d="M7.21 14.77a.75.75 0 01.02-1.06L11.168 10 7.23 6.29a.75.75 0 111.04-1.08l4.5 4.25a.75.75 0 010 1.08l-4.5 4.25a.75.75 0 01-1.06-.02z" clip-rule="evenodd" />
            </svg>
          </button>
        </div>
      </div>

      <%!-- Step 2: Customize team --%>
      <div :if={@step == :define}>
        <button
          phx-click="back_to_templates"
          class="trc-focus mb-6 inline-flex items-center gap-1.5 text-xs font-medium text-base-content/40 hover:text-base-content/70 transition-colors rounded px-1 -ml-1"
        >
          <svg xmlns="http://www.w3.org/2000/svg" class="h-3.5 w-3.5" viewBox="0 0 20 20" fill="currentColor">
            <path fill-rule="evenodd" d="M9.707 16.707a1 1 0 01-1.414 0l-6-6a1 1 0 010-1.414l6-6a1 1 0 011.414 1.414L5.414 9H17a1 1 0 110 2H5.414l4.293 4.293a1 1 0 010 1.414z" clip-rule="evenodd" />
          </svg>
          Templates
        </button>

        <div class="mb-8">
          <h1 class="text-2xl font-bold tracking-tight mb-1">Configure your team</h1>
          <p class="text-sm text-base-content/50">
            Name your team, adjust roles, then create.
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

          <%!-- Members --%>
          <div>
            <label class="block text-xs font-medium text-base-content/60 uppercase tracking-wider mb-3">
              Members
            </label>
            <div class="space-y-2">
              <div
                :for={{member, idx} <- Enum.with_index(@members)}
                class="group flex items-start gap-3 rounded-md border border-base-300 bg-base-200/30 p-3"
              >
                <div class="flex h-7 w-7 shrink-0 items-center justify-center rounded bg-base-200 text-xs font-mono text-base-content/40 mt-0.5">
                  <%= idx + 1 %>
                </div>
                <div class="flex-1 space-y-2">
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
                  <%!-- Per-member rule/skill assignment (shown when advanced + rules/skills exist) --%>
                  <div :if={@show_advanced && (has_defined_rules?(@rules) || has_defined_skills?(@skills))} class="pt-1 space-y-1.5">
                    <div :if={has_defined_rules?(@rules)} class="flex flex-wrap items-center gap-1.5">
                      <span class="text-[10px] uppercase tracking-wider text-base-content/30 font-medium mr-0.5">Rules</span>
                      <button
                        :for={rule <- Enum.filter(@rules, & &1.id != "")}
                        phx-click="toggle_member_rule"
                        phx-value-member-index={idx}
                        phx-value-rule-id={rule.id}
                        class={[
                          "trc-focus inline-flex items-center rounded px-1.5 py-0.5 text-[11px] font-mono transition-colors",
                          if(rule.id in (member[:rules] || []),
                            do: "bg-primary/15 text-primary border border-primary/30",
                            else: "bg-base-200/50 text-base-content/30 border border-transparent hover:border-base-300"
                          )
                        ]}
                      >
                        <%= rule.id %>
                      </button>
                    </div>
                    <div :if={has_defined_skills?(@skills)} class="flex flex-wrap items-center gap-1.5">
                      <span class="text-[10px] uppercase tracking-wider text-base-content/30 font-medium mr-0.5">Skills</span>
                      <button
                        :for={skill <- Enum.filter(@skills, & &1.id != "")}
                        phx-click="toggle_member_skill"
                        phx-value-member-index={idx}
                        phx-value-skill-id={skill.id}
                        class={[
                          "trc-focus inline-flex items-center rounded px-1.5 py-0.5 text-[11px] font-mono transition-colors",
                          if(skill.id in (member[:skills] || []),
                            do: "bg-primary/15 text-primary border border-primary/30",
                            else: "bg-base-200/50 text-base-content/30 border border-transparent hover:border-base-300"
                          )
                        ]}
                      >
                        <%= skill.id %>
                      </button>
                    </div>
                  </div>
                </div>
                <button
                  :if={length(@members) > 1}
                  phx-click="remove_member"
                  phx-value-index={idx}
                  class="trc-focus mt-1.5 rounded p-1 text-base-content/20 hover:bg-error/10 hover:text-error transition-colors sm:opacity-0 sm:group-hover:opacity-100"
                  aria-label="Remove member"
                >
                  <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
                    <path fill-rule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clip-rule="evenodd" />
                  </svg>
                </button>
              </div>
            </div>

            <button
              phx-click="add_member"
              class="trc-focus mt-3 inline-flex items-center gap-1.5 rounded px-2 py-1 text-xs font-medium text-base-content/40 hover:text-primary hover:bg-primary/5 transition-colors"
            >
              <svg xmlns="http://www.w3.org/2000/svg" class="h-3.5 w-3.5" viewBox="0 0 20 20" fill="currentColor">
                <path fill-rule="evenodd" d="M10 3a1 1 0 011 1v5h5a1 1 0 110 2h-5v5a1 1 0 11-2 0v-5H4a1 1 0 110-2h5V4a1 1 0 011-1z" clip-rule="evenodd" />
              </svg>
              Add member
            </button>
          </div>

          <%!-- Advanced configuration --%>
          <div class="border-t border-base-300/60 pt-6">
            <button
              phx-click="toggle_advanced"
              class="trc-focus inline-flex items-center gap-2 text-xs font-medium text-base-content/40 hover:text-base-content/60 transition-colors rounded px-1 -ml-1"
            >
              <svg
                xmlns="http://www.w3.org/2000/svg"
                class={"h-3.5 w-3.5 transition-transform duration-150 #{if @show_advanced, do: "rotate-90", else: ""}"}
                viewBox="0 0 20 20"
                fill="currentColor"
              >
                <path fill-rule="evenodd" d="M7.21 14.77a.75.75 0 01.02-1.06L11.168 10 7.23 6.29a.75.75 0 111.04-1.08l4.5 4.25a.75.75 0 010 1.08l-4.5 4.25a.75.75 0 01-1.06-.02z" clip-rule="evenodd" />
              </svg>
              Advanced
              <span :if={item_count(@rules, "rule")} class="font-mono text-base-content/30">
                (<%= item_count(@rules, "rule") %>)
              </span>
              <span :if={item_count(@skills, "skill")} class="font-mono text-base-content/30">
                (<%= item_count(@skills, "skill") %>)
              </span>
            </button>
          </div>

          <%!-- Advanced: Rules --%>
          <div :if={@show_advanced} class="space-y-8 animate-[fadeIn_150ms_ease-out]">
            <div>
              <div class="flex items-baseline justify-between mb-3">
                <label class="block text-xs font-medium text-base-content/60 uppercase tracking-wider">
                  Rules
                </label>
                <span class="text-xs text-base-content/30">
                  Policies for agents — assign per member or all inherit
                </span>
              </div>
              <div class="space-y-2">
                <div
                  :for={{rule, idx} <- Enum.with_index(@rules)}
                  class="group flex items-start gap-3 rounded-md border border-base-300 bg-base-200/30 p-3"
                >
                  <div class="flex-1 space-y-2">
                    <input
                      type="text"
                      value={rule.id}
                      phx-keyup="update_rule"
                      phx-value-index={idx}
                      phx-value-field="id"
                      placeholder="rule-id"
                      class="trc-focus w-full rounded border border-base-300 bg-base-100 px-2.5 py-1.5 text-sm font-mono placeholder:text-base-content/25 focus:border-primary/50 focus:ring-1 focus:ring-primary/20 transition-colors"
                    />
                    <textarea
                      phx-keyup="update_rule"
                      phx-value-index={idx}
                      phx-value-field="body"
                      placeholder="Describe the rule..."
                      rows="2"
                      class="trc-focus w-full rounded border border-base-300 bg-base-100 px-2.5 py-1.5 text-sm placeholder:text-base-content/25 focus:border-primary/50 focus:ring-1 focus:ring-primary/20 transition-colors resize-none"
                    ><%= rule.body %></textarea>
                  </div>
                  <button
                    phx-click="remove_rule"
                    phx-value-index={idx}
                    class="trc-focus mt-1.5 rounded p-1 text-base-content/20 hover:bg-error/10 hover:text-error transition-colors sm:opacity-0 sm:group-hover:opacity-100"
                    aria-label="Remove rule"
                  >
                    <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
                      <path fill-rule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clip-rule="evenodd" />
                    </svg>
                  </button>
                </div>
              </div>
              <button
                phx-click="add_rule"
                class="trc-focus mt-3 inline-flex items-center gap-1.5 rounded px-2 py-1 text-xs font-medium text-base-content/40 hover:text-primary hover:bg-primary/5 transition-colors"
              >
                <svg xmlns="http://www.w3.org/2000/svg" class="h-3.5 w-3.5" viewBox="0 0 20 20" fill="currentColor">
                  <path fill-rule="evenodd" d="M10 3a1 1 0 011 1v5h5a1 1 0 110 2h-5v5a1 1 0 11-2 0v-5H4a1 1 0 110-2h5V4a1 1 0 011-1z" clip-rule="evenodd" />
                </svg>
                Add rule
              </button>
            </div>

            <%!-- Advanced: Skills --%>
            <div>
              <div class="flex items-baseline justify-between mb-3">
                <label class="block text-xs font-medium text-base-content/60 uppercase tracking-wider">
                  Skills
                </label>
                <span class="text-xs text-base-content/30">
                  Capabilities — assign per member or all inherit
                </span>
              </div>
              <div class="space-y-2">
                <div
                  :for={{skill, idx} <- Enum.with_index(@skills)}
                  class="group flex items-start gap-3 rounded-md border border-base-300 bg-base-200/30 p-3"
                >
                  <div class="flex-1 space-y-2">
                    <input
                      type="text"
                      value={skill.id}
                      phx-keyup="update_skill"
                      phx-value-index={idx}
                      phx-value-field="id"
                      placeholder="skill-id"
                      class="trc-focus w-full rounded border border-base-300 bg-base-100 px-2.5 py-1.5 text-sm font-mono placeholder:text-base-content/25 focus:border-primary/50 focus:ring-1 focus:ring-primary/20 transition-colors"
                    />
                    <input
                      type="text"
                      value={skill[:description] || ""}
                      phx-keyup="update_skill"
                      phx-value-index={idx}
                      phx-value-field="description"
                      placeholder="Description (optional)"
                      class="trc-focus w-full rounded border border-base-300 bg-base-100 px-2.5 py-1.5 text-sm placeholder:text-base-content/25 focus:border-primary/50 focus:ring-1 focus:ring-primary/20 transition-colors"
                    />
                    <textarea
                      phx-keyup="update_skill"
                      phx-value-index={idx}
                      phx-value-field="body"
                      placeholder="Skill instructions (optional)"
                      rows="2"
                      class="trc-focus w-full rounded border border-base-300 bg-base-100 px-2.5 py-1.5 text-sm placeholder:text-base-content/25 focus:border-primary/50 focus:ring-1 focus:ring-primary/20 transition-colors resize-none"
                    ><%= skill[:body] || "" %></textarea>
                  </div>
                  <button
                    phx-click="remove_skill"
                    phx-value-index={idx}
                    class="trc-focus mt-1.5 rounded p-1 text-base-content/20 hover:bg-error/10 hover:text-error transition-colors sm:opacity-0 sm:group-hover:opacity-100"
                    aria-label="Remove skill"
                  >
                    <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" viewBox="0 0 20 20" fill="currentColor">
                      <path fill-rule="evenodd" d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z" clip-rule="evenodd" />
                    </svg>
                  </button>
                </div>
              </div>
              <button
                phx-click="add_skill"
                class="trc-focus mt-3 inline-flex items-center gap-1.5 rounded px-2 py-1 text-xs font-medium text-base-content/40 hover:text-primary hover:bg-primary/5 transition-colors"
              >
                <svg xmlns="http://www.w3.org/2000/svg" class="h-3.5 w-3.5" viewBox="0 0 20 20" fill="currentColor">
                  <path fill-rule="evenodd" d="M10 3a1 1 0 011 1v5h5a1 1 0 110 2h-5v5a1 1 0 11-2 0v-5H4a1 1 0 110-2h5V4a1 1 0 011-1z" clip-rule="evenodd" />
                </svg>
                Add skill
              </button>
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

      <%!-- Step 3: Team created --%>
      <div :if={@step == :created}>
        <div class="mb-8">
          <div class="flex items-center gap-3 mb-4">
            <div class="flex h-8 w-8 items-center justify-center rounded-full bg-success/15">
              <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4 text-success" viewBox="0 0 20 20" fill="currentColor">
                <path fill-rule="evenodd" d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z" clip-rule="evenodd" />
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
              phx-click={JS.dispatch("tb:copy", detail: %{text: "npx teamrc join #{@token}"})}
              class="trc-focus text-[10px] font-mono text-white/30 hover:text-white/60 transition-colors rounded px-1.5 py-0.5 hover:bg-white/5"
            >
              copy
            </button>
          </div>
          <div class="p-4">
            <div class="flex items-start gap-2">
              <span class="text-white/30 font-mono text-sm select-none">$</span>
              <code class="text-emerald-400 text-sm font-mono break-all select-all">npx teamrc join <%= @token %></code>
            </div>
          </div>
        </div>

        <%!-- What happens next --%>
        <div class="rounded-lg border border-base-300 bg-base-200/30 p-4 mb-8">
          <p class="text-xs font-medium text-base-content/60 uppercase tracking-wider mb-3">
            What this does
          </p>
          <div class="space-y-2">
            <div class="flex items-start gap-2.5 text-sm text-base-content/60">
              <div class="mt-1.5 h-1 w-1 rounded-full bg-primary/40 shrink-0"></div>
              Detects your platform (Claude Code, Cursor, Codex, etc.)
            </div>
            <div class="flex items-start gap-2.5 text-sm text-base-content/60">
              <div class="mt-1.5 h-1 w-1 rounded-full bg-primary/40 shrink-0"></div>
              Scaffolds all team agents with their roles locally
            </div>
            <div class="flex items-start gap-2.5 text-sm text-base-content/60">
              <div class="mt-1.5 h-1 w-1 rounded-full bg-primary/40 shrink-0"></div>
              Applies team rules and skills to each platform
            </div>
            <div class="flex items-start gap-2.5 text-sm text-base-content/60">
              <div class="mt-1.5 h-1 w-1 rounded-full bg-primary/40 shrink-0"></div>
              Sets up automatic sync on every session start
            </div>
          </div>
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

  # --- Step indicator component ---

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
