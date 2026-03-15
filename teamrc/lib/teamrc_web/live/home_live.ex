defmodule TeamrcWeb.HomeLive do
  use TeamrcWeb, :live_view

  @agents [
    %{id: "reviewer", name: "reviewer", desc: "Reviews PRs for correctness and style", default: true},
    %{id: "architect", name: "architect", desc: "Plans system design and architecture", default: true},
    %{id: "tester", name: "tester", desc: "Writes and maintains test suites", default: false},
    %{id: "deployer", name: "deployer", desc: "Manages deployments and infrastructure", default: false},
    %{id: "docs", name: "docs-writer", desc: "Writes and updates documentation", default: false}
  ]

  @impl true
  def mount(_params, _session, socket) do
    selected = @agents |> Enum.filter(& &1.default) |> Enum.map(& &1.id) |> MapSet.new()

    {:ok,
     assign(socket,
       page_title: "Keep Your AI Agents in Sync Across Machines and VMs",
       og_description:
         "Claude Code on your laptop, OpenClaw on a VM? teamrc keeps your agent configs in sync across machines, platforms, and projects. Open-source CLI.",
       hero_tab: "new",
       bottom_tab: "new",
       selected_agents: selected,
       agents: @agents
     )}
  end

  @impl true
  def handle_event("set_hero_tab", %{"tab" => tab}, socket) when tab in ["new", "clone", "local"] do
    {:noreply, assign(socket, :hero_tab, tab)}
  end

  @impl true
  def handle_event("set_bottom_tab", %{"tab" => tab}, socket) when tab in ["new", "clone", "local"] do
    {:noreply, assign(socket, :bottom_tab, tab)}
  end

  @impl true
  def handle_event("toggle_agent", %{"agent" => agent_id}, socket) do
    selected = socket.assigns.selected_agents

    selected =
      if MapSet.member?(selected, agent_id),
        do: MapSet.delete(selected, agent_id),
        else: MapSet.put(selected, agent_id)

    {:noreply, assign(socket, :selected_agents, selected)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <%!-- Hero --%>
    <div class="pt-12 sm:pt-20 pb-12 text-center">
      <h1 class="text-4xl sm:text-5xl lg:text-6xl font-bold tracking-tight leading-[1.1] text-base-content">
        Keep your AI agents<br />in sync everywhere.
      </h1>

      <p class="text-base sm:text-lg text-base-content/50 mt-6 max-w-xl mx-auto leading-relaxed">
        One config for every machine and platform. Claude Code, Cursor, Codex,
        Gemini, OpenClaw - all from the same source.
      </p>

      <div class="mt-10 flex flex-col sm:flex-row items-center justify-center gap-3">
        <a
          href="/new"
          class="trc-focus inline-flex items-center gap-2 rounded-lg bg-base-content px-5 py-2.5 text-sm font-medium text-base-100 hover:bg-base-content/85 transition-colors"
        >
          Start building
          <svg xmlns="http://www.w3.org/2000/svg" class="h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" d="M13.5 4.5 21 12m0 0-7.5 7.5M21 12H3" />
          </svg>
        </a>
        <a
          href="/guide"
          class="trc-focus inline-flex items-center gap-2 rounded-lg border border-base-300 px-5 py-2.5 text-sm font-medium text-base-content/60 hover:text-base-content hover:border-base-content/30 transition-colors"
        >
          Read the guide
        </a>
      </div>

      <div class="mt-10 flex justify-center">
        <.terminal_cta tab={@hero_tab} event="set_hero_tab" id_suffix="hero" />
      </div>
    </div>

    <%!-- Platforms --%>
    <section class="py-10 border-y border-base-300/50">
      <div class="flex flex-wrap items-center justify-center gap-x-8 gap-y-3">
        <span class="text-xs text-base-content/30 uppercase tracking-widest font-medium">Works with</span>
        <span class="text-sm text-base-content/50 font-mono">Claude Code</span>
        <span class="text-sm text-base-content/50 font-mono">Cursor</span>
        <span class="text-sm text-base-content/50 font-mono">Codex</span>
        <span class="text-sm text-base-content/50 font-mono">Gemini</span>
        <span class="text-sm text-base-content/50 font-mono">OpenClaw</span>
      </div>
    </section>

    <%!-- How it works --%>
    <section class="py-20">
      <p class="text-xs text-base-content/30 uppercase tracking-widest font-medium mb-3">How it works</p>
      <h2 class="text-2xl sm:text-3xl font-bold tracking-tight">Three steps to sync.</h2>

      <div class="mt-12 grid gap-12 sm:grid-cols-3">
        <div>
          <p class="text-xs font-mono text-base-content/30 mb-3">01</p>
          <h3 class="text-sm font-semibold mb-2">Define your agents once</h3>
          <p class="text-sm text-base-content/50 leading-relaxed">
            A single
            <code class="font-mono text-xs">.teamrc.yaml</code>
            describes your team - agents, skills, and how they're wired together.
          </p>
        </div>
        <div>
          <p class="text-xs font-mono text-base-content/30 mb-3">02</p>
          <h3 class="text-sm font-semibold mb-2">Each platform gets native files</h3>
          <p class="text-sm text-base-content/50 leading-relaxed">
            Claude Code gets Markdown. Codex gets TOML. Gemini gets YAML frontmatter.
            All generated from the same source.
          </p>
        </div>
        <div>
          <p class="text-xs font-mono text-base-content/30 mb-3">03</p>
          <h3 class="text-sm font-semibold mb-2">Sync across every machine</h3>
          <p class="text-sm text-base-content/50 leading-relaxed">
            Run <code class="font-mono text-xs">teamrc sync</code> anywhere.
            The relay pushes changes and merges knowledge automatically.
          </p>
        </div>
      </div>
    </section>

    <%!-- Interactive Config Builder --%>
    <section class="py-20 border-t border-base-300/50">
      <p class="text-xs text-base-content/30 uppercase tracking-widest font-medium mb-3">Try it</p>
      <h2 class="text-2xl sm:text-3xl font-bold tracking-tight">Build your team.</h2>
      <p class="text-sm text-base-content/50 mt-2 mb-10">Toggle agents and watch the config update live.</p>

      <div class="grid sm:grid-cols-2 gap-6">
        <%!-- Agent picker --%>
        <div class="space-y-2">
          <div
            :for={agent <- @agents}
            phx-click="toggle_agent"
            phx-value-agent={agent.id}
            class={"trc-focus cursor-pointer rounded-lg border px-4 py-3 transition-colors " <>
              if(MapSet.member?(@selected_agents, agent.id),
                do: "border-base-content/20 bg-base-100",
                else: "border-base-300/50 bg-base-200/20 opacity-50"
              )}
          >
            <div class="flex items-center justify-between">
              <span class="text-sm font-mono font-medium">{agent.name}</span>
              <div class={"w-4 h-4 rounded border flex items-center justify-center text-[10px] " <>
                if(MapSet.member?(@selected_agents, agent.id),
                  do: "border-base-content bg-base-content text-base-100",
                  else: "border-base-300"
                )}>
                <span :if={MapSet.member?(@selected_agents, agent.id)}>✓</span>
              </div>
            </div>
            <p class="text-xs text-base-content/45 mt-0.5">{agent.desc}</p>
          </div>
        </div>

        <%!-- Live YAML output --%>
        <div>
          <p class="text-xs font-mono text-base-content/40 mb-2">.teamrc.yaml</p>
          <div class="terminal-block rounded-lg p-4 text-sm font-mono leading-relaxed">
            <div><span class="text-blue-400">team</span><span class="text-white/50">:</span> <span class="text-emerald-400">my-project</span></div>
            <div class="mt-2"><span class="text-blue-400">agents</span><span class="text-white/50">:</span></div>
            <%= for agent <- @agents, MapSet.member?(@selected_agents, agent.id) do %>
              <div class="text-white/80 pl-4">- <span class="text-blue-400">name</span><span class="text-white/50">:</span> <span class="text-emerald-400">{agent.name}</span></div>
              <div class="text-white/80 pl-6"><span class="text-blue-400">description</span><span class="text-white/50">:</span> <span class="text-emerald-400">{agent.desc}</span></div>
            <% end %>
            <div :if={MapSet.size(@selected_agents) == 0} class="text-white/30 pl-4">  # select agents to add them</div>
          </div>
        </div>
      </div>
    </section>

    <%!-- Diff Propagation --%>
    <section class="py-20 border-t border-base-300/50">
      <p class="text-xs text-base-content/30 uppercase tracking-widest font-medium mb-3">Sync</p>
      <h2 class="text-2xl sm:text-3xl font-bold tracking-tight">Change once, update everywhere.</h2>
      <p class="text-sm text-base-content/50 mt-2 mb-10">Edit one agent in your YAML. The change propagates to every platform.</p>

      <div class="space-y-6">
        <%!-- The diff in .teamrc.yaml --%>
        <div>
          <p class="text-xs font-mono text-base-content/40 mb-2">.teamrc.yaml</p>
          <div class="terminal-block rounded-lg p-4 text-sm font-mono leading-relaxed">
            <div class="text-white/40">agents:</div>
            <div class="text-white/40">  - name: reviewer</div>
            <div class="bg-red-500/15 text-red-400 -mx-4 px-4">-     description: Reviews PRs for correctness</div>
            <div class="bg-emerald-500/15 text-emerald-400 -mx-4 px-4">+     description: Reviews PRs for correctness and security</div>
            <div class="bg-emerald-500/15 text-emerald-400 -mx-4 px-4">+     skills: [code-review, security-audit]</div>
            <div class="text-white/40 mt-1">  - name: architect</div>
            <div class="text-white/40">    description: Plans system design</div>
          </div>
        </div>

        <%!-- Separator --%>
        <div class="flex items-center justify-center gap-3">
          <div class="h-px flex-1 bg-base-300/50"></div>
          <span class="text-xs text-base-content/30 font-mono">teamrc apply</span>
          <div class="h-px flex-1 bg-base-300/50"></div>
        </div>

        <%!-- Propagated changes - equal height --%>
        <div class="grid sm:grid-cols-3 gap-3 items-stretch">
          <%!-- Claude Code --%>
          <div class="flex flex-col">
            <p class="text-xs font-mono text-base-content/40 mb-2">.claude/agents/reviewer.md</p>
            <div class="terminal-block rounded-lg p-3 text-xs font-mono leading-relaxed flex-1">
              <div class="text-white/40">---</div>
              <div class="text-white/50">name: reviewer</div>
              <div class="text-emerald-400">description: Reviews PRs for correctness and security</div>
              <div class="text-white/40">---</div>
              <div class="text-white/50 mt-2">You are a code reviewer. Focus on</div>
              <div class="text-white/50">correctness, style consistency, and</div>
              <div class="text-emerald-400">security vulnerabilities.</div>
              <div class="text-white/50 mt-2">## Skills</div>
              <div class="text-emerald-400">- code-review</div>
              <div class="text-emerald-400">- security-audit</div>
            </div>
          </div>

          <%!-- Cursor --%>
          <div class="flex flex-col">
            <p class="text-xs font-mono text-base-content/40 mb-2">.cursor/agents/reviewer.md</p>
            <div class="terminal-block rounded-lg p-3 text-xs font-mono leading-relaxed flex-1">
              <div class="text-white/40">---</div>
              <div class="text-white/50">name: reviewer</div>
              <div class="text-emerald-400">description: Reviews PRs for correctness and security</div>
              <div class="text-white/50">tools:</div>
              <div class="text-white/50 pl-2">- codebase_search</div>
              <div class="text-white/50 pl-2">- read_file</div>
              <div class="text-white/40">---</div>
              <div class="text-white/50 mt-2">You are a code reviewer. Focus on</div>
              <div class="text-white/50">correctness, style consistency, and</div>
              <div class="text-emerald-400">security vulnerabilities.</div>
            </div>
          </div>

          <%!-- Codex --%>
          <div class="flex flex-col">
            <p class="text-xs font-mono text-base-content/40 mb-2">.codex/agents/reviewer.toml</p>
            <div class="terminal-block rounded-lg p-3 text-xs font-mono leading-relaxed flex-1">
              <div class="text-white/50">[agent]</div>
              <div class="text-white/50">name = "reviewer"</div>
              <div class="text-emerald-400">description = "Reviews PRs for</div>
              <div class="text-emerald-400">  correctness and security"</div>
              <div class="text-white/50 mt-2">[agent.skills]</div>
              <div class="text-emerald-400">code-review = true</div>
              <div class="text-emerald-400">security-audit = true</div>
              <div class="text-white/50 mt-2">[agent.tools]</div>
              <div class="text-white/50">sandbox = "full"</div>
            </div>
          </div>
        </div>
      </div>
    </section>

    <%!-- What you get --%>
    <section class="py-20 border-t border-base-300/50">
      <p class="text-xs text-base-content/30 uppercase tracking-widest font-medium mb-3">Features</p>
      <h2 class="text-2xl sm:text-3xl font-bold tracking-tight">What you get</h2>

      <div class="mt-12 grid gap-x-12 gap-y-10 sm:grid-cols-2">
        <div>
          <h3 class="text-sm font-semibold mb-2">Relay sync</h3>
          <p class="text-sm text-base-content/50 leading-relaxed">
            Same team across different repos and projects. The relay keeps everything
            aligned across machines, no shared repo required.
          </p>
        </div>
        <div>
          <h3 class="text-sm font-semibold mb-2">Shared knowledge</h3>
          <p class="text-sm text-base-content/50 leading-relaxed">
            An agent discovers a pattern and writes it down. Every agent on every
            machine knows it by the next sync. No more siloed context.
          </p>
        </div>
        <div>
          <h3 class="text-sm font-semibold mb-2">Format conversion</h3>
          <p class="text-sm text-base-content/50 leading-relaxed">
            One YAML definition, five native output formats. No manual translation
            between platforms.
          </p>
        </div>
        <div>
          <h3 class="text-sm font-semibold mb-2">60+ agents, 50+ skills</h3>
          <p class="text-sm text-base-content/50 leading-relaxed">
            Pre-built catalog across development, infrastructure, quality, and
            research. Use as-is or customize.
          </p>
        </div>
      </div>
    </section>

    <%!-- Web wizard callout --%>
    <section class="py-12 border-t border-base-300/50">
      <div class="flex flex-col sm:flex-row sm:items-center gap-4">
        <div class="flex-1">
          <h2 class="text-sm font-bold tracking-tight">Build your team visually</h2>
          <p class="text-sm text-base-content/50 mt-1 leading-relaxed">
            Browse the agent and skill catalog, pick a template, and configure your
            team - no YAML required. The web wizard generates a
            <code class="font-mono text-xs">.teamrc.yaml</code>
            you can pull down with
            <code class="font-mono text-xs">teamrc sync</code>.
          </p>
        </div>
        <a
          href="/new"
          class="trc-focus shrink-0 inline-flex items-center gap-2 rounded-lg border border-base-300 px-4 py-2 text-sm font-medium text-base-content/60 hover:text-base-content hover:border-base-content/30 transition-colors"
        >
          Open the wizard
          <svg xmlns="http://www.w3.org/2000/svg" class="h-3.5 w-3.5" fill="none" viewBox="0 0 24 24" stroke-width="2" stroke="currentColor">
            <path stroke-linecap="round" stroke-linejoin="round" d="M13.5 4.5 21 12m0 0-7.5 7.5M21 12H3" />
          </svg>
        </a>
      </div>
    </section>

    <%!-- Knowledge sync --%>
    <section class="py-20 border-t border-base-300/50">
      <p class="text-xs text-base-content/30 uppercase tracking-widest font-medium mb-3">Knowledge</p>
      <h2 class="text-2xl sm:text-3xl font-bold tracking-tight">Your agents learn once. Every machine remembers.</h2>
      <div class="mt-6 max-w-2xl space-y-4">
        <p class="text-sm text-base-content/50 leading-relaxed">
          As agents work, they write findings to a shared knowledge file: build quirks,
          architectural decisions, environment-specific fixes. When you sync, knowledge
          from every machine merges automatically. The agent on your VM benefits from
          what the agent on your laptop discovered an hour ago.
        </p>
        <p class="text-sm text-base-content/50 leading-relaxed">
          With the daemon running, this happens in real time over WebSocket. No manual
          copying. No stale context.
        </p>
      </div>
    </section>

    <%!-- Use cases --%>
    <section class="py-20 border-t border-base-300/50">
      <p class="text-xs text-base-content/30 uppercase tracking-widest font-medium mb-3">Use cases</p>
      <h2 class="text-2xl sm:text-3xl font-bold tracking-tight mb-12">Useful when</h2>

      <div class="grid gap-6 sm:grid-cols-2 lg:grid-cols-4">
        <div>
          <h3 class="text-sm font-semibold mb-1">Multiple machines</h3>
          <p class="text-xs text-base-content/40">Laptop, VM, CI - all in sync</p>
        </div>
        <div>
          <h3 class="text-sm font-semibold mb-1">Mixed platforms</h3>
          <p class="text-xs text-base-content/40">Cursor, Codex, Gemini in one team</p>
        </div>
        <div>
          <h3 class="text-sm font-semibold mb-1">Fast onboarding</h3>
          <p class="text-xs text-base-content/40">Full agent setup in one command</p>
        </div>
        <div>
          <h3 class="text-sm font-semibold mb-1">Consistent behavior</h3>
          <p class="text-xs text-base-content/40">Same agents everywhere they run</p>
        </div>
      </div>
    </section>

    <%!-- Bottom CTA --%>
    <section class="py-20 border-t border-base-300/50 text-center">
      <h2 class="text-2xl sm:text-3xl font-bold tracking-tight">
        Try it now.
      </h2>
      <p class="text-sm text-base-content/50 mt-3 mb-10">
        One command. No account required.
      </p>
      <div class="flex justify-center">
        <.terminal_cta tab={@bottom_tab} event="set_bottom_tab" id_suffix="bottom" />
      </div>
    </section>

    <%!-- Footer note --%>
    <div class="pb-8 flex items-center justify-center gap-4">
      <a
        href="https://github.com/teamrc-ai/teamrc"
        target="_blank"
        rel="noopener"
        class="trc-focus inline-flex items-center gap-1.5 text-xs text-base-content/40 hover:text-base-content/60 transition-colors"
        aria-label="GitHub"
      >
        <svg class="h-3.5 w-3.5" viewBox="0 0 16 16" fill="currentColor" aria-hidden="true">
          <path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z" />
        </svg>
        Open source
      </a>
      <span class="text-base-content/20">·</span>
      <span class="text-xs text-base-content/40">No account required for local use</span>
      <span class="text-base-content/20">·</span>
      <span class="text-xs text-base-content/40">Self-host or use the hosted relay</span>
    </div>
    """
  end

  defp tab_command("new"), do: "npx @teamrc/cli init"
  defp tab_command("clone"), do: "npx @teamrc/cli clone trc_cl_NtxNUMHh0WfvS5HOkPpbT_ND"
  defp tab_command("local"), do: "npx @teamrc/cli init --local"

  defp tab_description("new"), do: "Creates a .teamrc.yaml and walks you through setup."
  defp tab_description("clone"), do: "Clones a prebuilt product team into your project."
  defp tab_description("local"), do: "Local only, no relay sync. Define everything in-project."

  attr :tab, :string, required: true
  attr :event, :string, required: true
  attr :id_suffix, :string, required: true

  defp terminal_cta(assigns) do
    ~H"""
    <div class="inline-flex flex-col items-center">
      <div class="flex rounded-md border border-base-300 bg-base-200/40 p-0.5 mb-3">
        <button
          phx-click={@event}
          phx-value-tab="new"
          class={"trc-focus px-3 py-1.5 text-xs font-mono rounded transition-colors " <> if(@tab == "new", do: "bg-white text-base-content", else: "text-base-content/40 hover:text-base-content/60")}
        >
          New team
        </button>
        <button
          phx-click={@event}
          phx-value-tab="clone"
          class={"trc-focus px-3 py-1.5 text-xs font-mono rounded transition-colors " <> if(@tab == "clone", do: "bg-white text-base-content", else: "text-base-content/40 hover:text-base-content/60")}
        >
          Clone a product team
        </button>
        <button
          phx-click={@event}
          phx-value-tab="local"
          class={"trc-focus px-3 py-1.5 text-xs font-mono rounded transition-colors " <> if(@tab == "local", do: "bg-white text-base-content", else: "text-base-content/40 hover:text-base-content/60")}
        >
          Local only
        </button>
      </div>
      <div class="terminal-block rounded-lg overflow-hidden">
        <div class="flex items-center justify-between gap-8 px-5 py-3.5">
          <div class="flex items-center gap-2.5">
            <span class="text-white/30 font-mono text-sm select-none">$</span>
            <code class="text-emerald-400 text-sm font-mono whitespace-nowrap">
              {tab_command(@tab)}
            </code>
          </div>
          <button
            id={"copy-init-" <> @id_suffix}
            phx-click={JS.dispatch("trc:copy", detail: %{text: tab_command(@tab)})}
            class="trc-focus text-white/40 hover:text-white/70 transition-colors rounded p-1"
            aria-label="Copy command"
          >
            <svg xmlns="http://www.w3.org/2000/svg" class="h-4 w-4" fill="none" viewBox="0 0 24 24" stroke-width="1.5" stroke="currentColor">
              <path stroke-linecap="round" stroke-linejoin="round" d="M15.75 17.25v3.375c0 .621-.504 1.125-1.125 1.125h-9.75a1.125 1.125 0 0 1-1.125-1.125V7.875c0-.621.504-1.125 1.125-1.125H6.75a9.06 9.06 0 0 1 1.5.124m7.5 10.376h3.375c.621 0 1.125-.504 1.125-1.125V11.25c0-4.46-3.243-8.161-7.5-8.876a9.06 9.06 0 0 0-1.5-.124H9.375c-.621 0-1.125.504-1.125 1.125v3.5m7.5 10.375H9.375a1.125 1.125 0 0 1-1.125-1.125v-9.25m12 6.625v-1.875a3.375 3.375 0 0 0-3.375-3.375h-1.5a1.125 1.125 0 0 1-1.125-1.125v-1.5a3.375 3.375 0 0 0-3.375-3.375H9.75" />
            </svg>
          </button>
        </div>
      </div>
      <p class="text-xs text-base-content/35 mt-2.5 font-mono">
        {tab_description(@tab)}
      </p>
    </div>
    """
  end
end
